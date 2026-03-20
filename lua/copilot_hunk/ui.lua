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
    -- Line-level backgrounds (muted, lighter)
    CopilotHunkAdd         = { bg = "#1a2e1a" },
    CopilotHunkDelete      = { bg = "#2e1a1a" },
    CopilotHunkChange      = { bg = "#2a2410" },

    -- Inline content highlights (vivid, darker - rendered on top of line bg)
    CopilotHunkAddText     = { bg = "#2d5230" },
    CopilotHunkDeleteText  = { bg = "#522d2d" },
    CopilotHunkChangeText  = { bg = "#4a3c18" },

    -- For char-level inline diff within change hunks (even more vivid)
    CopilotHunkChangeChar  = { bg = "#6b5420" },
    CopilotHunkDeleteChar  = { bg = "#6b2020" },

    -- Counter virt_text
    CopilotHunkCount       = { fg = "#888888", italic = true },

    -- Sign column
    CopilotHunkAddSign     = { fg = "#3fb950", bold = true },
    CopilotHunkDeleteSign  = { fg = "#f85149", bold = true },
    CopilotHunkChangeSign  = { fg = "#d29922", bold = true },
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
--- @param global_offset? number  non-rejected hunk count in sessions before this one
--- @param global_total?  number  total non-rejected hunks across all active sessions
function M.render(bufnr, hunks, opts, global_offset, global_total)
  M.clear(bufnr)
  local ns = M.ns()
  local show_signs = opts and opts.signs ~= false

  for _, hunk in ipairs(hunks) do
    if hunk.status ~= "rejected" then
      M._render_hunk(bufnr, ns, hunk, show_signs)
    end
  end

  M._render_hunk_counters(bufnr, ns, hunks, global_offset, global_total)
end

--- @private
function M._render_hunk(bufnr, ns, hunk, show_signs)
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  if hunk.type == "add" then
    -- Highlight each added line with a green background + content overlay.
    for i = hunk.start_after, hunk.end_after do
      local row = i - 1  -- 0-indexed
      if row < line_count then
        vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
          line_hl_group = "CopilotHunkAdd",
          sign_text = show_signs and "▎" or nil,
          sign_hl_group = show_signs and "CopilotHunkAddSign" or nil,
          priority = 100,
        })
        local line_len = #(vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or "")
        vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
          end_row = row,
          end_col = line_len,
          hl_group = "CopilotHunkAddText",
          hl_eol = true,
          priority = 101,
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

    -- Highlight each changed line with a yellow background + content overlay.
    for i = hunk.start_after, hunk.end_after do
      local row = i - 1
      if row < line_count then
        vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
          line_hl_group = "CopilotHunkChange",
          sign_text = show_signs and "▎" or nil,
          sign_hl_group = show_signs and "CopilotHunkChangeSign" or nil,
          priority = 100,
        })
        local line_len = #(vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or "")
        vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
          end_row = row,
          end_col = line_len,
          hl_group = "CopilotHunkChangeText",
          hl_eol = true,
          priority = 101,
        })
      end
    end

    -- Character-level inline diff for changed lines.
    M._render_char_diff(bufnr, ns, hunk)
  end
end

--- Character-level inline diff highlighting for "change" hunks.
--- Compares before/after lines character-by-character and highlights
--- the differing characters with CopilotHunkChangeChar.
--- @private
function M._render_char_diff(bufnr, ns, hunk)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local pairs_count = math.min(#hunk.before_lines, #hunk.after_lines)

  for i = 1, pairs_count do
    local before = hunk.before_lines[i]
    local after  = hunk.after_lines[i]
    local row    = hunk.start_after - 1 + (i - 1)  -- 0-indexed

    if row >= line_count then break end

    -- Split strings into characters and diff them via vim.diff
    local b_text = before:gsub(".", function(c) return c .. "\n" end)
    local a_text = after:gsub(".",  function(c) return c .. "\n" end)

    local ok, indices = pcall(vim.diff, b_text, a_text, { result_type = "indices" })
    if not ok or not indices then return end

    for _, idx in ipairs(indices) do
      local start_a, count_a = idx[3], idx[4]
      if count_a > 0 then
        local col_start = start_a - 1  -- 0-indexed
        local col_end   = col_start + count_a
        -- Clamp to actual line length
        local line_len = #after
        col_end = math.min(col_end, line_len)
        if col_start < col_end then
          vim.api.nvim_buf_set_extmark(bufnr, ns, row, col_start, {
            end_row   = row,
            end_col   = col_end,
            hl_group  = "CopilotHunkChangeChar",
            priority  = 120,
          })
        end
      end
    end
  end
end

--- Render [n/N] hunk counter as EOL virtual text on each hunk's first line.
--- Uses global_offset/global_total when provided (cross-file counter).
--- Falls back to local-only counting if globals are not supplied.
--- @param global_offset? number
--- @param global_total?  number
--- @private
function M._render_hunk_counters(bufnr, ns, hunks, global_offset, global_total)
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  -- Count non-rejected hunks for fallback local total.
  local fallback_total = 0
  for _, h in ipairs(hunks) do
    if h.status ~= "rejected" then fallback_total = fallback_total + 1 end
  end

  local total  = global_total  or fallback_total
  local offset = global_offset or 0
  local local_idx = 0

  for _, h in ipairs(hunks) do
    if h.status ~= "rejected" then
      local_idx = local_idx + 1
      if h.status == "pending" then
        local global_idx = offset + local_idx
        local row = math.max(h.start_after - 1, 0)  -- 0-indexed
        if row < line_count then
          vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
            virt_text = { { string.format("[%d/%d]", global_idx, total), "CopilotHunkCount" } },
            virt_text_pos = "eol",
            priority = 90,
          })
        end
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
