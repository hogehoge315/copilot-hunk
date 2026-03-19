--- plugin/copilot_hunk.lua
--- Loaded automatically by Neovim on startup.
--- Registers user commands and runs default setup.

if vim.fn.has("nvim-0.11") == 0 then
  vim.notify("[copilot-hunk] Neovim >= 0.11 is required.", vim.log.levels.ERROR)
  return
end

-- Guard against double-loading.
if vim.g.loaded_copilot_hunk then return end
vim.g.loaded_copilot_hunk = true

-- Run setup with defaults (user may call setup() again to override).
require("copilot_hunk").setup()

local function buf()
  return vim.api.nvim_get_current_buf()
end

vim.api.nvim_create_user_command("CopilotHunkAccept", function()
  require("copilot_hunk.session").accept_at_cursor(buf())
end, { desc = "Accept hunk at cursor" })

vim.api.nvim_create_user_command("CopilotHunkReject", function()
  require("copilot_hunk.session").reject_at_cursor(buf())
end, { desc = "Reject hunk at cursor" })

vim.api.nvim_create_user_command("CopilotHunkNext", function()
  require("copilot_hunk.session").goto_next(buf())
end, { desc = "Go to next hunk" })

vim.api.nvim_create_user_command("CopilotHunkPrev", function()
  require("copilot_hunk.session").goto_prev(buf())
end, { desc = "Go to previous hunk" })

vim.api.nvim_create_user_command("CopilotHunkAcceptAll", function()
  require("copilot_hunk.session").accept_all(buf())
end, { desc = "Accept all hunks" })

vim.api.nvim_create_user_command("CopilotHunkRejectAll", function()
  require("copilot_hunk.session").reject_all(buf())
end, { desc = "Reject all hunks" })

vim.api.nvim_create_user_command("CopilotHunkEnd", function()
  require("copilot_hunk").end_session(buf())
end, { desc = "End the current review session" })

vim.api.nvim_create_user_command("CopilotHunkAcceptAllFiles", function()
  require("copilot_hunk.session").accept_all_global()
end, { desc = "Accept all hunks in all active sessions" })

vim.api.nvim_create_user_command("CopilotHunkRejectAllFiles", function()
  require("copilot_hunk.session").reject_all_global()
end, { desc = "Reject all hunks in all active sessions" })
