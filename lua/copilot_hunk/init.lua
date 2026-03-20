--- init.lua
--- Public API for copilot-hunk.
---
--- This plugin automatically detects when an AI tool (Copilot, aider, cline, etc.)
--- edits a file on disk and starts a review session automatically.
---
--- Setup (in your Neovim config):
---   require('copilot_hunk').setup({ enable_auto_snapshot = true })
---
--- The session starts automatically when the file changes on disk.
--- Use n/N to navigate hunks, ga/gr to accept/reject.
--- The session ends automatically when all hunks are resolved.
---
--- Manual fallback (if auto-detection doesn't trigger):
---   require("copilot_hunk").start_session(bufnr, base_lines)

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
  enable_auto_snapshot = true,
  cross_file_navigation = true,
  decorations = {
    winbar = false,   -- opt-in WinBar (may conflict with other winbar plugins)
    icon   = "🤖",   -- icon shown in WinBar / statusline
  },
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

  -- Initialize decoration subsystem (diagnostic API, WinBar, etc.)
  local decoration = require("copilot_hunk.decoration")
  decoration.setup()

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
---
--- Formatter guard: formatters rewrite the file immediately after Neovim saves,
--- so FileChangedShell fires within seconds of BufWritePre.  We track the last
--- Neovim-initiated write timestamp per buffer and skip any FileChangedShell
--- that arrives within 5 seconds — those are formatter rewrites, not AI edits.
function M._setup_auto_snapshot()
  local snap_store = {}      -- bufnr → string[] (pre-change snapshot)
  local last_nvim_write = {} -- bufnr → timestamp ms (from BufWritePre)

  -- Expose for testing (read-only use from specs).
  M._snap_store       = snap_store
  M._last_nvim_write  = last_nvim_write

  local aug = vim.api.nvim_create_augroup("CopilotHunkAutoSnap", { clear = true })

  -- Track every time Neovim itself writes a buffer to disk.
  -- Any FileChangedShell that fires within 5s of this is a formatter, not an AI.
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = aug,
    callback = function(args)
      last_nvim_write[args.buf] = vim.uv.now()
    end,
  })

  -- Save snapshot on FocusGained (covers the "user was away while AI edited" case).
  -- When user returns, autoread reloads the file, then BufReadPost fires.
  vim.api.nvim_create_autocmd("FocusGained", {
    group = aug,
    callback = function()
      -- Snapshot ALL loaded normal buffers so multi-file AI edits are detected.
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr)
           and vim.bo[bufnr].buftype == ""
           and not M.has_session(bufnr)
           and not snap_store[bufnr] then
          snap_store[bufnr] = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        end
      end
      -- Detect AI-edited unloaded files via git (for cross-file global counter)
      if M._opts.cross_file_navigation then
        M._detect_ai_edited_via_git(snap_store, last_nvim_write)
      end
      -- Run checktime to trigger FileChangedShell for changed files.
      vim.cmd("checktime")
    end,
  })

  -- BufEnter: take snapshot + run checktime for the entered buffer.
  -- This handles AI edits to inactive buffers while Neovim remains focused.
  -- FileChangedShell for a non-current buffer fires only when that buffer is entered.
  vim.api.nvim_create_autocmd("BufEnter", {
    group = aug,
    callback = function(args)
      local bufnr = args.buf
      if M.has_session(bufnr) then return end
      if vim.bo[bufnr].buftype ~= "" then return end
      if not vim.api.nvim_buf_is_loaded(bufnr) then return end
      if snap_store[bufnr] then return end  -- snapshot already in progress

      snap_store[bufnr] = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Defer checktime so BufEnter fully completes first.
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.cmd("checktime " .. bufnr)
        end
      end)

      -- Clean up stale snapshot if FileChangedShell did not fire within 2s.
      vim.defer_fn(function()
        if snap_store[bufnr] and not M.has_session(bufnr) then
          snap_store[bufnr] = nil
        end
      end, 2000)
    end,
  })

  -- FileChangedShell: file changed on disk while Neovim has focus.
  -- Save snapshot IF it's not a formatter (i.e., not a recent Neovim write).
  vim.api.nvim_create_autocmd("FileChangedShell", {
    group = aug,
    callback = function(args)
      local bufnr = args.buf
      if M.has_session(bufnr) then return end
      -- Skip if this change follows a recent Neovim save (formatter guard).
      local last_write = last_nvim_write[bufnr]
      if last_write and (vim.uv.now() - last_write) < 2000 then return end
      -- Save the current (pre-reload) buffer content as base.
      if not snap_store[bufnr] then
        snap_store[bufnr] = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      end
    end,
  })

  -- After the file has been reloaded, compare and start session if changed.
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

--- @private
--- Detect AI-edited files not yet loaded as buffers by checking git diff.
--- For each unloaded modified file, loads it as a hidden buffer and starts a session.
--- Only runs when git is available. Skips non-git projects silently.
--- @param _snap_store table   per-bufnr snapshot store (unused here but kept for API consistency)
--- @param last_nvim_write table  per-bufnr timestamp of last BufWritePre
function M._detect_ai_edited_via_git(_snap_store, last_nvim_write)
  if vim.fn.executable("git") == 0 then return end
  local cwd = vim.fn.getcwd()
  local files = vim.fn.systemlist(
    "git -C " .. vim.fn.shellescape(cwd) .. " diff --name-only HEAD 2>/dev/null"
  )
  if not files or #files == 0 then return end

  local now = vim.uv.now()
  for _, relpath in ipairs(files) do
    local fullpath = cwd .. "/" .. relpath
    if vim.fn.filereadable(fullpath) == 0 then goto continue end

    local bufnr = vim.fn.bufnr(fullpath)
    local already_loaded = bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr)
    if already_loaded then goto continue end

    -- Formatter guard: skip if recently written by Neovim
    if bufnr ~= -1 and last_nvim_write[bufnr] then
      if (now - last_nvim_write[bufnr]) < 2000 then goto continue end
    end

    if bufnr ~= -1 and M.has_session(bufnr) then goto continue end

    local base_lines = vim.fn.systemlist(
      "git -C " .. vim.fn.shellescape(cwd)
      .. " show HEAD:" .. vim.fn.shellescape(relpath) .. " 2>/dev/null"
    )
    if not base_lines or #base_lines == 0 then goto continue end

    -- Load buffer (reads AI-edited content from disk)
    bufnr = vim.fn.bufadd(fullpath)
    vim.bo[bufnr].buflisted = false
    vim.fn.bufload(bufnr)

    local current = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if not vim.deep_equal(base_lines, current) and not M.has_session(bufnr) then
      require("copilot_hunk.session").start(bufnr, base_lines, M._opts)
    end

    ::continue::
  end
end

--- Statusline / tabline component.
--- Returns "🤖 N" when the current buffer has N pending AI hunks, else "".
--- Usage (lualine): { require('copilot_hunk').statusline }
function M.statusline()
  return require("copilot_hunk.decoration").statusline_component()
end

return M
