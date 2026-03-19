# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-03-19

### Added
- Initial release
- Inline diff display with full-line highlighting (VSCode-style)
- Hunk-level Accept / Reject operations
- Session-based state management (base / ai_result / current)
- Virtual lines for displaying deleted lines inline
- Buffer-local keymaps: `ga`, `gr`, `gn`, `gp`, `gA`, `gR`
- User commands: `:CopilotHunkAccept`, `:CopilotHunkReject`, etc.
- Git-independent diff engine via `vim.diff()`
