--- spec/session_spec.lua
--- Tests for session.lua (start, stop, accept/reject, navigation, cross-file).

-- This spec MUST run inside Neovim headlessly (uses vim.api).
-- It is run via: nvim --headless -l spec/minit.lua

local session = require("copilot_hunk.session")

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function get_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local OPTS = { signs = false, keymaps = false, highlights = {} }

describe("session.start()", function()
  before_each(function()
    -- Clean up any stale sessions.
    session._sessions = {}
    session._session_order = {}
  end)

  it("returns false when base == current (no diff)", function()
    local buf = make_buf({ "hello", "world" })
    local ok = session.start(buf, { "hello", "world" }, OPTS)
    assert.is_false(ok)
  end)

  it("returns true and creates session when diff exists", function()
    local buf = make_buf({ "hello", "CHANGED" })
    local ok = session.start(buf, { "hello", "world" }, OPTS)
    assert.is_true(ok)
    assert.is_not_nil(session.get(buf))
  end)

  it("returns false and warns when session already active", function()
    local buf = make_buf({ "A" })
    session.start(buf, { "B" }, OPTS)
    local ok2 = session.start(buf, { "C" }, OPTS)
    assert.is_false(ok2)
  end)

  it("adds bufnr to _session_order", function()
    local buf = make_buf({ "new" })
    session.start(buf, { "old" }, OPTS)
    assert.is_true(vim.tbl_contains(session._session_order, buf))
  end)
end)

describe("session.stop()", function()
  before_each(function()
    session._sessions = {}
    session._session_order = {}
  end)

  it("removes session and from _session_order", function()
    local buf = make_buf({ "new" })
    session.start(buf, { "old" }, OPTS)
    session.stop(buf)
    assert.is_nil(session.get(buf))
    assert.is_false(vim.tbl_contains(session._session_order, buf))
  end)
end)

describe("session.accept_all() / reject_all()", function()
  before_each(function()
    session._sessions = {}
    session._session_order = {}
  end)

  it("accept_all marks all hunks accepted and stops session", function()
    local buf = make_buf({ "new1", "new2" })
    session.start(buf, { "old1", "old2" }, OPTS)
    session.accept_all(buf)
    assert.is_nil(session.get(buf))  -- session ended (all resolved)
  end)

  it("reject_all restores base lines and stops session", function()
    local buf = make_buf({ "new1", "new2" })
    session.start(buf, { "old1", "old2" }, OPTS)
    session.reject_all(buf)
    assert.is_nil(session.get(buf))
    assert.are.same({ "old1", "old2" }, get_lines(buf))
  end)
end)

describe("session.accept_all_global() / reject_all_global()", function()
  before_each(function()
    session._sessions = {}
    session._session_order = {}
  end)

  it("accept_all_global handles multiple sessions without skipping (regression for iterator mutation bug)", function()
    local bufs = {}
    for i = 1, 4 do
      local buf = make_buf({ "new" .. i })
      session.start(buf, { "old" .. i }, OPTS)
      table.insert(bufs, buf)
    end
    assert.are.equal(4, #session._session_order)

    session.accept_all_global()

    -- All sessions should be stopped.
    for _, buf in ipairs(bufs) do
      assert.is_nil(session.get(buf))
    end
    assert.are.equal(0, #session._session_order)
  end)

  it("reject_all_global restores all buffers", function()
    local buf1 = make_buf({ "new1" })
    local buf2 = make_buf({ "new2" })
    session.start(buf1, { "old1" }, OPTS)
    session.start(buf2, { "old2" }, OPTS)

    session.reject_all_global()

    assert.are.same({ "old1" }, get_lines(buf1))
    assert.are.same({ "old2" }, get_lines(buf2))
    assert.are.equal(0, #session._session_order)
  end)
end)

describe("_next_session_bufnr / _prev_session_bufnr", function()
  before_each(function()
    session._sessions = {}
    session._session_order = {}
  end)

  it("returns nil when only one session exists", function()
    local buf = make_buf({ "new" })
    session.start(buf, { "old" }, OPTS)
    assert.is_nil(session._next_session_bufnr(buf))
    assert.is_nil(session._prev_session_bufnr(buf))
  end)

  it("returns the other buf when two sessions exist", function()
    local buf1 = make_buf({ "new1" })
    local buf2 = make_buf({ "new2" })
    session.start(buf1, { "old1" }, OPTS)
    session.start(buf2, { "old2" }, OPTS)
    assert.are.equal(buf2, session._next_session_bufnr(buf1))
    assert.are.equal(buf1, session._prev_session_bufnr(buf2))
  end)

  it("skips sessions with no pending hunks", function()
    local buf1 = make_buf({ "new1" })
    local buf2 = make_buf({ "new2" })
    local buf3 = make_buf({ "new3" })
    session.start(buf1, { "old1" }, OPTS)
    session.start(buf2, { "old2" }, OPTS)
    session.start(buf3, { "old3" }, OPTS)

    -- Accept all hunks in buf2 (so it has no pending hunks left).
    session.accept_all(buf2)
    -- buf2 session ends when all hunks resolved. So _session_order only has buf1, buf3.

    -- next from buf1 should skip buf2 (stopped) and return buf3.
    assert.are.equal(buf3, session._next_session_bufnr(buf1))
  end)
end)
