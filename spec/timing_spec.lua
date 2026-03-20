--- spec/timing_spec.lua
--- Tests for auto-snapshot timing scenarios (Issues #20, #21).
--- Covers formatter guard, FileChangedShell/Post flow, BufEnter cleanup,
--- and multiple buffer handling.

local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[bufnr].buftype = ""
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function set_buf(bufnr, lines)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

describe("auto-snapshot timing", function()
  local init
  local session

  before_each(function()
    package.loaded["copilot_hunk"] = nil
    package.loaded["copilot_hunk.session"] = nil
    package.loaded["copilot_hunk.ui"] = nil
    package.loaded["copilot_hunk.diff"] = nil
    package.loaded["copilot_hunk.hunk"] = nil
    package.loaded["copilot_hunk.keymap"] = nil
    package.loaded["copilot_hunk.decoration"] = nil

    init = require("copilot_hunk")
    session = require("copilot_hunk.session")
    init.setup({ enable_auto_snapshot = true, keymaps = false, signs = false, highlights = {} })
  end)

  after_each(function()
    local order = vim.deepcopy(session._session_order)
    for _, bufnr in ipairs(order) do
      session.stop(bufnr, { silent = true })
    end
    session._sessions = {}
    session._session_order = {}
  end)

  -- ── formatter guard ──────────────────────────────────────────────

  describe("formatter guard", function()
    it("skips FileChangedShell within 2s of BufWritePre", function()
      local bufnr = make_buf({ "line1", "line2" })
      vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr, modeline = false })
      vim.api.nvim_exec_autocmds("FileChangedShell", { buffer = bufnr, modeline = false })
      assert.is_nil(init._snap_store[bufnr])
    end)

    it("allows FileChangedShell after 2s of BufWritePre (AI edit)", function()
      local bufnr = make_buf({ "line1", "line2" })
      -- Simulate write that happened 3 seconds ago.
      init._last_nvim_write[bufnr] = vim.uv.now() - 3000
      vim.api.nvim_exec_autocmds("FileChangedShell", { buffer = bufnr, modeline = false })
      assert.is_not_nil(init._snap_store[bufnr])
    end)

    it("allows FileChangedShell when no prior BufWritePre", function()
      local bufnr = make_buf({ "content" })
      vim.api.nvim_exec_autocmds("FileChangedShell", { buffer = bufnr, modeline = false })
      assert.is_not_nil(init._snap_store[bufnr])
    end)
  end)

  -- ── FileChangedShell → FileChangedShellPost flow ─────────────────

  describe("FileChangedShell -> FileChangedShellPost flow", function()
    it("starts session when content changes", function()
      local bufnr = make_buf({ "original line" })
      init._last_nvim_write[bufnr] = 0

      vim.api.nvim_exec_autocmds("FileChangedShell", { buffer = bufnr, modeline = false })
      set_buf(bufnr, { "modified by AI" })
      vim.api.nvim_exec_autocmds("FileChangedShellPost", { buffer = bufnr, modeline = false })

      vim.wait(200, function() return session.get(bufnr) ~= nil end)
      assert.is_not_nil(session.get(bufnr))
    end)

    it("does NOT start session when content is identical", function()
      local bufnr = make_buf({ "same content" })
      init._last_nvim_write[bufnr] = 0

      vim.api.nvim_exec_autocmds("FileChangedShell", { buffer = bufnr, modeline = false })
      -- Content unchanged
      vim.api.nvim_exec_autocmds("FileChangedShellPost", { buffer = bufnr, modeline = false })
      vim.wait(200, function() return false end)

      assert.is_nil(session.get(bufnr))
    end)

    it("does NOT double-start if session already active", function()
      local bufnr = make_buf({ "original" })
      session.start(bufnr, { "base content" }, { keymaps = false, signs = false, highlights = {} })
      local first_session = session.get(bufnr)
      assert.is_not_nil(first_session)

      vim.api.nvim_exec_autocmds("FileChangedShell", { buffer = bufnr, modeline = false })
      vim.api.nvim_exec_autocmds("FileChangedShellPost", { buffer = bufnr, modeline = false })
      vim.wait(200, function() return false end)

      assert.equal(first_session, session.get(bufnr))
    end)

    it("clears snap_store after FileChangedShellPost", function()
      local bufnr = make_buf({ "original" })
      init._last_nvim_write[bufnr] = 0

      vim.api.nvim_exec_autocmds("FileChangedShell", { buffer = bufnr, modeline = false })
      assert.is_not_nil(init._snap_store[bufnr])

      set_buf(bufnr, { "changed" })
      vim.api.nvim_exec_autocmds("FileChangedShellPost", { buffer = bufnr, modeline = false })
      -- snap_store is cleared immediately; session start is deferred
      assert.is_nil(init._snap_store[bufnr])
    end)
  end)

  -- ── FocusGained all-buffer handling ──────────────────────────────

  describe("FocusGained all-buffer handling", function()
    it("snapshots ALL loaded normal buffers on FocusGained", function()
      local buf1 = make_buf({ "file1" })
      local buf2 = make_buf({ "file2" })

      vim.api.nvim_exec_autocmds("FocusGained", { modeline = false })

      assert.is_not_nil(init._snap_store[buf1])
      assert.is_not_nil(init._snap_store[buf2])
    end)

    it("skips buffers with active sessions", function()
      local buf1 = make_buf({ "file1 new" })
      session.start(buf1, { "file1 base" }, { keymaps = false, signs = false, highlights = {} })
      local buf2 = make_buf({ "file2" })

      vim.api.nvim_exec_autocmds("FocusGained", { modeline = false })

      assert.is_nil(init._snap_store[buf1])
      assert.is_not_nil(init._snap_store[buf2])
    end)

    it("does not overwrite existing snap_store entry", function()
      local bufnr = make_buf({ "original snap" })
      init._snap_store[bufnr] = { "preserved" }

      vim.api.nvim_exec_autocmds("FocusGained", { modeline = false })

      assert.are.same({ "preserved" }, init._snap_store[bufnr])
    end)
  end)

  -- ── BufEnter cleanup ─────────────────────────────────────────────

  describe("BufEnter cleanup", function()
    it("takes snapshot on BufEnter for normal buffer", function()
      local bufnr = make_buf({ "content" })
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = bufnr, modeline = false })
      assert.is_not_nil(init._snap_store[bufnr])
    end)

    it("skips BufEnter for buffers with active session", function()
      local bufnr = make_buf({ "new content" })
      session.start(bufnr, { "base" }, { keymaps = false, signs = false, highlights = {} })

      init._snap_store[bufnr] = nil
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = bufnr, modeline = false })
      assert.is_nil(init._snap_store[bufnr])
    end)

    it("skips BufEnter if snap_store already set", function()
      local bufnr = make_buf({ "content" })
      init._snap_store[bufnr] = { "existing snapshot" }
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = bufnr, modeline = false })
      assert.are.same({ "existing snapshot" }, init._snap_store[bufnr])
    end)

    pending("clears snap_store after 2s if no file change detected (slow test)")
  end)

  -- ── multiple buffer handling ─────────────────────────────────────

  describe("multiple buffer handling", function()
    it("handles two buffers changing simultaneously", function()
      local buf1 = make_buf({ "file1 original" })
      local buf2 = make_buf({ "file2 original" })

      init._last_nvim_write[buf1] = 0
      init._last_nvim_write[buf2] = 0

      vim.api.nvim_exec_autocmds("FileChangedShell", { buffer = buf1, modeline = false })
      vim.api.nvim_exec_autocmds("FileChangedShell", { buffer = buf2, modeline = false })

      set_buf(buf1, { "file1 modified" })
      set_buf(buf2, { "file2 modified" })

      vim.api.nvim_exec_autocmds("FileChangedShellPost", { buffer = buf1, modeline = false })
      vim.api.nvim_exec_autocmds("FileChangedShellPost", { buffer = buf2, modeline = false })

      vim.wait(500, function()
        return session.get(buf1) ~= nil and session.get(buf2) ~= nil
      end)

      assert.is_not_nil(session.get(buf1))
      assert.is_not_nil(session.get(buf2))
    end)

    it("FocusGained + FileChangedShellPost starts sessions for multiple buffers", function()
      local buf1 = make_buf({ "file1 original" })
      local buf2 = make_buf({ "file2 original" })

      vim.api.nvim_exec_autocmds("FocusGained", { modeline = false })

      set_buf(buf1, { "file1 AI edit" })
      set_buf(buf2, { "file2 AI edit" })

      vim.api.nvim_exec_autocmds("FileChangedShellPost", { buffer = buf1, modeline = false })
      vim.api.nvim_exec_autocmds("FileChangedShellPost", { buffer = buf2, modeline = false })

      vim.wait(500, function()
        return session.get(buf1) ~= nil and session.get(buf2) ~= nil
      end)

      assert.is_not_nil(session.get(buf1))
      assert.is_not_nil(session.get(buf2))
    end)
  end)
end)
