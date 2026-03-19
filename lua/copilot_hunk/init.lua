--- init.lua
--- Public API for copilot-hunk.
---
--- Typical usage (called by an external AI tool such as Copilot CLI):
---
---   -- Before the AI edits the buffer:
---   local base = require("copilot_hunk").snapshot(bufnr)
---
---   -- After the AI has written new content to the buffer:
---   require("copilot_hunk").start_session(bufnr, base)
---
---   -- Optionally end manually (auto-ends when all hunks are reviewed):
---   require("copilot_hunk").end_session(bufnr)

local M = {}

--- Default configuration.
M._opts = {
  highlights = {
    add    = {},
    delete = {},
    change = {},
  },
  signs   = true,
  keymaps = true,
}

--- Configure the plugin.  Call once in your init.lua / lazy spec.
---
--- @param user_opts? table
---   highlights.add    table  nvim_set_hl attrs for added lines
---   highlights.delete table  nvim_set_hl attrs for deleted lines
---   highlights.change table  nvim_set_hl attrs for changed lines
---   signs             boolean  show sign-column markers (default true)
---   keymaps           boolean  install default keymaps (default true)
function M.setup(user_opts)
  M._opts = vim.tbl_deep_extend("force", M._opts, user_opts or {})

  local ui = require("copilot_hunk.ui")
  ui.define_highlights(M._opts.highlights)

  -- Re-apply highlights after every colorscheme change.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("CopilotHunkHL", { clear = true }),
    callback = function()
      -- Reset so define_highlights re-creates them with correct contrast.
      for _, name in ipairs({
        "CopilotHunkAdd", "CopilotHunkDelete", "CopilotHunkChange",
        "CopilotHunkAddSign", "CopilotHunkDeleteSign", "CopilotHunkChangeSign",
      }) do
        vim.api.nvim_set_hl(0, name, {})
      end
      ui.define_highlights(M._opts.highlights)
    end,
  })
end

--- Capture the current content of `bufnr` as a snapshot string array.
--- Call this *before* triggering the AI edit.
---
--- @param bufnr? number  defaults to current buffer (0)
--- @return string[]
function M.snapshot(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

--- Start a review session.
--- `base_lines` is the snapshot taken before the AI edit.
--- The buffer must already contain the AI-edited content when this is called.
---
--- @param bufnr? number   defaults to current buffer
--- @param base_lines string[]
--- @return boolean  true if session started successfully
function M.start_session(bufnr, base_lines)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local session = require("copilot_hunk.session")
  return session.start(bufnr, base_lines, M._opts)
end

--- End the active review session for `bufnr`, discarding any pending hunks.
---
--- @param bufnr? number  defaults to current buffer
function M.end_session(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local session = require("copilot_hunk.session")
  session.stop(bufnr)
end

--- Return true if there is an active session for `bufnr`.
--- @param bufnr? number
--- @return boolean
function M.has_session(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local session = require("copilot_hunk.session")
  return session.get(bufnr) ~= nil
end

return M
