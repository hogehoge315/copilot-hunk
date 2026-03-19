--- session.lua
--- Manages per-buffer review sessions.
--- Each session stores base_lines, the computed hunks, and plugin options.

local diff_mod = require("copilot_hunk.diff")
local hunk_mod = require("copilot_hunk.hunk")
local ui       = require("copilot_hunk.ui")
local keymap   = require("copilot_hunk.keymap")

local M = {}

--- Active sessions keyed by bufnr.
--- @type table<number, table>
M._sessions = {}

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

  ui.render(bufnr, hunks, opts)
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
  keymap.detach(bufnr)
  M._sessions[bufnr] = nil
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
  ui.render(bufnr, session.hunks, session.opts)
  M._check_complete(bufnr, session)
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
  ui.render(bufnr, session.hunks, session.opts)
  M._check_complete(bufnr, session)
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

  ui.render(bufnr, session.hunks, session.opts)
  M._check_complete(bufnr, session)
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

  ui.render(bufnr, session.hunks, session.opts)
  M._check_complete(bufnr, session)
end

--- Jump to the next pending hunk.
--- @param bufnr number
function M.goto_next(bufnr)
  local session = M.get(bufnr)
  if not session then return end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = hunk_mod.next_hunk(line, session.hunks)
  if hunk then
    vim.api.nvim_win_set_cursor(0, { hunk.start_after, 0 })
  else
    vim.notify("[copilot-hunk] No next hunk.", vim.log.levels.INFO)
  end
end

--- Jump to the previous pending hunk.
--- @param bufnr number
function M.goto_prev(bufnr)
  local session = M.get(bufnr)
  if not session then return end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = hunk_mod.prev_hunk(line, session.hunks)
  if hunk then
    vim.api.nvim_win_set_cursor(0, { hunk.start_after, 0 })
  else
    vim.notify("[copilot-hunk] No previous hunk.", vim.log.levels.INFO)
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

return M
