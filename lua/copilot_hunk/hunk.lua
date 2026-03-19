--- hunk.lua
--- Hunk operations: accept and reject.
--- Reject replaces the buffer range with base_lines content and
--- recalculates the line offsets of all subsequent pending hunks.

local M = {}

--- Accept a hunk (no-op on the buffer; only flips the status flag).
--- @param hunk Hunk
function M.accept(hunk)
  hunk.status = "accepted"
end

--- Reject a hunk: restore the base lines into the buffer and shift
--- all later hunks so their after-positions remain valid.
--- @param hunk Hunk
--- @param bufnr number
--- @param all_hunks Hunk[]  full list so later hunks can be adjusted
function M.reject(hunk, bufnr, all_hunks)
  -- nvim_buf_set_lines is 0-indexed, end is exclusive.
  -- hunk.start_after / end_after are 1-indexed, inclusive.
  if hunk.type == "add" then
    -- Remove the added lines: [start_after-1, end_after) in 0-indexed.
    vim.api.nvim_buf_set_lines(bufnr, hunk.start_after - 1, hunk.end_after, false, {})
  elseif hunk.type == "delete" then
    -- Re-insert before_lines AFTER line start_after (1-indexed).
    -- 0-indexed insert point = start_after.
    local ins = hunk.start_after
    vim.api.nvim_buf_set_lines(bufnr, ins, ins, false, hunk.before_lines)
  else
    -- Change: replace the after range with the before lines.
    vim.api.nvim_buf_set_lines(bufnr, hunk.start_after - 1, hunk.end_after, false, hunk.before_lines)
  end

  hunk.status = "rejected"

  -- Recalculate after-positions of all hunks that come after this one.
  -- delta = (number of before_lines restored) - (number of after_lines removed)
  local delta = #hunk.before_lines - #hunk.after_lines
  if delta ~= 0 then
    for _, h in ipairs(all_hunks) do
      if h.id > hunk.id and h.status == "pending" then
        h.start_after = h.start_after + delta
        h.end_after   = h.end_after   + delta
      end
    end
  end
end

--- Return the hunk that contains the given (1-indexed) buffer line,
--- or nil if no pending hunk covers that line.
--- @param line number  1-indexed current line
--- @param hunks Hunk[]
--- @return Hunk|nil
function M.hunk_at_line(line, hunks)
  for _, h in ipairs(hunks) do
    if h.status == "pending" then
      local s = h.start_after
      -- A pure-delete hunk occupies a single virtual position.
      local e = math.max(h.end_after, h.start_after)
      if line >= s and line <= e then
        return h
      end
    end
  end
  return nil
end

--- Return the next pending hunk after `line`, or nil.
--- @param line number
--- @param hunks Hunk[]
--- @return Hunk|nil
function M.next_hunk(line, hunks)
  for _, h in ipairs(hunks) do
    if h.status == "pending" and h.start_after > line then
      return h
    end
  end
  return nil
end

--- Return the previous pending hunk before `line`, or nil.
--- @param line number
--- @param hunks Hunk[]
--- @return Hunk|nil
function M.prev_hunk(line, hunks)
  local result = nil
  for _, h in ipairs(hunks) do
    if h.status == "pending" and h.start_after < line then
      result = h
    end
  end
  return result
end

--- Return the next pending hunk with wrap-around.
--- @param line number
--- @param hunks Hunk[]
--- @return Hunk|nil, boolean  (hunk, wrapped)
function M.next_hunk_wrap(line, hunks)
  local h = M.next_hunk(line, hunks)
  if h then return h, false end
  -- Wrap: return the first pending hunk (even if before current line).
  for _, hunk in ipairs(hunks) do
    if hunk.status == "pending" then
      return hunk, true
    end
  end
  return nil, false
end

--- Return the previous pending hunk with wrap-around.
--- @param line number
--- @param hunks Hunk[]
--- @return Hunk|nil, boolean  (hunk, wrapped)
function M.prev_hunk_wrap(line, hunks)
  local h = M.prev_hunk(line, hunks)
  if h then return h, false end
  -- Wrap: return the last pending hunk.
  local last = nil
  for _, hunk in ipairs(hunks) do
    if hunk.status == "pending" then
      last = hunk
    end
  end
  return last, last ~= nil
end

return M
