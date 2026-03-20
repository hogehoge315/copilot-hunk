# copilot-hunk.nvim

> VSCode-style inline diff review for AI-assisted editing in Neovim.

`copilot-hunk` automatically detects when an AI tool (Copilot CLI, aider, cline, etc.)
edits a file on disk and shows the diff **inline** with full-line colour highlights —
just like the GitHub Copilot experience in VS Code.
No manual setup needed: the review session starts and ends automatically.

![demo placeholder](https://raw.githubusercontent.com/hogehoge315/copilot-hunk/main/assets/demo.gif)

---

## Features

- **Auto-detection of AI edits** — no manual snapshot step.
  When an external tool writes a file, `FileChangedShell` / `FocusGained` fires and
  a review session starts automatically. Unloaded buffers are also detected via
  `git diff` / `git ls-files` on `FocusGained`.
- **Formatter false-positive prevention** — `BufWritePre` timestamp guard ignores
  file changes within 2 seconds of a Neovim save (stylua, prettier, LSP format, etc.).
- **Inline diff with 2-tier colouring** — muted background on the entire changed line,
  vivid overlay on the changed text region (like GitHub's diff view).
- **Character-level diff** — within change hunks, the exact modified characters are
  highlighted with an even stronger colour (`CopilotHunkChangeChar`).
- **Hunk counter** — each pending hunk shows `[1/4]` virtual text at end-of-line
  (global across all files).
- **`n` / `N` navigation with wrap-around** — jump between hunks just like search.
- **Cross-file navigation** — `n` / `N` crosses buffer boundaries when multiple files
  have active sessions, cycling through all pending hunks.
- **New file / deleted file support** — AI-created files show all content as "add" hunks
  (accept = save, reject = delete). AI-deleted files show all content as "delete" hunks
  (accept = delete, reject = restore).
- **Accept / reject at three levels** — hunk (`ga` / `gr`), file (`gA` / `gR`),
  or all files (`gAA` / `gRR`). After accept/reject, the hunk highlight disappears
  immediately and auto-jumps to the next pending hunk (even across files).
- **Robot icon 🤖 decoration** — buffers with pending hunks get a HINT diagnostic,
  automatically picked up by nvim-tree / neo-tree to show the 🤖 icon.
  Also provides `statusline_component()` for lualine integration.
- **Notification control** — `notify_level` option (default `WARN`) suppresses
  routine INFO notifications for a quieter experience.
- **Reviewed-state persistence** — after all hunks in a file are resolved, the file
  path + SHA-256 hash is saved to `.git/copilot-hunk-reviewed`. On next session start,
  matching files are skipped. Re-editing by AI auto-invalidates the hash.
- **Telescope / FZF / nvim-tree compatibility** — when you open a file via Telescope
  or FZF that has pending AI hunks, the session is auto-transferred to the new buffer.
- **Git-independent** — works on any buffer, no Git repo required.

---

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim) (recommended)

```lua
{
  "hogehoge315/copilot-hunk",
  version = "*",
  opts = {
    enable_auto_snapshot = true,  -- default: true
    signs = false,                -- default: false
  },
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "hogehoge315/copilot-hunk",
  config = function()
    require("copilot_hunk").setup()
  end,
}
```

---

## Configuration

```lua
require("copilot_hunk").setup({
  enable_auto_snapshot = true,     -- auto-detect AI file edits (default: true)
  signs   = false,                 -- sign column markers (default: false)
  keymaps = true,                  -- install default keymaps (default: true)
  cross_file_navigation = true,    -- n/N crosses file boundaries (default: true)
  notify_level = vim.log.levels.WARN,  -- notification verbosity (default: WARN)
  decorations = {
    winbar = false,                -- WinBar display (default: false)
    icon   = "🤖",                -- icon for WinBar/statusline
  },
  highlights = {
    add    = {},                   -- override CopilotHunkAdd bg
    delete = {},                   -- override CopilotHunkDelete bg
    change = {},                   -- override CopilotHunkChange bg
  },
})
```

---

## Keymaps

The following keymaps are buffer-local and active **only during a review session**.
When the session ends, `n` / `N` revert to Neovim's default behaviour.

| Key | Action |
|-----|--------|
| `n` | Go to next hunk (cross-file, wrap-around) |
| `N` | Go to previous hunk (cross-file, wrap-around) |
| `ga` | Accept hunk at cursor → auto-jump to next |
| `gr` | Reject hunk at cursor → auto-jump to next |
| `gA` | Accept all hunks in current file |
| `gR` | Reject all hunks in current file |
| `gAA` | Accept all hunks across all files |
| `gRR` | Reject all hunks across all files |

To disable the default keymaps and define your own:

```lua
require("copilot_hunk").setup({ keymaps = false })

-- Then bind manually, e.g.:
vim.keymap.set("n", "<leader>ha", function()
  require("copilot_hunk.session").accept_at_cursor(vim.api.nvim_get_current_buf())
end)
```

---

## User Commands

| Command | Description |
|---------|-------------|
| `:CopilotHunkAccept` | Accept hunk at cursor |
| `:CopilotHunkReject` | Reject hunk at cursor |
| `:CopilotHunkNext` | Go to next hunk |
| `:CopilotHunkPrev` | Go to previous hunk |
| `:CopilotHunkAcceptAll` | Accept all hunks in current buffer |
| `:CopilotHunkRejectAll` | Reject all hunks in current buffer |
| `:CopilotHunkAcceptAllFiles` | Accept all hunks across all active sessions |
| `:CopilotHunkRejectAllFiles` | Reject all hunks across all active sessions |
| `:CopilotHunkEnd` | End the current session |

---

## Integrations

### Statusline (lualine, etc.)

```lua
-- In your lualine config:
sections = {
  lualine_x = {
    { require("copilot_hunk.decoration").statusline_component },
  }
}
```

Shows `🤖 3` when the current buffer has 3 pending AI hunks.

### nvim-tree / neo-tree

The plugin places a HINT-level diagnostic on buffers with pending hunks.
nvim-tree and neo-tree automatically read `vim.diagnostic.get()` and show
the robot icon 🤖 on files with pending hunks — no extra configuration needed.

### Telescope / FZF

Works out of the box. When you open a file via Telescope or FZF that has
pending AI hunks, the hunks are automatically displayed.

---

## How It Works

```
AI tool writes file on disk
       ↓
FileChangedShell / FocusGained fires
       ↓ (formatter guard: skip if Neovim saved < 2s ago)
Snapshot comparison
       ↓ (diff detected)
Session starts — inline highlights appear
       ↓
User navigates with n/N, accepts/rejects with ga/gr
       ↓ (all hunks resolved)
Session ends automatically
```

---

## Programmatic API

For AI tools or scripts that want to integrate directly:

```lua
local ch = require("copilot_hunk")

-- Manually start a session (when auto-detection doesn't apply):
local base = ch.snapshot(bufnr)  -- capture before AI edits
-- ... AI writes to buffer ...
ch.start_session(bufnr, base)

-- End manually (optional; auto-ends when all hunks resolved):
ch.end_session(bufnr)
```

---

## Requirements

- Neovim ≥ 0.11

---

## License

MIT — see [LICENSE](./LICENSE)

---

For full specification, see [SPEC.md](./SPEC.md).
