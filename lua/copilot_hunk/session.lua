--- session.lua
--- Manages per-buffer review sessions.
--- Each session stores base_lines, the computed hunks, and plugin options.

local diff_mod   = require("copilot_hunk.diff")
local hunk_mod   = require("copilot_hunk.hunk")
local ui         = require("copilot_hunk.ui")
local keymap     = require("copilot_hunk.keymap")
local decoration = require("copilot_hunk.decoration")

--- @private
--- Calculate the global hunk offset and total across all active sessions.
--- Counts non-rejected hunks (pending + accepted) to keep counter stable
--- until a hunk is explicitly rejected.
--- @param bufnr number
--- @return number offset  non-rejected hunks in sessions before bufnr in _session_order
--- @return number total   total non-rejected hunks across ALL active sessions
local function global_counts(bufnr)
  local M_ref = require("copilot_hunk.session")
  local offset = 0
  local total  = 0
  local found  = false
  for _, b in ipairs(M_ref._session_order) do
    local s = M_ref._sessions[b]
    if not s then goto continue end
    local cnt = 0
    for _, h in ipairs(s.hunks) do
      if h.status ~= "rejected" then cnt = cnt + 1 end
    end
    if b == bufnr then
      found = true
    elseif not found then
      offset = offset + cnt
    end
    total = total + cnt
    ::continue::
  end
  return offset, total
end

local M = {}

--- Active sessions keyed by bufnr.
--- @type table<number, table>
M._sessions = {}

--- Ordered list of bufnrs with active sessions (registration order).
--- Used for cross-file navigation.
--- @type number[]
M._session_order = {}

--- Start a review session for `bufnr`.
--- `base_lines` must be the buffer content captured *before* the AI edit.
--- The current buffer content is treated as ai_result.
---
--- @param bufnr number
--- @param base_lines string[]
--- @param opts table  plugin options
--- @return boolean  true on success, false if session already active
function M.start(bufnr, base_lines, opts)
  if M._sessions[bufnr] then
    vim.notify(
      "[copilot-hunk] A review session is already active for this buffer.",
      vim.log.levels.WARN
    )
    return false
  end

  local ai_result_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local hunks = diff_mod.diff(base_lines, ai_result_lines)
  if #hunks == 0 then
    vim.notify("[copilot-hunk] No differences found.", vim.log.levels.INFO)
    return false
  end

  M._sessions[bufnr] = {
    bufnr = bufnr,
    base_lines = base_lines,
    ai_result_lines = ai_result_lines,
    hunks = hunks,
    opts = opts,
  }

  table.insert(M._session_order, bufnr)
  decoration.mark(bufnr, #hunks, opts)

  local off, tot = global_counts(bufnr)
  ui.render(bufnr, hunks, opts, off, tot)
  M._rerender_all()
  keymap.attach(bufnr)

  -- Auto-close session when the buffer is deleted.
  vim.api.nvim_buf_attach(bufnr, false, {
    on_detach = function()
      M.stop(bufnr, { silent = true })
    end,
  })

  vim.notify(
    string.format("[copilot-hunk] Review started: %d hunk(s) to review.", #hunks),
    vim.log.levels.INFO
  )
  return true
end

--- End the review session for `bufnr`, cleaning up UI and keymaps.
--- @param bufnr number
--- @param opts? { silent?: boolean }
function M.stop(bufnr, opts)
  local session = M._sessions[bufnr]
  if not session then
    if not (opts and opts.silent) then
      vim.notify("[copilot-hunk] No active session for this buffer.", vim.log.levels.WARN)
    end
    return
  end

  ui.clear(bufnr)
  local sess_opts = session and session.opts or {}
  decoration.unmark(bufnr, sess_opts)
  keymap.detach(bufnr)
  M._sessions[bufnr] = nil

  for i, b in ipairs(M._session_order) do
    if b == bufnr then
      table.remove(M._session_order, i)
      break
    end
  end
end

--- Return the active session for `bufnr`, or nil.
--- @param bufnr number
--- @return table|nil
function M.get(bufnr)
  return M._sessions[bufnr]
end

--- Accept the hunk under the cursor and re-render.
--- @param bufnr number
function M.accept_at_cursor(bufnr)
  local session = M.get(bufnr)
  if not session then return end

  local line = vim.api.nvim_win_get_cursor(0)[1]  -- 1-indexed
  local hunk = hunk_mod.hunk_at_line(line, session.hunks)
  if not hunk then
    vim.notify("[copilot-hunk] No pending hunk at cursor.", vim.log.levels.INFO)
    return
  end

  hunk_mod.accept(hunk)
  local off, tot = global_counts(bufnr)
  ui.render(bufnr, session.hunks, session.opts, off, tot)

  M._check_complete(bufnr, session)
  M._rerender_all()
  local upd_s = M.get(bufnr)
  if upd_s then
    local pend = 0
    for _, h in ipairs(upd_s.hunks) do if h.status == "pending" then pend = pend + 1 end end
    decoration.update(bufnr, pend, upd_s.opts)
  end
  if M.get(bufnr) then
    M.goto_next(bufnr)
  end
end

--- Reject the hunk under the cursor and re-render.
--- @param bufnr number
function M.reject_at_cursor(bufnr)
  local session = M.get(bufnr)
  if not session then return end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = hunk_mod.hunk_at_line(line, session.hunks)
  if not hunk then
    vim.notify("[copilot-hunk] No pending hunk at cursor.", vim.log.levels.INFO)
    return
  end

  hunk_mod.reject(hunk, bufnr, session.hunks)
  local off, tot = global_counts(bufnr)
  ui.render(bufnr, session.hunks, session.opts, off, tot)

  M._check_complete(bufnr, session)
  M._rerender_all()
  local upd_s2 = M.get(bufnr)
  if upd_s2 then
    local pend = 0
    for _, h in ipairs(upd_s2.hunks) do if h.status == "pending" then pend = pend + 1 end end
    decoration.update(bufnr, pend, upd_s2.opts)
  end
  if M.get(bufnr) then
    M.goto_next(bufnr)
  end
end

--- Accept all pending hunks.
--- @param bufnr number
function M.accept_all(bufnr)
  local session = M.get(bufnr)
  if not session then return end

  for _, hunk in ipairs(session.hunks) do
    if hunk.status == "pending" then
      hunk_mod.accept(hunk)
    end
  end

  local off1, tot1 = global_counts(bufnr)
  ui.render(bufnr, session.hunks, session.opts, off1, tot1)
  M._check_complete(bufnr, session)
  M._rerender_all()
  local upd_s3 = M.get(bufnr)
  if upd_s3 then
    local pend = 0
    for _, h in ipairs(upd_s3.hunks) do if h.status == "pending" then pend = pend + 1 end end
    decoration.update(bufnr, pend, upd_s3.opts)
  end
end

--- Reject all pending hunks.
--- @param bufnr number
function M.reject_all(bufnr)
  local session = M.get(bufnr)
  if not session then return end

  -- Reject in order so offset recalculations are applied sequentially.
  for _, hunk in ipairs(session.hunks) do
    if hunk.status == "pending" then
      hunk_mod.reject(hunk, bufnr, session.hunks)
    end
  end

  local off2, tot2 = global_counts(bufnr)
  ui.render(bufnr, session.hunks, session.opts, off2, tot2)
  M._check_complete(bufnr, session)
  M._rerender_all()
  local upd_s4 = M.get(bufnr)
  if upd_s4 then
    local pend = 0
    for _, h in ipairs(upd_s4.hunks) do if h.status == "pending" then pend = pend + 1 end end
    decoration.update(bufnr, pend, upd_s4.opts)
  end
end

--- Jump to the next pending hunk, crossing file boundaries with wrap-around.
--- @param bufnr number
function M.goto_next(bufnr)
  local session = M.get(bufnr)
  if not session then return end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunk, wrapped = hunk_mod.next_hunk_wrap(line, session.hunks)

  if hunk and not wrapped then
    vim.api.nvim_win_set_cursor(0, { hunk.start_after, 0 })
    return
  end

  -- No forward hunk in this file (or would wrap) → try next file if cross_file_navigation enabled.
  local cross = session.opts and session.opts.cross_file_navigation
  if cross == nil then cross = true end
  local next_bufnr = cross and M._next_session_bufnr(bufnr) or nil
  if next_bufnr and next_bufnr ~= bufnr then
    -- Restore buflisted for hidden buffers we loaded via git detection
    if not vim.bo[next_bufnr].buflisted then
      vim.bo[next_bufnr].buflisted = true
    end
    vim.api.nvim_set_current_buf(next_bufnr)
    local ns = M.get(next_bufnr)
    if ns then
      local first = hunk_mod.next_hunk(0, ns.hunks)
      if first then
        vim.api.nvim_win_set_cursor(0, { first.start_after, 0 })
      end
    end
    return
  end

  -- Only one file (or already looped through all) → wrap within this file.
  if hunk then
    vim.api.nvim_win_set_cursor(0, { hunk.start_after, 0 })
  else
    vim.notify("[copilot-hunk] No pending hunks.", vim.log.levels.INFO)
  end
end

--- Jump to the previous pending hunk, crossing file boundaries with wrap-around.
--- @param bufnr number
function M.goto_prev(bufnr)
  local session = M.get(bufnr)
  if not session then return end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunk, wrapped = hunk_mod.prev_hunk_wrap(line, session.hunks)

  if hunk and not wrapped then
    vim.api.nvim_win_set_cursor(0, { hunk.start_after, 0 })
    return
  end

  -- No backward hunk → try previous file if cross_file_navigation enabled.
  local cross = session.opts and session.opts.cross_file_navigation
  if cross == nil then cross = true end
  local prev_bufnr = cross and M._prev_session_bufnr(bufnr) or nil
  if prev_bufnr and prev_bufnr ~= bufnr then
    if not vim.bo[prev_bufnr].buflisted then
      vim.bo[prev_bufnr].buflisted = true
    end
    vim.api.nvim_set_current_buf(prev_bufnr)
    local ps = M.get(prev_bufnr)
    if ps then
      local last = hunk_mod.prev_hunk(math.huge, ps.hunks)
      if last then
        vim.api.nvim_win_set_cursor(0, { last.start_after, 0 })
      end
    end
    return
  end

  -- Wrap within this file.
  if hunk then
    vim.api.nvim_win_set_cursor(0, { hunk.start_after, 0 })
  else
    vim.notify("[copilot-hunk] No pending hunks.", vim.log.levels.INFO)
  end
end

--- @private
--- Check whether all hunks have been resolved and auto-stop the session.
function M._check_complete(bufnr, session)
  for _, h in ipairs(session.hunks) do
    if h.status == "pending" then return end
  end

  M.stop(bufnr)
  vim.notify("[copilot-hunk] All hunks reviewed. Session ended.", vim.log.levels.INFO)
end

--- @private
--- Re-render all active sessions with globally-correct hunk counters.
--- Call this after any accept/reject to keep counters in sync across files.
function M._rerender_all()
  for _, b in ipairs(M._session_order) do
    local s = M._sessions[b]
    if s then
      local off, tot = global_counts(b)
      ui.render(b, s.hunks, s.opts, off, tot)
    end
  end
end

--- @private
--- Return the bufnr of the next session in registration order after `bufnr`.
--- Skips sessions with no pending hunks. Wraps around.
--- @param bufnr number
--- @return number|nil
function M._next_session_bufnr(bufnr)
  local n = #M._session_order
  if n <= 1 then return nil end

  local idx = nil
  for i, b in ipairs(M._session_order) do
    if b == bufnr then idx = i; break end
  end
  if not idx then return nil end

  for offset = 1, n - 1 do
    local next_idx = (idx - 1 + offset) % n + 1
    local next_buf = M._session_order[next_idx]
    local s = M._sessions[next_buf]
    if s then
      for _, h in ipairs(s.hunks) do
        if h.status == "pending" then return next_buf end
      end
    end
  end
  return nil
end

--- @private
--- Return the bufnr of the previous session in registration order before `bufnr`.
--- @param bufnr number
--- @return number|nil
function M._prev_session_bufnr(bufnr)
  local n = #M._session_order
  if n <= 1 then return nil end

  local idx = nil
  for i, b in ipairs(M._session_order) do
    if b == bufnr then idx = i; break end
  end
  if not idx then return nil end

  for offset = 1, n - 1 do
    local prev_idx = (idx - 1 - offset + n) % n + 1
    local prev_buf = M._session_order[prev_idx]
    local s = M._sessions[prev_buf]
    if s then
      for _, h in ipairs(s.hunks) do
        if h.status == "pending" then return prev_buf end
      end
    end
  end
  return nil
end

--- Accept all pending hunks in ALL active sessions across all files.
function M.accept_all_global()
  -- Snapshot the order list: accept_all → _check_complete → stop removes from _session_order.
  local order = vim.deepcopy(M._session_order)
  for _, bufnr in ipairs(order) do
    M.accept_all(bufnr)
  end
end

--- Reject all pending hunks in ALL active sessions across all files.
function M.reject_all_global()
  local order = vim.deepcopy(M._session_order)
  for _, bufnr in ipairs(order) do
    M.reject_all(bufnr)
  end
end

return M
