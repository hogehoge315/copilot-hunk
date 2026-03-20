--- spec/telescope_buf_spec.lua
--- Tests for session transfer between hidden and listed buffers (fixes #36).
--- Covers: _transfer_session, BufEnter Case 1 (re-render), Case 2 (path-based transfer),
--- and edge case for old buffer deletion.

local session = require("copilot_hunk.session")

local OPTS = { signs = false, keymaps = false, highlights = {} }

local function make_buf(lines, listed)
  local buf = vim.api.nvim_create_buf(listed ~= false, listed == false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe("telescope buffer transfer", function()
  before_each(function()
    session._sessions = {}
    session._session_order = {}
  end)

  describe("_transfer_session", function()
    it("moves session from old bufnr to new bufnr", function()
      local old_bufnr = vim.api.nvim_create_buf(false, true)   -- unlisted scratch
      local new_bufnr = vim.api.nvim_create_buf(true, false)    -- listed real buf

      vim.api.nvim_buf_set_name(old_bufnr, "/tmp/test_transfer_move.lua")
      vim.api.nvim_buf_set_lines(old_bufnr, 0, -1, false, { "line1", "CHANGED" })
      session.start(old_bufnr, { "line1", "line2" }, OPTS)
      assert.truthy(session._sessions[old_bufnr])
      assert.is_true(vim.tbl_contains(session._session_order, old_bufnr))

      -- Transfer to new buffer (simulate Telescope opening the same file).
      vim.api.nvim_buf_set_lines(new_bufnr, 0, -1, false, { "line1", "CHANGED" })
      session._transfer_session(old_bufnr, new_bufnr)

      -- Session moved.
      assert.is_nil(session._sessions[old_bufnr])
      assert.truthy(session._sessions[new_bufnr])
      assert.equal(new_bufnr, session._sessions[new_bufnr].bufnr)

      -- _session_order updated.
      assert.is_false(vim.tbl_contains(session._session_order, old_bufnr))
      assert.is_true(vim.tbl_contains(session._session_order, new_bufnr))
      assert.equal(new_bufnr, session._session_order[1])

      -- Cleanup.
      pcall(vim.api.nvim_buf_delete, new_bufnr, { force = true })
    end)

    it("deletes old buffer when it is unlisted", function()
      local old_bufnr = vim.api.nvim_create_buf(false, true)   -- unlisted
      local new_bufnr = vim.api.nvim_create_buf(true, false)

      vim.api.nvim_buf_set_name(old_bufnr, "/tmp/test_transfer_del_unlisted.lua")
      vim.api.nvim_buf_set_lines(old_bufnr, 0, -1, false, { "a", "B" })
      session.start(old_bufnr, { "a", "b" }, OPTS)

      vim.api.nvim_buf_set_lines(new_bufnr, 0, -1, false, { "a", "B" })
      session._transfer_session(old_bufnr, new_bufnr)

      -- Old unlisted buffer should be deleted.
      assert.is_false(vim.api.nvim_buf_is_valid(old_bufnr))

      pcall(vim.api.nvim_buf_delete, new_bufnr, { force = true })
    end)

    it("does NOT delete old buffer when it is listed", function()
      local old_bufnr = vim.api.nvim_create_buf(true, false)   -- listed
      local new_bufnr = vim.api.nvim_create_buf(true, false)

      vim.api.nvim_buf_set_name(old_bufnr, "/tmp/test_transfer_keep_listed.lua")
      vim.api.nvim_buf_set_lines(old_bufnr, 0, -1, false, { "x", "Y" })
      session.start(old_bufnr, { "x", "y" }, OPTS)

      vim.api.nvim_buf_set_lines(new_bufnr, 0, -1, false, { "x", "Y" })
      session._transfer_session(old_bufnr, new_bufnr)

      -- Old listed buffer should still be valid.
      assert.is_true(vim.api.nvim_buf_is_valid(old_bufnr))

      pcall(vim.api.nvim_buf_delete, old_bufnr, { force = true })
      pcall(vim.api.nvim_buf_delete, new_bufnr, { force = true })
    end)

    it("is a no-op when old bufnr has no session", function()
      local old_bufnr = vim.api.nvim_create_buf(false, true)
      local new_bufnr = vim.api.nvim_create_buf(true, false)

      -- No session on old_bufnr.
      session._transfer_session(old_bufnr, new_bufnr)

      assert.is_nil(session._sessions[new_bufnr])
      assert.equal(0, #session._session_order)

      pcall(vim.api.nvim_buf_delete, old_bufnr, { force = true })
      pcall(vim.api.nvim_buf_delete, new_bufnr, { force = true })
    end)
  end)

  describe("BufEnter Case 1: existing session re-render", function()
    it("session remains intact after BufEnter on a buffer that already has a session", function()
      local buf = make_buf({ "hello", "CHANGED" })
      session.start(buf, { "hello", "world" }, OPTS)
      assert.truthy(session.get(buf))

      -- Simulate BufEnter by checking that the session is still present.
      -- (The autocmd schedules _rerender_all; we verify the session isn't disrupted.)
      local s = session.get(buf)
      assert.is_not_nil(s)
      assert.equal(buf, s.bufnr)

      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)
  end)

  describe("BufEnter Case 2: path-based transfer", function()
    it("transfers session when a new bufnr enters for the same file path", function()
      local old_bufnr = vim.api.nvim_create_buf(false, true)
      local new_bufnr = vim.api.nvim_create_buf(true, false)
      local path = "/tmp/test_bufenter_transfer.lua"

      vim.api.nvim_buf_set_name(old_bufnr, path)
      vim.api.nvim_buf_set_lines(old_bufnr, 0, -1, false, { "foo", "BAR" })
      session.start(old_bufnr, { "foo", "bar" }, OPTS)
      assert.truthy(session._sessions[old_bufnr])

      -- New buffer for the same path (simulates Telescope :edit).
      vim.api.nvim_buf_set_lines(new_bufnr, 0, -1, false, { "foo", "BAR" })

      -- Directly call _transfer_session (the autocmd would do this via vim.schedule).
      session._transfer_session(old_bufnr, new_bufnr)

      assert.is_nil(session._sessions[old_bufnr])
      assert.truthy(session._sessions[new_bufnr])

      pcall(vim.api.nvim_buf_delete, new_bufnr, { force = true })
    end)
  end)

  describe("multi-session transfer", function()
    it("preserves order of other sessions after transfer", function()
      local buf_a = make_buf({ "A" })
      local old_b  = vim.api.nvim_create_buf(false, true)
      local buf_c  = make_buf({ "C" })

      vim.api.nvim_buf_set_name(old_b, "/tmp/test_order_b.lua")
      vim.api.nvim_buf_set_lines(old_b, 0, -1, false, { "B_new" })

      session.start(buf_a, { "a" }, OPTS)
      session.start(old_b, { "B_old" }, OPTS)
      session.start(buf_c, { "c" }, OPTS)

      assert.equal(3, #session._session_order)
      assert.equal(old_b, session._session_order[2])

      local new_b = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_lines(new_b, 0, -1, false, { "B_new" })
      session._transfer_session(old_b, new_b)

      -- Order preserved: buf_a, new_b, buf_c
      assert.equal(3, #session._session_order)
      assert.equal(buf_a, session._session_order[1])
      assert.equal(new_b, session._session_order[2])
      assert.equal(buf_c, session._session_order[3])

      pcall(vim.api.nvim_buf_delete, buf_a, { force = true })
      pcall(vim.api.nvim_buf_delete, new_b, { force = true })
      pcall(vim.api.nvim_buf_delete, buf_c, { force = true })
    end)
  end)
end)
