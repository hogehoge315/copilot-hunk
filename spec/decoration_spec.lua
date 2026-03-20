--- spec/decoration_spec.lua
--- Tests for decoration.lua diagnostic namespace config (Issue #35).

describe("decoration", function()
  local init, decoration

  before_each(function()
    for _, mod in ipairs({
      "copilot_hunk", "copilot_hunk.session", "copilot_hunk.ui",
      "copilot_hunk.diff", "copilot_hunk.hunk", "copilot_hunk.keymap", "copilot_hunk.decoration"
    }) do
      package.loaded[mod] = nil
    end
    init = require("copilot_hunk")
    decoration = require("copilot_hunk.decoration")
    init.setup({ enable_auto_snapshot = false, keymaps = false, signs = false, highlights = {} })
  end)

  it("setup configures diagnostic namespace to suppress all visuals", function()
    local ns = vim.api.nvim_create_namespace("copilot_hunk_diag")
    local cfg = vim.diagnostic.config(nil, ns)
    assert.is_false(cfg.virtual_text)
    assert.is_false(cfg.signs)
    assert.is_false(cfg.underline)
    assert.is_false(cfg.float)
    assert.is_false(cfg.update_in_insert)
    assert.is_false(cfg.severity_sort)
  end)

  it("mark sets one diagnostic entry for the buffer", function()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello" })

    decoration.mark(bufnr, 2, {})

    local ns = vim.api.nvim_create_namespace("copilot_hunk_diag")
    local diags = vim.diagnostic.get(bufnr, { namespace = ns })
    assert.equal(1, #diags)
    assert.equal(vim.diagnostic.severity.HINT, diags[1].severity)
    assert.truthy(diags[1].message:find("2 hunk"))
  end)

  it("unmark clears diagnostics for the buffer", function()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello" })

    decoration.mark(bufnr, 1, {})
    decoration.unmark(bufnr, {})

    local ns = vim.api.nvim_create_namespace("copilot_hunk_diag")
    local diags = vim.diagnostic.get(bufnr, { namespace = ns })
    assert.equal(0, #diags)
  end)
end)
