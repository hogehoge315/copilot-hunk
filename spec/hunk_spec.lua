--- spec/hunk_spec.lua
--- Unit tests for hunk operations (accept, reject, navigation).
--- These tests do NOT require Neovim because they mock nvim_buf_set_lines.

-- Minimal vim API stub.
if not vim then
  local _lines = {}

  ---@diagnostic disable-next-line: lowercase-global
  vim = {
    api = {
      nvim_buf_set_lines = function(bufnr, s, e, strict, replacement)
        -- Simulate 0-indexed, end-exclusive replacement on _lines.
        local result = {}
        for i = 1, s do result[#result + 1] = _lines[i] end
        for _, l in ipairs(replacement) do result[#result + 1] = l end
        for i = e + 1, #_lines do result[#result + 1] = _lines[i] end
        _lines = result
      end,
    },
    _test_set_lines = function(lines) _lines = lines end,
    _test_get_lines = function() return _lines end,
  }
end

local hunk_mod = require("copilot_hunk.hunk")

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
    vim._test_set_lines({ "new" })
    local h = make_hunk(1, "change", 1, 1, 1, 1, { "old" }, { "new" })
    hunk_mod.reject(h, 0, { h })
    assert.are.equal("rejected", h.status)
  end)

  it("restores before_lines in the buffer", function()
    vim._test_set_lines({ "new" })
    local h = make_hunk(1, "change", 1, 1, 1, 1, { "original" }, { "new" })
    hunk_mod.reject(h, 0, { h })
    assert.are.equal("original", vim._test_get_lines()[1])
  end)

  it("shifts later pending hunks by the correct offset", function()
    -- base: 3 lines, ai_result: 4 lines (one extra added in hunk1)
    -- hunk1: add 1 line at position 2  (before=0, after=1 → delta = -1 on reject)
    -- hunk2: change at position 3 (after) → should shift to 2 after hunk1 reject
    vim._test_set_lines({ "a", "ADDED", "b", "CHANGED" })

    local h1 = make_hunk(1, "add",    0, 0,   2, 2, {},        { "ADDED" })
    local h2 = make_hunk(2, "change", 3, 3,   4, 4, { "b" },   { "CHANGED" })

    hunk_mod.reject(h1, 0, { h1, h2 })

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
