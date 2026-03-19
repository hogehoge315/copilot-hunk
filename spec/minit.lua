--- spec/minit.lua
--- Minimal Neovim init for running busted tests headlessly.
--- Usage: nvim --headless -l spec/minit.lua

-- Add project lua/ to the runtime path so `require("copilot_hunk.*")` works.
local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(project_root)

-- Bootstrap busted if not already on the path.
-- Expects busted to be installed via luarocks: luarocks install busted
local ok, busted = pcall(require, "busted.runner")
if not ok then
  vim.notify("busted not found. Install with: luarocks install busted", vim.log.levels.ERROR)
  vim.cmd("cquit 1")
  return
end

busted({
  standalone = false,
  pattern    = "_spec%.lua$",
  ROOT       = { project_root .. "/spec" },
})
