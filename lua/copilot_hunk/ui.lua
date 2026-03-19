--- ui.lua
--- Renders inline diff highlights using extmarks (VSCode-style full-line color).
--- Added lines  → green background on the actual buffer line.
--- Deleted lines → red virtual lines shown above the insertion point.
--- Changed lines → yellow background on the actual buffer line, with the
---                 original lines shown as red virtual lines above.

local M = {}

local NS_NAME = "copilot_hunk"

--- Lazily create (or reuse) the extmark namespace.
--- @return number
function M.ns()
  return vim.api.nvim_create_namespace(NS_NAME)
end

--- Define highlight groups if they have not been defined yet.
--- Callers (setup) may override these by calling nvim_set_hl after setup().
function M.define_highlights(opts)
  opts = opts or {}

  local defaults = {
    CopilotHunkAdd = { bg = "#1e3a2f", bold = false },
    CopilotHunkDelete = { bg = "#3a1e1e", bold = false },
    CopilotHunkChange = { bg = "#2e2a12", bold = false },
    CopilotHunkAddSign = { fg = "#3fb950", bold = true },
    CopilotHunkDeleteSign = { fg = "#f85149", bold = true },
    CopilotHunkChangeSign = { fg = "#d29922", bold = true },
  }

  local overrides = {
    CopilotHunkAdd    = opts.add    or {},
    CopilotHunkDelete = opts.delete or {},
    CopilotHunkChange = opts.change or {},
  }

  for name, def in pairs(defaults) do
    local override = overrides[name] or {}
    -- `default = true` means the colorscheme can override these; we always
    -- (re-)register them so they survive `:colorscheme` changes.
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", def, override, { default = true }))
  end
end

--- Clear all extmarks for a buffer managed by this plugin.
--- @param bufnr number
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns(), 0, -1)
end

--- Render all pending (and re-render accepted/rejected) hunks in the buffer.
--- @param bufnr number
--- @param hunks Hunk[]
--- @param opts table  plugin options
function M.render(bufnr, hunks, opts)
  M.clear(bufnr)
  local ns = M.ns()
  local show_signs = opts and opts.signs ~= false

  for _, hunk in ipairs(hunks) do
    if hunk.status ~= "rejected" then
      M._render_hunk(bufnr, ns, hunk, show_signs)
    end
  end
end

--- @private
function M._render_hunk(bufnr, ns, hunk, show_signs)
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  if hunk.type == "add" then
    -- Highlight each added line with a green background.
    for i = hunk.start_after, hunk.end_after do
      local row = i - 1  -- 0-indexed
      if row < line_count then
        vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
          line_hl_group = "CopilotHunkAdd",
          sign_text = show_signs and "▎" or nil,
          sign_hl_group = show_signs and "CopilotHunkAddSign" or nil,
          priority = 100,
        })
      end
    end

  elseif hunk.type == "delete" then
    -- Show deleted lines as virtual lines at the deletion point.
    -- start_after is the 1-indexed line AFTER WHICH these lines were removed.
    -- anchor_row (0-indexed) = start_after → the row just after the deletion point.
    local virt = M._build_virt_lines(hunk.before_lines, "CopilotHunkDelete")
    local anchor_row = hunk.start_after  -- 0-indexed row after deletion point
    local above = true
    if anchor_row >= line_count then
      -- Deletion at end of file: attach below the last line.
      anchor_row = line_count - 1
      above = false
    end
    vim.api.nvim_buf_set_extmark(bufnr, ns, anchor_row, 0, {
      virt_lines = virt,
      virt_lines_above = above,
      sign_text = show_signs and "▎" or nil,
      sign_hl_group = show_signs and "CopilotHunkDeleteSign" or nil,
      priority = 100,
    })

  elseif hunk.type == "change" then
    -- Show original lines as virtual lines above the first changed line.
    local anchor_row = hunk.start_after - 1  -- 0-indexed
    if anchor_row < line_count then
      local virt = M._build_virt_lines(hunk.before_lines, "CopilotHunkDelete")
      vim.api.nvim_buf_set_extmark(bufnr, ns, anchor_row, 0, {
        virt_lines = virt,
        virt_lines_above = true,
        priority = 100,
      })
    end

    -- Highlight each changed line with a yellow background.
    for i = hunk.start_after, hunk.end_after do
      local row = i - 1
      if row < line_count then
        vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
          line_hl_group = "CopilotHunkChange",
          sign_text = show_signs and "▎" or nil,
          sign_hl_group = show_signs and "CopilotHunkChangeSign" or nil,
          priority = 100,
        })
      end
    end
  end
end

--- Build a virt_lines table from a list of text lines and a highlight group.
--- @param lines string[]
--- @param hl_group string
--- @return table
function M._build_virt_lines(lines, hl_group)
  local virt = {}
  for _, text in ipairs(lines) do
    -- Each virt_line is a list of {text, hl_group} chunks.
    -- We use a single chunk that pads to the full window width with the
    -- background colour so the row looks fully coloured.
    virt[#virt + 1] = { { text .. string.rep(" ", math.max(0, 120 - #text)), hl_group } }
  end
  return virt
end

return M
