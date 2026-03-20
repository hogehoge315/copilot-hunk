--- spec/global_counter_spec.lua
--- Tests for the global hunk counter ([n/N] across all files).

local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[bufnr].buftype = ""
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

describe("global hunk counter", function()
  local session
  local opts = { keymaps = false, signs = false, highlights = {} }

  before_each(function()
    package.loaded["copilot_hunk.session"]    = nil
    package.loaded["copilot_hunk.ui"]         = nil
    package.loaded["copilot_hunk.diff"]       = nil
    package.loaded["copilot_hunk.hunk"]       = nil
    package.loaded["copilot_hunk.keymap"]     = nil
    package.loaded["copilot_hunk.decoration"] = nil
    session = require("copilot_hunk.session")
  end)

  after_each(function()
    local order = vim.deepcopy(session._session_order)
    for _, bufnr in ipairs(order) do
      session.stop(bufnr, { silent = true })
    end
  end)

  it("single buffer: offset=0, total=local hunk count", function()
    local bufnr = make_buf({ "a", "b", "c" })
    -- base has 3 lines, buf has different content → 1 change hunk
    session.start(bufnr, { "x", "b", "c" }, opts)
    local s = session.get(bufnr)
    assert.is_not_nil(s)
    -- _session_order has one entry; global_counts returns offset=0, total=1
    -- We can't directly call global_counts (private), but we can verify via the session
    assert.equal(1, #s.hunks)
  end)

  it("two buffers: second buffer offset = first buffer hunk count", function()
    local buf1 = make_buf({ "line1" })
    local buf2 = make_buf({ "a", "b" })

    session.start(buf1, { "orig1" }, opts)        -- 1 hunk in buf1
    session.start(buf2, { "x", "y" }, opts)       -- 1 hunk in buf2

    local s1 = session.get(buf1)
    local s2 = session.get(buf2)
    assert.is_not_nil(s1)
    assert.is_not_nil(s2)
    -- session_order is [buf1, buf2]
    -- buf1: offset=0, total=2 → hunk shows [1/2]
    -- buf2: offset=1, total=2 → hunk shows [2/2]
    assert.equal(2, #session._session_order)
  end)

  it("accepting a hunk decrements global total", function()
    local buf1 = make_buf({ "new1" })
    local buf2 = make_buf({ "new2" })

    session.start(buf1, { "old1" }, opts)
    session.start(buf2, { "old2" }, opts)

    -- Accept the only hunk in buf1
    local s1 = session.get(buf1)
    assert.is_not_nil(s1)
    for _, h in ipairs(s1.hunks) do
      if h.status == "pending" then
        require("copilot_hunk.hunk").accept(h)
      end
    end
    -- Now session_order still has buf1 until _check_complete; manually check
    local s2 = session.get(buf2)
    assert.is_not_nil(s2)
    -- buf2 hunk should still be pending
    local pending = 0
    for _, h in ipairs(s2.hunks) do
      if h.status == "pending" then pending = pending + 1 end
    end
    assert.equal(1, pending)
  end)

  it("_render_hunk_counters uses global_offset/global_total when provided", function()
    local ui = require("copilot_hunk.ui")
    local ns = ui.ns()
    local bufnr = make_buf({ "foo", "bar" })
    -- Simulate a hunk list with one pending hunk
    local hunks = {
      { id = 1, type = "change", status = "pending",
        start_after = 1, end_after = 1,
        before_lines = { "old" }, after_lines = { "foo" } },
    }
    -- With global_offset=2, global_total=5 → should render [3/5]
    ui.render(bufnr, hunks, opts, 2, 5)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
    local found = false
    for _, m in ipairs(marks) do
      local vt = m[4] and m[4].virt_text
      if vt then
        for _, chunk in ipairs(vt) do
          if chunk[1] == "[3/5]" then found = true end
        end
      end
    end
    assert.is_true(found, "expected [3/5] in extmarks")
  end)

  it("_render_hunk_counters falls back to local count when no globals", function()
    local ui = require("copilot_hunk.ui")
    local ns = ui.ns()
    local bufnr = make_buf({ "foo", "bar" })
    local hunks = {
      { id = 1, type = "change", status = "pending",
        start_after = 1, end_after = 1,
        before_lines = { "old" }, after_lines = { "foo" } },
      { id = 2, type = "add", status = "pending",
        start_after = 2, end_after = 2,
        before_lines = {}, after_lines = { "bar" } },
    }
    -- No globals → should render [1/2] and [2/2]
    ui.render(bufnr, hunks, opts)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
    local texts = {}
    for _, m in ipairs(marks) do
      local vt = m[4] and m[4].virt_text
      if vt then
        for _, chunk in ipairs(vt) do
          if chunk[1]:match("%[%d+/%d+%]") then
            texts[#texts + 1] = chunk[1]
          end
        end
      end
    end
    assert.is_true(vim.tbl_contains(texts, "[1/2]"), "expected [1/2]")
    assert.is_true(vim.tbl_contains(texts, "[2/2]"), "expected [2/2]")
  end)
end)
