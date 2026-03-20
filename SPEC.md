# copilot-hunk 仕様書 (SPEC)

> **Note**: `adr.md` は初期設計時のドキュメントです。実装との乖離が大きいため、
> このファイル (SPEC.md) が唯一の正式仕様書です。

## コアコンセプト

VS Code の GitHub Copilot が持つ "inline diff review" 体験を Neovim で再現する。

- AI (Copilot CLI / aider / cline など) がファイルを編集した直後、**自動的に**差分を検出してインラインで表示する
- ユーザーは hunk 単位で Accept / Reject を選べる
- **手動でセッションを開始・終了する必要はない** — セッションライフサイクルはすべて自動

## セッションライフサイクル

```
[AI がファイルを disk 上で書き換える]
        ↓
[Neovim が FileChangedShell / FocusGained を検出]
        ↓  (フォーマッタ誤検知ガード: BufWritePre から 2秒以内は無視)
[自動スナップショット比較]
        ↓
[差分ありなら session.start() — hunk 描画開始]
        ↓
[ユーザーが n/N で移動、ga/gr で accept/reject]
        ↓
[全 hunk 解決で session.stop() — 自動終了]
```

## 自動スナップショット方式

### フォーマッタ誤検知ガード

フォーマッタ (stylua / prettier / rustfmt / LSP format) は Neovim の保存直後にファイルを書き換える。
これを AI 編集と誤認しないために、`BufWritePre` のタイムスタンプを記録し、
その後 2 秒以内に来た `FileChangedShell` は無視する。

```
BufWritePre  ──→  last_nvim_write[buf] = now()

FileChangedShell  ──→  if now() - last_nvim_write[buf] < 2000ms → skip (formatter)
                         else → snap_store[buf] = current lines
```

### 4つの検出パス

| シナリオ | Neovim autoread | イベント系列 |
|---|---|---|
| Neovim 起動中に AI が編集 | 任意 | `FileChangedShell` → `FileChangedShellPost` |
| ユーザー不在中に AI が編集 | true | `FocusGained` → (autoread reload) → `BufReadPost` |
| Neovim フォーカス中・非アクティブバッファ変更 | 任意 | `BufEnter` → checktime → `FileChangedShell` → `FileChangedShellPost` |
| 未ロードバッファ・新規/削除ファイル | 任意 | `FocusGained` → `_detect_ai_edited_via_git()` |

- **FocusGained**: 全ロード済み通常バッファのスナップショットを取得後、`checktime` を実行
- **BufEnter**: スナップショット + `checktime` + 2 秒クリーンアップタイマー（未変更スナップの破棄）

### `_detect_ai_edited_via_git()`

`FocusGained` 時に以下の git コマンドを実行し、Neovim で未ロードのファイルを検出する:

- `git diff --name-only HEAD` → 変更済みファイル
- `git ls-files --others --exclude-standard` → 新規ファイル
- `git ls-files --deleted` → 削除ファイル

検出されたファイルは非表示バッファとして読み込まれセッションが開始される。

### BufEnter ハンドラの 3 ケース

| ケース | 条件 | 処理 |
|---|---|---|
| Case 1 | セッション既存 (`_sessions[bufnr]` あり) | `_rerender_all()` で extmark 再描画 |
| Case 2 | 同ファイル・異なる bufnr (Telescope/FZF 経由) | `_transfer_session()` でセッション転送 |
| Case 3 | セッションなし | 通常のスナップショット + checktime |

## キーマップ (セッション中のみ有効)

| キー | 動作 | 説明 |
|---|---|---|
| `n` | `goto_next()` | 次のhunkへ (クロスファイル・ラップアラウンド) |
| `N` | `goto_prev()` | 前のhunkへ (クロスファイル・ラップアラウンド) |
| `ga` | `accept_at_cursor()` | カーソル位置のhunkをaccept → 自動で次hunkへ |
| `gr` | `reject_at_cursor()` | カーソル位置のhunkをreject → 自動で次hunkへ |
| `gA` | `accept_all()` | 現在バッファの全hunkをaccept |
| `gR` | `reject_all()` | 現在バッファの全hunkをreject |
| `gAA` | `accept_all_global()` | 全バッファの全hunkをaccept |
| `gRR` | `reject_all_global()` | 全バッファの全hunkをreject |

- セッション終了時にキーマップは元に戻る (`n`/`N` は Neovim デフォルトに復帰)
- セッション外では `n`/`N` は上書きしない

## クロスファイルナビゲーション

複数ファイルを AI が編集した場合、`n`/`N` でファイルをまたいで移動できる。

- `_session_order[]` でセッション開始順を管理
- 現在ファイルの最後のhunkから `n` → 次のファイルの最初のhunkへ
- pending hunk がないセッションはスキップ
- すべてのファイルを周回して元のファイルに戻るループ
- `cross_file_navigation = false` で無効化可能（現在バッファ内のみでラップ）

### 未ロードバッファの自動検出

`cross_file_navigation = true`（デフォルト）の場合、`FocusGained` 時に
`git diff --name-only HEAD` を実行し、まだ Neovim で開いていない変更ファイルを検出する。

- 検出されたファイルは非表示バッファ (`buflisted = false`) として読み込まれ、セッションが開始される
- これにより、1ファイルしか開いていなくても `[1/2]` のようにグローバルカウンターが正しく表示される
- `n`/`N` で未ロードバッファへ移動すると、自動的に `buflisted = true` に設定される
- git が利用できないプロジェクトでは静かにスキップされる

## 新規ファイル / 削除ファイル対応

AI が新規作成・削除したファイルにも対応する。

### 新規ファイル (`_session_kind = "new_file"`)

- AI が新規作成したファイルを `git ls-files --others --exclude-standard` で検出
- 全行が「追加」hunk として表示される (`diff({}, lines)`)
- **accept**: `:write!` でファイルを保存
- **reject**: ファイルを削除 (`vim.fn.delete()`)

### 削除ファイル (`_session_kind = "deleted_file"`)

- AI が削除したファイルを `git ls-files --deleted` で検出
- 全行が「削除」hunk として表示される (`diff(lines, {})`)
- **accept**: バッファを削除 (ファイルは削除されたまま)
- **reject**: `writefile()` でファイルを復元

## ビジュアル仕様

### 2段階カラーリング

GitHub の diff 表示と同様に、変更行と変更テキストで色の濃度を分ける。

| ハイライトグループ | 用途 | 例 (ダークテーマ) |
|---|---|---|
| `CopilotHunkAdd` | 追加行 背景 (薄) | `#1a2e1a` |
| `CopilotHunkAddText` | 追加行 テキスト域 (濃) | `#2d5230` |
| `CopilotHunkDelete` | 削除 virtual lines 背景 | `#2e1a1a` |
| `CopilotHunkChange` | 変更行 背景 (薄) | `#2a2410` |
| `CopilotHunkChangeText` | 変更行 テキスト域 (濃) | `#4a3c18` |
| `CopilotHunkChangeChar` | 変更文字 (最濃) | `#6b5420` |
| `CopilotHunkCount` | hunk カウンター | `fg=#888888, italic` |

### Hunk カウンター

各 pending hunk の最初の行末に `[1/3]` 形式の virtual text を表示。
セッション更新時に再描画。

### 文字レベル diff

change hunk では、変更前後の行を `vim.diff()` で文字単位比較し、
変更された文字範囲に `CopilotHunkChangeChar` (priority=120) を適用。

## アーキテクチャ

```
plugin/copilot_hunk.lua   ← Neovim 起動時に自動ロード。User Commands を登録。
lua/copilot_hunk/
  init.lua       ← Public API (setup, snapshot, start_session, end_session, arm)
                    auto-snapshot の autocmd 設定 (_setup_auto_snapshot)
  session.lua    ← per-buffer セッション管理
                    _sessions{}, _session_order[], start/stop, accept/reject, goto_next/prev
  decoration.lua ← UI デコレーション (diagnostic API, buffer variable, User event, WinBar)
  diff.lua       ← vim.diff() ラッパー → Hunk[] パーサー
  hunk.lua       ← hunk モデル、accept/reject、offset 再計算、wrap ナビゲーション
  ui.lua         ← extmark による inline 描画 (highlight, virt_lines, virt_text)
  keymap.lua     ← セッション中の buffer-local キーマップ管理
```

## 設定オプション

```lua
require('copilot_hunk').setup({
  -- AI が編集したファイルを自動検出してセッションを開始する (default: true)
  enable_auto_snapshot = true,

  -- サイン列表示 (default: false)
  signs = false,

  -- キーマップを自動設定 (default: true)
  keymaps = true,

  -- n/N でファイルをまたいだ hunk 移動を有効にする (default: true)
  -- false にすると現在バッファ内のみでラップする
  cross_file_navigation = true,

  -- 通知レベル (default: vim.log.levels.WARN = INFOを抑制)
  -- vim.log.levels.INFO にすると全通知を表示
  notify_level = vim.log.levels.WARN,

  -- デコレーション設定
  decorations = {
    winbar = false,  -- WinBar 表示 (default: false)
    icon   = "🤖",  -- WinBar / statusline のアイコン
  },

  -- ハイライトカラーの上書き (省略可)
  highlights = {
    add    = { bg = "#1a2e1a" },
    delete = { bg = "#2e1a1a" },
    change = { bg = "#2a2410" },
  },
})
```

## レビュー済み永続化

ファイル内の全 hunk が accept/reject で解決されると、レビュー済みとして永続保存される。

- accept 完了時に `.git/copilot-hunk-reviewed` にファイルパス + SHA-256 ハッシュを書き込む
- 次回 Neovim 起動時にハッシュ照合し、一致すればスキップ (セッションを開始しない)
- AI が再編集するとファイル内容が変わりハッシュが不一致になるため、自動的に再検出される

## デコレーション

pending hunk のあるバッファには以下のデコレーションが適用される。

### diagnostic API

- `vim.diagnostic.set()` で namespace `copilot_hunk_diag` に HINT エントリを設定
- `vim.diagnostic.config({ float = false, signs = false, underline = false, virtual_text = false }, _ns)` で表示を完全抑制 (プログラム的な読み取り専用)
- nvim-tree / neo-tree はこの diagnostic を自動的に読み取りアイコンを表示する

### バッファ変数

- `vim.b[bufnr].copilot_hunk_active` — セッションがアクティブかどうか (`true` / `false`)
- `vim.b[bufnr].copilot_hunk_count` — pending hunk の数

### autocmd イベント

- `User CopilotHunkSessionChanged` — データ: `{ bufnr, active, pending }`

### statusline_component()

```lua
require("copilot_hunk.decoration").statusline_component()
-- → "🤖 3" (pending hunk がある場合)
-- → ""    (セッションなしの場合)
```

lualine 等のステータスラインプラグインで使用する。

### WinBar

`decorations.winbar = true` にすると、セッション中のバッファの WinBar にロボットアイコンが表示される。

## Non-goals (意図的に実装しないもの)

- **手動セッション開始**: `<leader>as` などのキーでセッションを手動開始するフローは主機能ではない。補助 API (`start_session`) は提供するが、UI としては不要。
- **git 連携**: gitsigns のような git diff との連携は対象外。あくまで AI 編集の差分のみを扱う。
- **undo ベースの差分**: `vim.diff(base, current)` による差分を使用。undo history は使わない。

## Neovim バージョン要件

Neovim >= 0.11.0 必須 (vim.diff, virt_lines, line_hl_group extmarks, default=true in nvim_set_hl)
