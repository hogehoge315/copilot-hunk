# copilot-hunk.nvim

> VSCode-style inline diff review for AI-assisted editing in Neovim.

`copilot-hunk` lets you review AI-generated code changes **hunk by hunk** directly in your buffer — with full-line colour highlights exactly like the GitHub Copilot experience in VSCode.

![demo placeholder](https://raw.githubusercontent.com/hogehoge315/copilot-hunk/main/assets/demo.gif)

---

## Features

- **Inline diff highlighting** — entire lines are coloured (not just gutter signs)
  - 🟢 Added lines: green background
  - 🔴 Deleted lines: red virtual lines shown inline
  - 🟡 Changed lines: yellow background + red virtual lines for the original
- **Hunk-level Accept / Reject** — accept the AI change or roll back to the pre-AI state
- **Session model** — mirrors VS Code Copilot's UX (apply first, reject to roll back)
- **Git-independent** — works on unsaved buffers, no Git repo required
- **Neovim ≥ 0.11** — uses `vim.diff()`, `virt_lines`, and `line_hl_group` extmarks

---

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim) (recommended)

```lua
{
  "hogehoge315/copilot-hunk",
  version = "*",
  opts = {},  -- see Configuration below
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
  highlights = {
    add    = { bg = "#1e3a2f" },  -- override added-line background
    delete = { bg = "#3a1e1e" },  -- override deleted-line background
    change = { bg = "#2e2a12" },  -- override changed-line background
  },
  signs   = true,   -- show ▎ marker in the sign column
  keymaps = true,   -- install default keymaps (see below)
})
```

---

## Keymaps

The following keymaps are buffer-local and active **only during a review session**.

| Key | Action |
|-----|--------|
| `ga` | Accept hunk at cursor |
| `gr` | Reject hunk at cursor |
| `gn` | Jump to next hunk |
| `gp` | Jump to previous hunk |
| `gA` | Accept all hunks |
| `gR` | Reject all hunks |

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
| `:CopilotHunkAcceptAll` | Accept all hunks |
| `:CopilotHunkRejectAll` | Reject all hunks |
| `:CopilotHunkEnd` | End the current session |

---

## Programmatic API

Designed to be called by external AI tools (e.g. Copilot CLI, custom scripts):

```lua
local ch = require("copilot_hunk")

-- 1. Capture the buffer state BEFORE the AI edits it.
local base = ch.snapshot(bufnr)

-- 2. (AI tool writes new content to the buffer here.)

-- 3. Start the review session.
ch.start_session(bufnr, base)

-- 4. User reviews hunks with ga/gr/gn/gp…
--    Session ends automatically when all hunks are resolved.

-- 5. Or end the session manually at any time:
ch.end_session(bufnr)
```

---

## How It Works

Based on [ADR-0002](./adr.md):

```
base snapshot ←─ saved before AI edit
      │
      ↓ vim.diff()
ai_result (= current buffer) ←─ AI writes here
      │
      ↓ review
Accept → keep ai_result lines  (no-op)
Reject → restore base lines    (buffer replace)
```

---

## Requirements

- Neovim ≥ 0.11

---

## License

MIT — see [LICENSE](./LICENSE)
