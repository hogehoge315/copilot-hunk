--- decoration.lua
--- Handles UI decorations for active sessions.
--- Provides: diagnostic API, buffer variable, User event, optional WinBar.

local M = {}

local _ns = nil  -- diagnostic namespace

--- Initialize decoration subsystem. Called from setup().
function M.setup()
  _ns = vim.api.nvim_create_namespace("copilot_hunk_diag")
  -- Suppress ALL visual output for our diagnostic namespace.
  -- The entries exist only so nvim-tree / neo-tree / statusline can read them
  -- via vim.diagnostic.get(). No popups, no signs, no virtual text ever.
  vim.diagnostic.config({
    virtual_text     = false,
    signs            = false,
    underline        = false,
    float            = false,
    update_in_insert = false,
    severity_sort    = false,
  }, _ns)
end

--- Mark a buffer as having AI-pending hunks.
--- @param bufnr number
--- @param pending_count number
--- @param opts table  plugin opts
function M.mark(bufnr, pending_count, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  opts = opts or {}
  local icon = (opts.decorations and opts.decorations.icon) or "🤖"

  vim.b[bufnr].copilot_hunk_active = true
  vim.b[bufnr].copilot_hunk_count  = pending_count

  if _ns then
    vim.diagnostic.set(_ns, bufnr, {
      {
        lnum     = 0,
        col      = 0,
        severity = vim.diagnostic.severity.HINT,
        message  = string.format("AI変更あり (%d hunk)", pending_count),
        source   = "copilot-hunk",
      },
    })
  end

  local show_winbar = opts.decorations and opts.decorations.winbar
  if show_winbar then
    local label = string.format(" %s AI変更あり [%d]", icon, pending_count)
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
      local cur = vim.wo[win].winbar or ""
      if cur == "" or cur:find("copilot%-hunk", 1, true) then
        vim.wo[win].winbar = "%#CopilotHunkCount#" .. label .. "%*"
      end
    end
  end

  vim.api.nvim_exec_autocmds("User", {
    pattern  = "CopilotHunkSessionChanged",
    data     = { bufnr = bufnr, active = true, pending = pending_count },
    modeline = false,
  })
end

--- Remove decorations when session ends or all hunks resolved.
--- @param bufnr number
--- @param opts? table
function M.unmark(bufnr, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  opts = opts or {}

  vim.b[bufnr].copilot_hunk_active = false
  vim.b[bufnr].copilot_hunk_count  = 0

  if _ns then
    vim.diagnostic.reset(_ns, bufnr)
  end

  local show_winbar = opts.decorations and opts.decorations.winbar
  if show_winbar then
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
      local cur = vim.wo[win].winbar or ""
      if cur:find("copilot%-hunk", 1, true) then
        vim.wo[win].winbar = ""
      end
    end
  end

  vim.api.nvim_exec_autocmds("User", {
    pattern  = "CopilotHunkSessionChanged",
    data     = { bufnr = bufnr, active = false, pending = 0 },
    modeline = false,
  })
end

--- Update decoration after accept/reject.
--- @param bufnr number
--- @param pending_count number
--- @param opts table
function M.update(bufnr, pending_count, opts)
  if pending_count > 0 then
    M.mark(bufnr, pending_count, opts)
  else
    M.unmark(bufnr, opts)
  end
end

--- Statusline/tabline helper.
--- Returns "🤖 N" when current buffer has pending AI hunks, else "".
function M.statusline_component()
  local bufnr = vim.api.nvim_get_current_buf()
  local active = vim.b[bufnr].copilot_hunk_active
  local count  = vim.b[bufnr].copilot_hunk_count or 0
  if active and count > 0 then
    return string.format("🤖 %d", count)
  end
  return ""
end

return M
