# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.6] - 2026-03-20
### Fixed
- Accept後もhunkハイライトが消えないバグを修正 (`render()` が accepted hunks も描画していた)
- `ui.lua` の `col out of range` エラーを修正 (reject後バッファ行長変化時に col_start が範囲外)

## [0.3.5] - 2026-03-20
### Fixed
- Telescope/FZF/nvim-tree でファイルを開いたときhunkが表示されない問題を修正
- hidden buffer と listed buffer の重複を解消 (`_transfer_session`)
- `BufEnter` ハンドラを3ケース対応に拡張 (既存session再描画、path-based転送、通常フロー)

## [0.3.4] - 2026-03-20
### Fixed
- accept後に別Neovimセッション（別WezTermタブ等）で同じhunkが再表示されるバグを修正
- `.git/copilot-hunk-reviewed` にSHA-256ハッシュを永続保存、次回起動時にスキップ
### Added
- `notify_level` オプション追加（デフォルト: `vim.log.levels.WARN`）
- INFO通知（"Review started", "No pending hunks" 等）をデフォルトで抑制

## [0.3.3] - 2026-03-20
### Fixed
- `n`/`N` で移動して開いたバッファにシンタックスハイライトとLSPが適用されない問題を修正
- `_open_buffer()` で `:edit` 経由でバッファを開くことで完全なautocmdチェーンを発火

## [0.3.2] - 2026-03-20
### Added
- AIが新規作成したファイルの検出・accept/rejectに対応（accept=保存、reject=削除）
- AIが削除したファイルの検出・accept/rejectに対応（accept=削除、reject=復元）
- `git ls-files --others` / `git ls-files --deleted` による新規/削除ファイル検出
### Fixed
- `diff({}, lines)` / `diff(lines, {})` のエッジケース修正

## [0.3.1] - 2026-03-19
### Added
- `cross_file_navigation` オプション追加（デフォルト: true）
- 未ロードバッファを `git diff --name-only HEAD` で検出しグローバルカウンターに反映
- `[1/2]` のようにすべてのAI変更ファイルにまたがったグローバルhunkカウンター

## [0.3.0] - 2026-03-19
### Fixed
- 非アクティブバッファへのAI変更が検出されないバグを修正
- タイミング起因のバグ（保存後すぐのchecktime等）を修正
### Added
- `BufEnter` ハンドラ：非アクティブバッファへの変更を checktime で検出

## [0.2.0] - 2026-03-19
### Added
- グローバルhunkカウンター（全AIファイルにわたる `[1/4]` 表示）
- ロボアイコン🤖 デコレーション (nvim-tree/neo-tree/statusline連携)
- `decoration.statusline_component()` — lualine等での `🤖 N` 表示
- `User CopilotHunkSessionChanged` autocmdイベント
- `vim.b.copilot_hunk_active` / `vim.b.copilot_hunk_count` バッファ変数
- `decorations.winbar` オプション

## [0.1.0] - 2026-03-19
### Added
- Initial release
- Inline diff display with full-line highlighting (VSCode-style)
- Hunk-level Accept / Reject operations
- Auto-detection via FileChangedShell / FocusGained
- Formatter false-positive guard (BufWritePre 2-second timestamp)
- Virtual lines for deleted content inline display
- Character-level diff highlighting within change hunks
- 2-tier colouring: muted line background + vivid text overlay
- Buffer-local keymaps: `n`, `N`, `ga`, `gr`, `gA`, `gR`, `gAA`, `gRR`
- User commands: `:CopilotHunkAccept`, `:CopilotHunkReject`, etc.
- Cross-file navigation with `_session_order`
- Git-independent diff engine via `vim.diff()`
- Neovim ≥ 0.11 requirement
