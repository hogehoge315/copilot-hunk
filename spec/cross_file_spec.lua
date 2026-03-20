--- spec/cross_file_spec.lua
--- Tests for cross-file navigation and unloaded buffer global counter (Issue #24).

local function make_buf(lines, fname)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[bufnr].buftype = ""
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  if fname then
    vim.api.nvim_buf_set_name(bufnr, fname)
  end
  return bufnr
end

describe("cross-file navigation", function()
  local init, session

  before_each(function()
    -- Clear module cache
    for _, mod in ipairs({
      "copilot_hunk", "copilot_hunk.session", "copilot_hunk.ui",
      "copilot_hunk.diff", "copilot_hunk.hunk", "copilot_hunk.keymap", "copilot_hunk.decoration"
    }) do
      package.loaded[mod] = nil
    end
    init = require("copilot_hunk")
    session = require("copilot_hunk.session")
    init.setup({ enable_auto_snapshot = false, keymaps = false, signs = false, highlights = {},
                 cross_file_navigation = true })
  end)

  after_each(function()
    local order = vim.deepcopy(session._session_order)
    for _, b in ipairs(order) do
      session.stop(b, { silent = true })
    end
    session._sessions = {}
    session._session_order = {}
  end)

  -- ── global counter with two sessions ────────────────────────────────────

  describe("global counter", function()
    it("shows [1/2] for first hunk when two sessions exist", function()
      local buf1 = make_buf({ "a", "b" }, "/tmp/ch_test_file1.txt")
      local buf2 = make_buf({ "x", "y" }, "/tmp/ch_test_file2.txt")
      local base1 = { "a_old", "b" }
      local base2 = { "x_old", "y" }

      session.start(buf1, base1, init._opts)
      session.start(buf2, base2, init._opts)

      -- Check that _session_order has both
      assert.equal(2, #session._session_order)

      local s1 = session.get(buf1)
      local s2 = session.get(buf2)
      assert.is_not_nil(s1)
      assert.is_not_nil(s2)
      assert.equal(1, #s1.hunks)
      assert.equal(1, #s2.hunks)
    end)

    it("counter total decreases when a hunk is rejected (rejected excluded)", function()
      local buf1 = make_buf({ "a", "b" }, "/tmp/ch_test_file1b.txt")
      local buf2 = make_buf({ "x", "y" }, "/tmp/ch_test_file2b.txt")

      session.start(buf1, { "a_old", "b" }, init._opts)
      session.start(buf2, { "x_old", "y" }, init._opts)

      -- Reject buf1's hunk
      session.reject_all(buf1)

      -- buf2 session should still exist with 1 hunk
      local s2 = session.get(buf2)
      assert.is_not_nil(s2)
      assert.equal(1, #s2.hunks)
      assert.equal("pending", s2.hunks[1].status)
    end)
  end)

  -- ── cross_file_navigation = false ───────────────────────────────────────

  describe("cross_file_navigation = false", function()
    it("goto_next wraps within current file only", function()
      local opts_no_cross = vim.tbl_deep_extend("force", init._opts, { cross_file_navigation = false })

      local buf1 = make_buf({ "a", "b" }, "/tmp/ch_test_nocross1.txt")
      local buf2 = make_buf({ "x", "y" }, "/tmp/ch_test_nocross2.txt")

      session.start(buf1, { "a_old", "b" }, opts_no_cross)
      session.start(buf2, { "x_old", "y" }, opts_no_cross)

      assert.equal(2, #session._session_order)

      -- With cross=false, session.opts.cross_file_navigation is stored
      local s1 = session.get(buf1)
      assert.is_not_nil(s1)
      assert.equal(false, s1.opts.cross_file_navigation)
    end)

    it("goto_next with cross=true moves to second buffer", function()
      local buf1 = make_buf({ "a", "b" }, "/tmp/ch_test_cross1.txt")
      local buf2 = make_buf({ "x", "y" }, "/tmp/ch_test_cross2.txt")

      session.start(buf1, { "a_old", "b" }, init._opts)
      session.start(buf2, { "x_old", "y" }, init._opts)

      -- _next_session_bufnr from buf1 should return buf2
      local next_buf = session._next_session_bufnr(buf1)
      assert.equal(buf2, next_buf)
    end)

    it("_prev_session_bufnr wraps to last session from first", function()
      local buf1 = make_buf({ "a", "b" }, "/tmp/ch_test_prev1.txt")
      local buf2 = make_buf({ "x", "y" }, "/tmp/ch_test_prev2.txt")

      session.start(buf1, { "a_old", "b" }, init._opts)
      session.start(buf2, { "x_old", "y" }, init._opts)

      local prev_buf = session._prev_session_bufnr(buf1)
      assert.equal(buf2, prev_buf)  -- wraps to buf2 (last)
    end)
  end)

  -- ── session order management ─────────────────────────────────────────────

  describe("session_order", function()
    it("session is removed from _session_order when stopped", function()
      local buf1 = make_buf({ "a", "b" }, "/tmp/ch_test_order1.txt")
      local buf2 = make_buf({ "x", "y" }, "/tmp/ch_test_order2.txt")

      session.start(buf1, { "a_old", "b" }, init._opts)
      session.start(buf2, { "x_old", "y" }, init._opts)
      assert.equal(2, #session._session_order)

      session.stop(buf1)
      assert.equal(1, #session._session_order)
      assert.equal(buf2, session._session_order[1])
    end)

    it("accept_all_global resolves hunks in all sessions", function()
      local buf1 = make_buf({ "a_new", "b" }, "/tmp/ch_test_glob1.txt")
      local buf2 = make_buf({ "x_new", "y" }, "/tmp/ch_test_glob2.txt")

      session.start(buf1, { "a_old", "b" }, init._opts)
      session.start(buf2, { "x_old", "y" }, init._opts)
      assert.equal(2, #session._session_order)

      session.accept_all_global()

      -- Both sessions ended
      assert.equal(0, #session._session_order)
    end)
  end)
end)
