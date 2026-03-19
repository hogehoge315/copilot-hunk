--- spec/hunk_spec.lua
--- Unit tests for hunk operations (accept, reject, navigation).
--- Works both inside Neovim (headless) and outside (standalone busted)
--- by providing a minimal vim API stub when vim is not available.

-- Minimal vim API stub for running outside Neovim.
if not vim then
  local _buffers = { [0] = {} }
  local _next_buf = 1

  ---@diagnostic disable-next-line: lowercase-global
  vim = {
    api = {
      nvim_create_buf = function(_listed, _scratch)
        local id = _next_buf
        _next_buf = _next_buf + 1
        _buffers[id] = {}
        return id
      end,
      nvim_buf_set_lines = function(bufnr, s, e, _strict, replacement)
        local lines = _buffers[bufnr] or {}
        local actual_e = e < 0 and #lines or e
        local result = {}
        for i = 1, s do result[#result + 1] = lines[i] end
        for _, l in ipairs(replacement) do result[#result + 1] = l end
        for i = actual_e + 1, #lines do result[#result + 1] = lines[i] end
        _buffers[bufnr] = result
      end,
      nvim_buf_get_lines = function(bufnr, s, e, _strict)
        local lines = _buffers[bufnr] or {}
        local actual_e = e < 0 and #lines or e
        local result = {}
        for i = s + 1, actual_e do result[#result + 1] = lines[i] end
        return result
      end,
    },
  }
end

local hunk_mod = require("copilot_hunk.hunk")

--- Create a scratch buffer populated with the given lines.
local function create_test_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

--- Read all lines from a test buffer.
local function get_buf_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

--- Helper: create a minimal hunk.
local function make_hunk(id, type, start_a, end_a, start_b, end_b, before, after)
  return {
    id = id,
    type = type,
    start_before = start_a,
    end_before   = end_a,
    start_after  = start_b,
    end_after    = end_b,
    before_lines = before,
    after_lines  = after,
    status       = "pending",
  }
end

describe("hunk_mod.accept()", function()
  it("sets status to 'accepted'", function()
    local h = make_hunk(1, "change", 1, 1, 1, 1, { "old" }, { "new" })
    hunk_mod.accept(h)
    assert.are.equal("accepted", h.status)
  end)
end)

describe("hunk_mod.reject()", function()
  it("sets status to 'rejected'", function()
    local bufnr = create_test_buf({ "new" })
    local h = make_hunk(1, "change", 1, 1, 1, 1, { "old" }, { "new" })
    hunk_mod.reject(h, bufnr, { h })
    assert.are.equal("rejected", h.status)
  end)

  it("restores before_lines in the buffer for a change hunk", function()
    local bufnr = create_test_buf({ "new" })
    local h = make_hunk(1, "change", 1, 1, 1, 1, { "original" }, { "new" })
    hunk_mod.reject(h, bufnr, { h })
    assert.are.equal("original", get_buf_lines(bufnr)[1])
  end)

  it("re-inserts before_lines for a delete hunk", function()
    -- After deletion, buffer has lines { "a", "c" }; line "b" was deleted
    -- after line 1. start_after=1 means deleted after line 1 of the after-text.
    local bufnr = create_test_buf({ "a", "c" })
    local h = make_hunk(1, "delete", 2, 2, 1, 0, { "b" }, {})
    hunk_mod.reject(h, bufnr, { h })
    local lines = get_buf_lines(bufnr)
    assert.are.same({ "a", "b", "c" }, lines)
  end)

  it("shifts later pending hunks by the correct offset", function()
    -- base: 3 lines, ai_result: 4 lines (one extra added in hunk1)
    -- hunk1: add 1 line at position 2  (before=0, after=1 → delta = -1 on reject)
    -- hunk2: change at position 3 (after) → should shift to 2 after hunk1 reject
    local bufnr = create_test_buf({ "a", "ADDED", "b", "CHANGED" })

    local h1 = make_hunk(1, "add",    0, 0,   2, 2, {},        { "ADDED" })
    local h2 = make_hunk(2, "change", 3, 3,   4, 4, { "b" },   { "CHANGED" })

    hunk_mod.reject(h1, bufnr, { h1, h2 })

    -- After rejecting h1 (which added 1 line), h2 should shift back by 1.
    assert.are.equal(3, h2.start_after)
    assert.are.equal(3, h2.end_after)
  end)
end)

describe("hunk_mod.hunk_at_line()", function()
  it("finds a hunk whose range covers the given line", function()
    local hunks = {
      make_hunk(1, "change", 5, 5, 5, 6, { "x" }, { "y", "z" }),
    }
    local found = hunk_mod.hunk_at_line(5, hunks)
    assert.are.equal(1, found.id)

    local found2 = hunk_mod.hunk_at_line(6, hunks)
    assert.are.equal(1, found2.id)
  end)

  it("returns nil when no hunk covers the line", function()
    local hunks = {
      make_hunk(1, "change", 5, 5, 5, 5, { "x" }, { "y" }),
    }
    assert.is_nil(hunk_mod.hunk_at_line(3, hunks))
  end)

  it("ignores non-pending hunks", function()
    local h = make_hunk(1, "change", 5, 5, 5, 5, { "x" }, { "y" })
    h.status = "accepted"
    assert.is_nil(hunk_mod.hunk_at_line(5, { h }))
  end)
end)

describe("hunk_mod.next_hunk() / prev_hunk()", function()
  local hunks

  before_each(function()
    hunks = {
      make_hunk(1, "change", 2, 2, 2, 2, { "a" }, { "A" }),
      make_hunk(2, "change", 5, 5, 5, 5, { "b" }, { "B" }),
      make_hunk(3, "change", 8, 8, 8, 8, { "c" }, { "C" }),
    }
  end)

  it("next_hunk returns the first hunk after the line", function()
    local h = hunk_mod.next_hunk(3, hunks)
    assert.are.equal(2, h.id)
  end)

  it("next_hunk returns nil when past all hunks", function()
    assert.is_nil(hunk_mod.next_hunk(10, hunks))
  end)

  it("prev_hunk returns the last hunk before the line", function()
    local h = hunk_mod.prev_hunk(7, hunks)
    assert.are.equal(2, h.id)
  end)

  it("prev_hunk returns nil when before all hunks", function()
    assert.is_nil(hunk_mod.prev_hunk(1, hunks))
  end)
end)

describe("hunk_mod.next_hunk_wrap() / prev_hunk_wrap()", function()
  it("next_hunk_wrap wraps to first when past all", function()
    local hunks = {
      make_hunk(1, "change", 2, 2, 2, 2, { "a" }, { "A" }),
      make_hunk(2, "change", 5, 5, 5, 5, { "b" }, { "B" }),
    }
    local h, wrapped = hunk_mod.next_hunk_wrap(10, hunks)
    assert.are.equal(1, h.id)
    assert.is_true(wrapped)
  end)

  it("prev_hunk_wrap wraps to last when before all", function()
    local hunks = {
      make_hunk(1, "change", 2, 2, 2, 2, { "a" }, { "A" }),
      make_hunk(2, "change", 5, 5, 5, 5, { "b" }, { "B" }),
    }
    local h, wrapped = hunk_mod.prev_hunk_wrap(1, hunks)
    assert.are.equal(2, h.id)
    assert.is_true(wrapped)
  end)
end)
