# ADR-0002: AI編集適用後ロールバック型の hunk 単位レビュー機構

- **Status**: Accepted
- **Date**: 2026-03-19
- **Decision Makers**: 開発者
- **Supersedes**: ADR-0001

---

## Context

GitHub Copilot CLI などの AI によるコード編集結果を、  
**VS Code ライクにバッファ上で差分表示し、hunk 単位で Accept / Reject したい**という要件がある。

求める体験は以下。

- ユーザーが途中まで手動編集している状態で AI を呼び出す
- AI がファイルを直接書き換える
- 変更差分が色付きでバッファに表示される
- 各差分ブロック（hunk）ごとに Accept / Reject できる
- Reject しても、AI 実行前の手動編集は失われない

重要な点として、VS Code 上の Copilot は以下の挙動を取る。

- AI の変更は **一度適用される**
- Reject は「未適用にする」のではなく  
  **AI リクエスト直前の状態にロールバックする**

この挙動を再現する必要がある。

---

## Decision

**AI 編集は必ず一度適用し、その後のレビュー操作で部分的にロールバックする方式を採用する。**

具体的には：

- AI 実行直前の状態を **`base snapshot`** として保存
- AI 実行後の状態を **`ai_result`** とする
- バッファには `ai_result` をそのまま表示する
- Reject 時は対象 hunk を `base snapshot` に戻す

---

## Decision Drivers

1. VS Code Copilot の挙動と一致させる
2. ユーザーの手動編集を破壊しない
3. 差分レビューを直感的にする（「適用済み → 差し戻し」モデル）
4. Git に依存しない設計にする
5. 未保存バッファを扱えるようにする
6. hunk 単位で細かく制御可能にする

---

## Core Model

レビューセッションでは以下の3状態を保持する。

### `base`
AI 実行直前のバッファ内容  
（ユーザーの手動編集を含む）

### `ai_result`
AI 実行後のバッファ内容  
（すでにバッファに適用されている）

### `current`
レビュー操作後の現在状態  
（accept / reject により変化）

初期状態は：

```text
current = ai_result
```

---

## Operation Semantics

### Accept

```text
対象 hunk をそのまま維持する
```

- `current` は変更なし
- 状態フラグのみ更新（accepted）

---

### Reject

```text
対象 hunk を base snapshot に戻す
```

- `current` の該当範囲を `base` の内容で置換
- 後続 hunk の位置を再計算

---

## Flow

```text
1. ファイルを開く
2. ユーザーが手動編集
3. AI 実行直前に base snapshot を保存
4. AI が編集（ファイルを書き換える）
5. ai_result を取得（= 現在バッファ）
6. base と ai_result の diff を生成
7. hunk ごとに UI 表示
8. Accept / Reject を適用
9. 最終状態を保存
```

---

## Key Principle

**差分の基準は常に「AI 実行単位」**

```text
base snapshot ↔ ai_result
```

以下は採用しない：

- Git HEAD 基準
- ファイルオープン時基準
- AI 出力テキスト基準

---

## UI Specification

Neovim 上での表示仕様。

### 表示

- 追加行: 緑
- 削除行: 赤（virtual lines）
- 変更行: ハイライト
- hunk 単位で境界管理

### 操作

- `ga`: accept hunk
- `gr`: reject hunk
- `gn`: next hunk
- `gp`: prev hunk
- `gA`: accept all
- `gR`: reject all

---

## Data Model

```lua
Hunk = {
  id = number,
  start_before = number,
  end_before = number,
  start_after = number,
  end_after = number,
  before_lines = string[],
  after_lines = string[],
  status = "pending" | "accepted" | "rejected",
  type = "add" | "delete" | "change"
}
```

---

## Implementation Strategy

### 差分生成

```bash
git diff --no-index --unified=3 base tmp_after
```

または内部 diff エンジンを使用。

---

### 描画

- extmarks: 範囲管理
- signs: 行マーカー
- virt_lines: 削除行表示

---

### Reject 実装

```text
current_buffer[range] = base_lines
```

パッチ適用ではなく **直接バッファ置換** を採用する。

理由：

- 安定性が高い
- context mismatch を回避できる
- Neovim 内で完結

---

## Session Rules

### セッション開始

- AI 実行時に `base` を保存

### セッション中

- `current` を操作対象とする

### セッション終了

- 全 hunk が確定した時点で通常状態へ戻る

---

## Edge Cases

### AI 後に手動編集が入る場合

MVP 方針：

- 非推奨とする
- 編集検知時はセッション無効化または再計算

---

### フォーマッタが走る場合

問題：

- 差分が大量発生

対策：

- AI edit と format を分離
- format は別セッションで扱う

---

### 複数ファイル変更

- ファイル単位で `base` を保持
- MVP は単一ファイルのみ対応

---

## Consequences

### Positive

- VS Code Copilot と同じ操作モデル
- 手動編集が安全に保持される
- 直感的（「戻す」だけ）
- Git 非依存
- AI エンジン非依存

---

### Negative

- 状態管理が増える
- hunk 再配置ロジックが必要
- セッション概念が必須

---

## Rejected Alternatives

### 未適用提案モデル

```text
提案を見て accept したものだけ適用
```

理由：

- VS Code の UX と異なる
- 差分プレビューと実バッファが乖離する

---

### Git ベースパッチ適用

理由：

- 未保存バッファに弱い
- context mismatch が発生する
- UX が複雑

---

## Summary

本設計の本質は以下。

```text
AI変更は先に適用する
→ ユーザーが不要な部分だけロールバックする
```

つまり：

```text
Accept = 何もしない
Reject = 部分的に巻き戻す
```

このモデルにより、**手動編集と AI 編集を明確に分離しつつ、直感的な差分操作を実現する。**
