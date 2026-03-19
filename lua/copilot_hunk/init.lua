--- init.lua
--- Public API for copilot-hunk.
---
--- Typical usage (called by an external AI tool such as Copilot CLI):
---
---   -- Before the AI edits the buffer:
---   local base = require("copilot_hunk").snapshot(bufnr)
---
---   -- After the AI has written new content to the buffer:
---   require("copilot_hunk").start_session(bufnr, base)
---
---   -- Optionally end manually (auto-ends when all hunks are reviewed):
---   require("copilot_hunk").end_session(bufnr)

local M = {}

--- Default configuration.
M._opts = {
  highlights = {
    add    = {},
    delete = {},
    change = {},
  },
  signs   = false,
  keymaps = true,
  enable_auto_snapshot = false,
}

--- Configure the plugin.  Call once in your init.lua / lazy spec.
---
--- @param user_opts? table
---   highlights.add    table  nvim_set_hl attrs for added lines
---   highlights.delete table  nvim_set_hl attrs for deleted lines
---   highlights.change table  nvim_set_hl attrs for changed lines
---   signs             boolean  show sign-column markers (default true)
---   keymaps           boolean  install default keymaps (default true)
function M.setup(user_opts)
  M._opts = vim.tbl_deep_extend("force", M._opts, user_opts or {})

  local ui = require("copilot_hunk.ui")
  ui.define_highlights(M._opts.highlights)

  -- Re-apply highlights after every colorscheme change.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("CopilotHunkHL", { clear = true }),
    callback = function()
      ui.define_highlights(M._opts.highlights)
    end,
  })

  if M._opts.enable_auto_snapshot then
    M._setup_auto_snapshot()
  end
end

--- Capture the current content of `bufnr` as a snapshot string array.
--- Call this *before* triggering the AI edit.
---
--- @param bufnr? number  defaults to current buffer (0)
--- @return string[]
function M.snapshot(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

--- Start a review session.
--- `base_lines` is the snapshot taken before the AI edit.
--- The buffer must already contain the AI-edited content when this is called.
---
--- @param bufnr? number   defaults to current buffer
--- @param base_lines string[]
--- @return boolean  true if session started successfully
function M.start_session(bufnr, base_lines)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local session = require("copilot_hunk.session")
  return session.start(bufnr, base_lines, M._opts)
end

--- End the active review session for `bufnr`, discarding any pending hunks.
---
--- @param bufnr? number  defaults to current buffer
function M.end_session(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local session = require("copilot_hunk.session")
  session.stop(bufnr)
end

--- Arm the plugin for a single AI edit on `bufnr`.
--- Captures a snapshot NOW, then watches for the file to change on disk
--- (FileChangedShell / BufReadPost) and auto-starts a session.
--- The armed state expires after 120 seconds to avoid stale triggers.
---
--- Usage: call this BEFORE telling the AI to edit the file.
---
--- @param bufnr? number  defaults to current buffer
function M.arm(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local base = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local fname = vim.api.nvim_buf_get_name(bufnr)

  -- Discard any previous armed state for this buffer.
  M._disarm(bufnr)

  local aug_name = "CopilotHunkArmed_" .. bufnr
  local aug = vim.api.nvim_create_augroup(aug_name, { clear = true })

  local function fire()
    M._disarm(bufnr)
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      if M.has_session(bufnr) then return end
      local current = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      if not vim.deep_equal(base, current) then
        require("copilot_hunk.session").start(bufnr, base, M._opts)
      else
        vim.notify("[copilot-hunk] 変更が検出されませんでした。", vim.log.levels.INFO)
      end
    end, 80)
  end

  -- Watch for external file change (AI rewrote the file on disk).
  vim.api.nvim_create_autocmd({ "FileChangedShellPost", "BufReadPost" }, {
    group = aug,
    buffer = bufnr,
    once = true,
    callback = fire,
  })

  -- Expire after 120s to avoid stale triggers from later saves/formatters.
  local timer = vim.uv.new_timer()
  timer:start(120000, 0, vim.schedule_wrap(function()
    M._disarm(bufnr)
    vim.notify("[copilot-hunk] armed状態がタイムアウトしました。", vim.log.levels.WARN)
  end))

  -- Store armed state.
  M._armed = M._armed or {}
  M._armed[bufnr] = { base = base, aug = aug_name, timer = timer, fname = fname }

  vim.notify(
    string.format("[copilot-hunk] Armed: %s — AIが編集したら自動でセッション開始します", vim.fn.fnamemodify(fname, ":t")),
    vim.log.levels.INFO
  )
end

--- @private
function M._disarm(bufnr)
  if not M._armed or not M._armed[bufnr] then return end
  local state = M._armed[bufnr]
  pcall(vim.api.nvim_del_augroup_by_name, state.aug)
  if state.timer and not state.timer:is_closing() then
    state.timer:stop()
    state.timer:close()
  end
  M._armed[bufnr] = nil
end

--- Manually start a session using the armed snapshot (for when the AI
--- edited the buffer content directly rather than the file on disk).
--- @param bufnr? number
function M.trigger_armed_session(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not M._armed or not M._armed[bufnr] then
    vim.notify("[copilot-hunk] このバッファはarmed状態ではありません。先に <leader>ab を押してください。", vim.log.levels.WARN)
    return
  end
  local base = M._armed[bufnr].base
  M._disarm(bufnr)
  require("copilot_hunk.session").start(bufnr, base, M._opts)
end

--- Return true if there is an active session for `bufnr`.
--- @param bufnr? number
--- @return boolean
function M.has_session(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local session = require("copilot_hunk.session")
  return session.get(bufnr) ~= nil
end

--- @private
--- Set up autocmds that automatically capture a base snapshot when an external
--- tool edits the file on disk, covering both autoread and non-autoread setups.
function M._setup_auto_snapshot()
  local snap_store = {} -- bufnr → string[] (pre-change lines)

  local aug = vim.api.nvim_create_augroup("CopilotHunkAutoSnap", { clear = true })

  -- Save snapshot of current buffer on focus (covers autoread case)
  vim.api.nvim_create_autocmd("FocusGained", {
    group = aug,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if M.has_session(bufnr) then return end
      if vim.bo[bufnr].buftype ~= "" then return end
      if not vim.api.nvim_buf_is_loaded(bufnr) then return end
      snap_store[bufnr] = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end,
  })

  -- Also save on FileChangedShell (non-autoread setups)
  vim.api.nvim_create_autocmd("FileChangedShell", {
    group = aug,
    callback = function(args)
      local bufnr = args.buf
      if M.has_session(bufnr) then return end
      if not snap_store[bufnr] then
        snap_store[bufnr] = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      end
    end,
  })

  -- After reload: compare and start session if content changed
  vim.api.nvim_create_autocmd({ "FileChangedShellPost", "BufReadPost" }, {
    group = aug,
    callback = function(args)
      local bufnr = args.buf
      local base = snap_store[bufnr]
      if not base then return end
      snap_store[bufnr] = nil

      vim.defer_fn(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        if M.has_session(bufnr) then return end
        local current = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        if not vim.deep_equal(base, current) then
          require("copilot_hunk.session").start(bufnr, base, M._opts)
        end
      end, 50)
    end,
  })
end

return M
