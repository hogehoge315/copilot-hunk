--- diff.lua
--- Wraps vim.diff() to produce a list of Hunk objects from two sets of lines.

local M = {}

--- @class Hunk
--- @field id number
--- @field start_before number  1-indexed start line in base
--- @field end_before number    1-indexed end line in base (inclusive)
--- @field start_after number   1-indexed start line in ai_result
--- @field end_after number     1-indexed end line in ai_result (inclusive)
--- @field before_lines string[]
--- @field after_lines string[]
--- @field status "pending"|"accepted"|"rejected"
--- @field type "add"|"delete"|"change"

--- Generate a list of Hunks by diffing base_lines against ai_result_lines.
--- @param base_lines string[]
--- @param ai_result_lines string[]
--- @return Hunk[]
function M.diff(base_lines, ai_result_lines)
  -- Normalize: a buffer with only one empty line is equivalent to empty content.
  if #base_lines == 1 and base_lines[1] == "" then base_lines = {} end
  if #ai_result_lines == 1 and ai_result_lines[1] == "" then ai_result_lines = {} end

  local base_text = #base_lines > 0 and (table.concat(base_lines, "\n") .. "\n") or ""
  local ai_text = #ai_result_lines > 0 and (table.concat(ai_result_lines, "\n") .. "\n") or ""

  -- vim.diff with result_type="indices" returns a list of
  -- { start_a, count_a, start_b, count_b } tables (1-indexed).
  local indices = vim.diff(base_text, ai_text, { result_type = "indices" })

  local hunks = {}
  for id, idx in ipairs(indices) do
    local start_a, count_a, start_b, count_b = idx[1], idx[2], idx[3], idx[4]

    -- vim.diff uses 0 for "no lines on this side" (pure add/delete)
    -- Normalise to inclusive 1-indexed ranges; end < start means empty range.
    local end_a = start_a + count_a - 1
    local end_b = start_b + count_b - 1

    local before = {}
    for i = start_a, end_a do
      before[#before + 1] = base_lines[i] or ""
    end

    local after = {}
    for i = start_b, end_b do
      after[#after + 1] = ai_result_lines[i] or ""
    end

    local hunk_type
    if count_a == 0 then
      hunk_type = "add"
    elseif count_b == 0 then
      hunk_type = "delete"
    else
      hunk_type = "change"
    end

    hunks[#hunks + 1] = {
      id = id,
      start_before = start_a,
      end_before = end_a,
      start_after = start_b,
      end_after = end_b,
      before_lines = before,
      after_lines = after,
      status = "pending",
      type = hunk_type,
    }
  end

  return hunks
end

return M
