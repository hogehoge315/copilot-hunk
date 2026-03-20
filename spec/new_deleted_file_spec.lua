--- spec/new_deleted_file_spec.lua
--- Tests for new file creation and deleted file AI scenarios (Issues #26, #27).

local tmpdir = vim.fn.tempname():gsub("[^/]+$", "")  -- /tmp/

local function tmpfile(name, lines)
  local path = tmpdir .. "copilot_hunk_test_" .. name .. "_" .. tostring(math.random(100000))
  if lines then
    vim.fn.writefile(lines, path)
  end
  return path
end

local function buf_from_file(path)
  local bufnr = vim.fn.bufadd(path)
  vim.bo[bufnr].buflisted = true
  vim.fn.bufload(bufnr)
  return bufnr
end

describe("new and deleted file AI scenarios", function()
  local init, session, diff_mod

  before_each(function()
    for _, mod in ipairs({
      "copilot_hunk", "copilot_hunk.session", "copilot_hunk.ui",
      "copilot_hunk.diff", "copilot_hunk.hunk", "copilot_hunk.keymap",
      "copilot_hunk.decoration"
    }) do
      package.loaded[mod] = nil
    end
    init = require("copilot_hunk")
    session = require("copilot_hunk.session")
    diff_mod = require("copilot_hunk.diff")
    init.setup({ enable_auto_snapshot = false, keymaps = false, signs = false, highlights = {} })
  end)

  after_each(function()
    local order = vim.deepcopy(session._session_order)
    for _, b in ipairs(order) do
      session.stop(b, { silent = true })
    end
    session._sessions = {}
    session._session_order = {}
  end)

  -- ── diff.lua: edge cases ─────────────────────────────────────────────────

  describe("diff edge cases", function()
    it("base=empty produces all-add hunks (new file scenario)", function()
      local hunks = diff_mod.diff({}, { "line1", "line2", "line3" })
      assert.equal(1, #hunks)
      assert.equal("add", hunks[1].type)
      assert.equal(3, #hunks[1].after_lines)
      assert.equal("line1", hunks[1].after_lines[1])
    end)

    it("current=empty produces all-delete hunks (deleted file scenario)", function()
      local hunks = diff_mod.diff({ "line1", "line2", "line3" }, {})
      assert.equal(1, #hunks)
      assert.equal("delete", hunks[1].type)
      assert.equal(3, #hunks[1].before_lines)
    end)

    it("single line change produces one change hunk", function()
      local hunks = diff_mod.diff({ "old" }, { "new" })
      assert.equal(1, #hunks)
      assert.equal("change", hunks[1].type)
    end)

    it("non-adjacent changes produce separate hunks", function()
      local base    = { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" }
      local current = { "A", "b", "c", "d", "e", "f", "g", "h", "i", "J" }
      local hunks = diff_mod.diff(base, current)
      assert.equal(2, #hunks)
    end)
  end)

  -- ── new file: session mechanics ──────────────────────────────────────────

  describe("new file session", function()
    it("starts session with empty base, shows all-add hunks", function()
      local path = tmpfile("new", { "new_line1", "new_line2" })
      local bufnr = buf_from_file(path)

      local ok = session.start(bufnr, {}, vim.tbl_extend("force", init._opts, {
        _session_kind = "new_file",
        _session_file_path = path,
      }))

      assert.is_true(ok)
      local s = session.get(bufnr)
      assert.is_not_nil(s)
      assert.equal(1, #s.hunks)
      assert.equal("add", s.hunks[1].type)
      assert.equal(2, #s.hunks[1].after_lines)

      vim.fn.delete(path)
    end)

    it("accept_all: file should stay on disk (already there)", function()
      local path = tmpfile("newaccept", { "content" })
      local bufnr = buf_from_file(path)

      session.start(bufnr, {}, vim.tbl_extend("force", init._opts, {
        _session_kind = "new_file",
        _session_file_path = path,
      }))
      session.accept_all(bufnr)

      -- Session should be ended
      assert.is_nil(session.get(bufnr))
      -- File still exists (we just saved it)
      assert.equal(1, vim.fn.filereadable(path))

      vim.fn.delete(path)
    end)

    it("reject_all: file should be deleted from disk", function()
      local path = tmpfile("newreject", { "line1", "line2" })
      local bufnr = buf_from_file(path)
      -- Confirm file exists before reject
      assert.equal(1, vim.fn.filereadable(path))

      session.start(bufnr, {}, vim.tbl_extend("force", init._opts, {
        _session_kind = "new_file",
        _session_file_path = path,
      }))
      session.reject_all(bufnr)

      -- Session should be ended
      assert.is_nil(session.get(bufnr))
      -- File should be deleted
      assert.equal(0, vim.fn.filereadable(path))
    end)
  end)

  -- ── deleted file: session mechanics ─────────────────────────────────────

  describe("deleted file session", function()
    it("starts session with base content, shows all-delete hunks", function()
      local path = tmpfile("del", nil)  -- don't create the file
      local base = { "original_line1", "original_line2" }

      -- Create empty buffer (simulates deleted file)
      local bufnr = vim.fn.bufadd(path)
      vim.bo[bufnr].buflisted = true
      vim.fn.bufload(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local ok = session.start(bufnr, base, vim.tbl_extend("force", init._opts, {
        _session_kind = "deleted_file",
        _session_file_path = path,
      }))

      assert.is_true(ok)
      local s = session.get(bufnr)
      assert.is_not_nil(s)
      assert.equal(1, #s.hunks)
      assert.equal("delete", s.hunks[1].type)
      assert.equal(2, #s.hunks[1].before_lines)
    end)

    it("accept_all (keep deleted): session ends, file stays gone", function()
      local path = tmpfile("delaccept", nil)
      local base = { "original" }

      local bufnr = vim.fn.bufadd(path)
      vim.bo[bufnr].buflisted = true
      vim.fn.bufload(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      session.start(bufnr, base, vim.tbl_extend("force", init._opts, {
        _session_kind = "deleted_file",
        _session_file_path = path,
      }))
      session.accept_all(bufnr)

      assert.is_nil(session.get(bufnr))
      -- File should NOT exist
      assert.equal(0, vim.fn.filereadable(path))
    end)

    it("reject_all (restore): file is written back to disk", function()
      local path = tmpfile("delreject", nil)
      local base = { "restored_line1", "restored_line2" }

      local bufnr = vim.fn.bufadd(path)
      vim.bo[bufnr].buflisted = true
      vim.fn.bufload(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      session.start(bufnr, base, vim.tbl_extend("force", init._opts, {
        _session_kind = "deleted_file",
        _session_file_path = path,
      }))
      session.reject_all(bufnr)

      -- Session ends
      assert.is_nil(session.get(bufnr))
      -- File should exist with restored content
      assert.equal(1, vim.fn.filereadable(path))
      local restored = vim.fn.readfile(path)
      assert.same(base, restored)

      vim.fn.delete(path)
    end)
  end)

  -- ── mixed sessions: modified + new + deleted ─────────────────────────────

  describe("mixed session types global counter", function()
    it("counts hunks from all session kinds in global total", function()
      -- modified file: 1 hunk
      local buf_mod = vim.api.nvim_create_buf(true, false)
      vim.bo[buf_mod].buftype = ""
      vim.api.nvim_buf_set_lines(buf_mod, 0, -1, false, { "new_content" })
      session.start(buf_mod, { "old_content" }, init._opts)

      -- new file: 1 hunk
      local path_new = tmpfile("mixed_new", { "created" })
      local buf_new = buf_from_file(path_new)
      session.start(buf_new, {}, vim.tbl_extend("force", init._opts, {
        _session_kind = "new_file",
        _session_file_path = path_new,
      }))

      -- deleted file: 1 hunk
      local path_del = tmpfile("mixed_del", nil)
      local buf_del = vim.fn.bufadd(path_del)
      vim.bo[buf_del].buflisted = true
      vim.fn.bufload(buf_del)
      vim.api.nvim_buf_set_lines(buf_del, 0, -1, false, {})
      session.start(buf_del, { "deleted_line" }, vim.tbl_extend("force", init._opts, {
        _session_kind = "deleted_file",
        _session_file_path = path_del,
      }))

      -- All 3 sessions should be in _session_order
      assert.equal(3, #session._session_order)

      -- Cleanup
      vim.fn.delete(path_new)
    end)
  end)

  -- ── partial accept/reject (multiple hunks in new file) ────────────────────

  describe("new file with multiple content blocks", function()
    it("session opts stores kind and path", function()
      local path = tmpfile("opts_check", { "a", "b" })
      local bufnr = buf_from_file(path)

      session.start(bufnr, {}, vim.tbl_extend("force", init._opts, {
        _session_kind = "new_file",
        _session_file_path = path,
      }))

      local s = session.get(bufnr)
      assert.equal("new_file", s.opts._session_kind)
      assert.equal(path, s.opts._session_file_path)

      vim.fn.delete(path)
    end)
  end)
end)
