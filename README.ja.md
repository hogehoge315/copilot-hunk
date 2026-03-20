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
  レビューセッションが自動的に開始されます。未ロードバッファも `FocusGained` 時に
  `git diff` / `git ls-files` で検出されます。
- **フォーマッタ誤検知防止** — `BufWritePre` タイムスタンプガードにより、
  Neovim の保存から 2 秒以内のファイル変更は無視します (stylua、prettier、LSP format など)。
- **2 段階カラーリングのインライン diff** — 変更行全体に薄い背景色、
  変更テキスト領域に濃いオーバーレイ (GitHub の diff 表示と同様)。
- **文字レベル diff** — change hunk 内では、実際に変更された文字が
  さらに濃い色 (`CopilotHunkChangeChar`) でハイライトされます。
- **Hunk カウンター** — 各 pending hunk の行末に `[1/4]` の仮想テキストを表示
  (全ファイルにわたるグローバルカウンター)。
- **`n` / `N` ナビゲーション (ラップアラウンド)** — 検索と同じ感覚で hunk 間を移動。
- **クロスファイルナビゲーション** — 複数ファイルにアクティブセッションがある場合、
  `n` / `N` でバッファ境界を越えて全 pending hunk を巡回します。
- **新規ファイル / 削除ファイル対応** — AI が新規作成したファイルは全内容が「追加」hunk として表示
  (accept = 保存、reject = 削除)。AI が削除したファイルは全内容が「削除」hunk として表示
  (accept = 削除、reject = 復元)。
- **3 レベルの Accept / Reject** — hunk 単位 (`ga` / `gr`)、ファイル単位 (`gA` / `gR`)、
  全ファイル (`gAA` / `gRR`)。accept/reject 後、hunk ハイライトは即座に消え、
  次の pending hunk へ自動ジャンプします (ファイルをまたいでも対応)。
- **ロボットアイコン 🤖 デコレーション** — pending hunk のあるバッファに HINT 診断を設定し、
  nvim-tree / neo-tree が自動で 🤖 アイコンを表示。
  lualine 連携用の `statusline_component()` も提供します。
- **通知レベル制御** — `notify_level` オプション (デフォルト `WARN`) で
  日常的な INFO 通知を抑制し、静かな操作感を実現します。
- **レビュー済み永続化** — ファイルの全 hunk が解決されると、ファイルパスと SHA-256 ハッシュが
  `.git/copilot-hunk-reviewed` に保存されます。次回セッション開始時に一致すればスキップ。
  AI が再編集するとハッシュが変わり自動的に再検出されます。
- **Telescope / FZF / nvim-tree 互換** — Telescope や FZF で開いたファイルに
  pending hunk がある場合、セッションが新しいバッファへ自動転送されます。
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
  enable_auto_snapshot = true,     -- AI のファイル編集を自動検出 (デフォルト: true)
  signs   = false,                 -- サイン列マーカー (デフォルト: false)
  keymaps = true,                  -- デフォルトキーマップを設定 (デフォルト: true)
  cross_file_navigation = true,    -- n/N でファイル間移動 (デフォルト: true)
  notify_level = vim.log.levels.WARN,  -- 通知レベル (デフォルト: WARN)
  decorations = {
    winbar = false,                -- WinBar 表示 (デフォルト: false)
    icon   = "🤖",                -- WinBar / statusline のアイコン
  },
  highlights = {
    add    = {},                   -- CopilotHunkAdd の背景色を上書き
    delete = {},                   -- CopilotHunkDelete の背景色を上書き
    change = {},                   -- CopilotHunkChange の背景色を上書き
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

## 連携

### ステータスライン (lualine など)

```lua
-- lualine の設定に追加:
sections = {
  lualine_x = {
    { require("copilot_hunk.decoration").statusline_component },
  }
}
```

現在のバッファに 3 つの pending AI hunk がある場合、`🤖 3` と表示されます。

### nvim-tree / neo-tree

プラグインは pending hunk のあるバッファに HINT レベルの diagnostic を設定します。
nvim-tree と neo-tree は `vim.diagnostic.get()` を自動的に読み取り、
pending hunk のあるファイルにロボットアイコン 🤖 を表示します — 追加設定は不要です。

### Telescope / FZF

そのまま動作します。Telescope や FZF で pending AI hunk のあるファイルを開くと、
hunk が自動的に表示されます。

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
