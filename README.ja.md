# copilot-hunk.nvim

> Neovim で AI 支援編集のための VSCode スタイルのインライン diff レビュー。

`copilot-hunk` は AI ツール (Copilot CLI、aider、cline など) がファイルを編集したとき、
その差分を自動的に検出して**インライン**でフルライン色付きハイライト表示します —
VS Code の GitHub Copilot と同じ体験を Neovim で。
手動操作は不要: レビューセッションは自動で開始・終了します。

![デモ](https://raw.githubusercontent.com/hogehoge315/copilot-hunk/main/assets/demo.gif)

---

## 機能

- **AI 編集の自動検出** — 手動のスナップショット操作は不要。
  外部ツールがファイルを書き換えると `FileChangedShell` / `FocusGained` が発火し、
  レビューセッションが自動的に開始されます。
- **フォーマッタ誤検知防止** — `BufWritePre` タイムスタンプガードにより、
  Neovim の保存から 2 秒以内のファイル変更は無視します (stylua、prettier、LSP format など)。
- **2 段階カラーリングのインライン diff** — 変更行全体に薄い背景色、
  変更テキスト領域に濃いオーバーレイ (GitHub の diff 表示と同様)。
- **文字レベル diff** — change hunk 内では、実際に変更された文字が
  さらに濃い色 (`CopilotHunkChangeChar`) でハイライトされます。
- **Hunk カウンター** — 各 pending hunk の行末に `[1/3]` の仮想テキストを表示。
- **`n` / `N` ナビゲーション (ラップアラウンド)** — 検索と同じ感覚で hunk 間を移動。
- **クロスファイルナビゲーション** — 複数ファイルにアクティブセッションがある場合、
  `n` / `N` でバッファ境界を越えて全 pending hunk を巡回します。
- **3 レベルの Accept / Reject** — hunk 単位 (`ga` / `gr`)、ファイル単位 (`gA` / `gR`)、
  全ファイル (`gAA` / `gRR`)。
- **Git 非依存** — Git リポジトリがなくても動作します。

---

## インストール

### [lazy.nvim](https://github.com/folke/lazy.nvim) (推奨)

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

## 設定

```lua
require("copilot_hunk").setup({
  enable_auto_snapshot = true,   -- AI のファイル編集を自動検出
  signs   = false,               -- サイン列マーカー (デフォルト: false)
  keymaps = true,                -- デフォルトキーマップを設定
  highlights = {
    add    = {},   -- CopilotHunkAdd の背景色を上書き
    delete = {},   -- CopilotHunkDelete の背景色を上書き
    change = {},   -- CopilotHunkChange の背景色を上書き
  },
})
```

---

## キーマップ

以下のキーマップはバッファローカルで、**レビューセッション中のみ**有効です。
セッション終了時、`n` / `N` は Neovim のデフォルト動作に復帰します。

| キー | 動作 |
|------|------|
| `n` | 次の hunk へ移動 (クロスファイル・ラップアラウンド) |
| `N` | 前の hunk へ移動 (クロスファイル・ラップアラウンド) |
| `ga` | カーソル位置の hunk を accept → 自動で次の hunk へ |
| `gr` | カーソル位置の hunk を reject → 自動で次の hunk へ |
| `gA` | 現在のファイルの全 hunk を accept |
| `gR` | 現在のファイルの全 hunk を reject |
| `gAA` | 全ファイルの全 hunk を accept |
| `gRR` | 全ファイルの全 hunk を reject |

デフォルトキーマップを無効にして独自に設定する場合:

```lua
require("copilot_hunk").setup({ keymaps = false })

-- 手動でバインド:
vim.keymap.set("n", "<leader>ha", function()
  require("copilot_hunk.session").accept_at_cursor(vim.api.nvim_get_current_buf())
end)
```

---

## ユーザーコマンド

| コマンド | 説明 |
|----------|------|
| `:CopilotHunkAccept` | カーソル位置の hunk を accept |
| `:CopilotHunkReject` | カーソル位置の hunk を reject |
| `:CopilotHunkNext` | 次の hunk へ移動 |
| `:CopilotHunkPrev` | 前の hunk へ移動 |
| `:CopilotHunkAcceptAll` | 現在のバッファの全 hunk を accept |
| `:CopilotHunkRejectAll` | 現在のバッファの全 hunk を reject |
| `:CopilotHunkAcceptAllFiles` | 全アクティブセッションの全 hunk を accept |
| `:CopilotHunkRejectAllFiles` | 全アクティブセッションの全 hunk を reject |
| `:CopilotHunkEnd` | 現在のセッションを終了 |

---

## 仕組み

```
AI ツールがファイルを disk 上で書き換える
       ↓
FileChangedShell / FocusGained が発火
       ↓ (フォーマッタガード: Neovim の保存から 2 秒以内はスキップ)
スナップショット比較
       ↓ (差分検出)
セッション開始 — インラインハイライト表示
       ↓
ユーザーが n/N で移動、ga/gr で accept/reject
       ↓ (全 hunk 解決)
セッション自動終了
```

---

## プログラマティック API

AI ツールやスクリプトから直接連携する場合:

```lua
local ch = require("copilot_hunk")

-- 手動でセッションを開始 (自動検出が適用されない場合):
local base = ch.snapshot(bufnr)  -- AI 編集前にキャプチャ
-- ... AI がバッファに書き込み ...
ch.start_session(bufnr, base)

-- 手動で終了 (任意; 全 hunk 解決時は自動終了):
ch.end_session(bufnr)
```

---

## 要件

- Neovim ≥ 0.11

---

## ライセンス

MIT — [LICENSE](./LICENSE) を参照

---

詳細な仕様は [SPEC.md](./SPEC.md) を参照してください。
