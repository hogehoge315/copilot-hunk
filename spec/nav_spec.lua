--- spec/nav_spec.lua
--- Tests for wrap-around navigation in hunk.lua

local hunk_mod = require("copilot_hunk.hunk")

local function make_hunk(id, start_after, status)
  return {
    id = id,
    type = "change",
    start_before = start_after,
    end_before = start_after,
    start_after = start_after,
    end_after = start_after,
    before_lines = { "old" },
    after_lines = { "new" },
    status = status or "pending",
  }
end

describe("hunk_mod.next_hunk_wrap()", function()
  it("returns the next hunk without wrap when available", function()
    local hunks = { make_hunk(1, 2), make_hunk(2, 5), make_hunk(3, 8) }
    local h, wrapped = hunk_mod.next_hunk_wrap(3, hunks)
    assert.are.equal(2, h.id)
    assert.is_false(wrapped)
  end)

  it("wraps to the first hunk when at end", function()
    local hunks = { make_hunk(1, 2), make_hunk(2, 5), make_hunk(3, 8) }
    local h, wrapped = hunk_mod.next_hunk_wrap(10, hunks)
    assert.are.equal(1, h.id)
    assert.is_true(wrapped)
  end)

  it("returns nil when no pending hunks", function()
    local hunks = { make_hunk(1, 2, "accepted") }
    local h, wrapped = hunk_mod.next_hunk_wrap(1, hunks)
    assert.is_nil(h)
    assert.is_false(wrapped)
  end)
end)

describe("hunk_mod.prev_hunk_wrap()", function()
  it("returns the previous hunk without wrap when available", function()
    local hunks = { make_hunk(1, 2), make_hunk(2, 5), make_hunk(3, 8) }
    local h, wrapped = hunk_mod.prev_hunk_wrap(6, hunks)
    assert.are.equal(2, h.id)
    assert.is_false(wrapped)
  end)

  it("wraps to the last hunk when at start", function()
    local hunks = { make_hunk(1, 2), make_hunk(2, 5), make_hunk(3, 8) }
    local h, wrapped = hunk_mod.prev_hunk_wrap(1, hunks)
    assert.are.equal(3, h.id)
    assert.is_true(wrapped)
  end)
end)
