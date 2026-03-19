--- spec/diff_spec.lua
--- Unit tests for the diff module.
--- Run with: busted spec/

-- Minimal vim stub so tests can run outside Neovim via luarocks/busted.
if not vim then
  ---@diagnostic disable-next-line: lowercase-global
  vim = {
    diff = function(a, b, opts)
      -- Simple stub: delegate to a native diff if available, otherwise skip.
      -- In a real CI run this test suite is executed *inside* Neovim with
      -- `nvim --headless -l spec/minit.lua`.
      error("vim.diff not available outside Neovim")
    end,
  }
end

local diff = require("copilot_hunk.diff")

describe("diff.diff()", function()
  it("returns empty list when inputs are identical", function()
    local lines = { "hello", "world" }
    local hunks = diff.diff(lines, lines)
    assert.are.equal(0, #hunks)
  end)

  it("detects a pure addition", function()
    local base = { "line1", "line3" }
    local ai   = { "line1", "line2", "line3" }
    local hunks = diff.diff(base, ai)
    assert.are.equal(1, #hunks)
    assert.are.equal("add", hunks[1].type)
    assert.are.equal("line2", hunks[1].after_lines[1])
  end)

  it("detects a pure deletion", function()
    local base = { "line1", "line2", "line3" }
    local ai   = { "line1", "line3" }
    local hunks = diff.diff(base, ai)
    assert.are.equal(1, #hunks)
    assert.are.equal("delete", hunks[1].type)
    assert.are.equal("line2", hunks[1].before_lines[1])
  end)

  it("detects a change", function()
    local base = { "foo" }
    local ai   = { "bar" }
    local hunks = diff.diff(base, ai)
    assert.are.equal(1, #hunks)
    assert.are.equal("change", hunks[1].type)
    assert.are.equal("foo", hunks[1].before_lines[1])
    assert.are.equal("bar", hunks[1].after_lines[1])
  end)

  it("assigns sequential ids", function()
    local base = { "a", "b", "c", "d" }
    local ai   = { "A", "b", "C", "d" }
    local hunks = diff.diff(base, ai)
    assert.are.equal(2, #hunks)
    assert.are.equal(1, hunks[1].id)
    assert.are.equal(2, hunks[2].id)
  end)

  it("all hunks start with status 'pending'", function()
    local base = { "x" }
    local ai   = { "y" }
    local hunks = diff.diff(base, ai)
    assert.are.equal("pending", hunks[1].status)
  end)
end)
