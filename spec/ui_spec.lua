local ui

before_each(function()
  for _, mod in ipairs({
    "copilot_hunk", "copilot_hunk.ui",
  }) do
    package.loaded[mod] = nil
  end
  ui = require("copilot_hunk.ui")
  ui.define_highlights()
end)

--- Helper: create a scratch buffer with given lines.
local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

--- Helper: build a minimal hunk table.
local function make_hunk(opts)
  return {
    id           = opts.id or 1,
    type         = opts.type or "add",
    status       = opts.status or "pending",
    start_before = opts.start_before or 0,
    end_before   = opts.end_before or 0,
    start_after  = opts.start_after or 1,
    end_after    = opts.end_after or 1,
    before_lines = opts.before_lines or {},
    after_lines  = opts.after_lines or {},
  }
end

local OPTS = { signs = false }

-- ──────────────────────────────────────────────
-- Bug A: accepted/rejected hunks should NOT be rendered
-- ──────────────────────────────────────────────

describe("ui.render – hunk visibility by status", function()
  it("renders extmarks for a pending hunk", function()
    local buf = make_buf({ "hello" })
    local ns  = ui.ns()
    local hunks = {
      make_hunk({ id = 1, type = "add", status = "pending", start_after = 1, end_after = 1, after_lines = { "hello" } }),
    }
    ui.render(buf, hunks, OPTS)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    assert.is_true(#marks > 0, "pending hunk should create extmarks")
  end)

  it("does NOT render extmarks for an accepted hunk", function()
    local buf = make_buf({ "hello" })
    local ns  = ui.ns()
    local hunks = {
      make_hunk({ id = 1, type = "add", status = "accepted", start_after = 1, end_after = 1, after_lines = { "hello" } }),
    }
    ui.render(buf, hunks, OPTS)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    assert.are.equal(0, #marks, "accepted hunk must not produce extmarks")
  end)

  it("does NOT render extmarks for a rejected hunk", function()
    local buf = make_buf({ "hello" })
    local ns  = ui.ns()
    local hunks = {
      make_hunk({ id = 1, type = "add", status = "rejected", start_after = 1, end_after = 1, after_lines = { "hello" } }),
    }
    ui.render(buf, hunks, OPTS)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    assert.are.equal(0, #marks, "rejected hunk must not produce extmarks")
  end)
end)

-- ──────────────────────────────────────────────
-- Bug B: col out of range in _render_char_diff
-- ──────────────────────────────────────────────

describe("ui._render_char_diff – col clamping", function()
  it("does not error when after_lines is longer than the actual buffer line", function()
    -- Buffer has a short line; hunk's after_lines claims a longer one.
    local buf = make_buf({ "ab" })  -- actual length = 2
    local ns  = ui.ns()
    local hunk = make_hunk({
      type         = "change",
      start_after  = 1,
      end_after    = 1,
      before_lines = { "xy" },
      after_lines  = { "abcdefghij" },  -- length = 10, much longer than buffer
    })
    -- Should not raise E5108
    local ok, err = pcall(ui._render_char_diff, buf, ns, hunk)
    assert.is_true(ok, "expected no error, got: " .. tostring(err))
  end)

  it("still highlights chars when buffer line matches after_lines length", function()
    local buf = make_buf({ "abcdef" })
    local ns  = ui.ns()
    local hunk = make_hunk({
      type         = "change",
      start_after  = 1,
      end_after    = 1,
      before_lines = { "aXcdef" },
      after_lines  = { "abcdef" },
    })
    ui._render_char_diff(buf, ns, hunk)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    assert.is_true(#marks > 0, "should have char-level extmarks")
  end)
end)
