--- keymap.lua
--- Buffer-local keymaps that are active only during a review session.

local M = {}

--- Map of bufnr → list of keymap descriptions set for that buffer.
--- Used to clean up on session end.
M._active = {}

local MAPS = {
  { "n", "ga", "accept_at_cursor", "Accept hunk at cursor" },
  { "n", "gr", "reject_at_cursor", "Reject hunk at cursor" },
  { "n", "gn", "goto_next",        "Go to next hunk" },
  { "n", "gp", "goto_prev",        "Go to previous hunk" },
  { "n", "gA", "accept_all",       "Accept all hunks" },
  { "n", "gR", "reject_all",       "Reject all hunks" },
}

--- Attach buffer-local keymaps for `bufnr`.
--- @param bufnr number
function M.attach(bufnr)
  if M._active[bufnr] then return end

  local session = require("copilot_hunk.session")
  M._active[bufnr] = true

  for _, map in ipairs(MAPS) do
    local mode, lhs, action, desc = map[1], map[2], map[3], map[4]
    vim.keymap.set(mode, lhs, function()
      session[action](bufnr)
    end, {
      buffer = bufnr,
      silent = true,
      desc = "[copilot-hunk] " .. desc,
    })
  end
end

--- Remove all buffer-local keymaps set by this module for `bufnr`.
--- @param bufnr number
function M.detach(bufnr)
  if not M._active[bufnr] then return end

  for _, map in ipairs(MAPS) do
    local mode, lhs = map[1], map[2]
    pcall(vim.keymap.del, mode, lhs, { buffer = bufnr })
  end

  M._active[bufnr] = nil
end

return M
