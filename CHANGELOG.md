# Changelog

## codex-commander

### 0.1.0 — 2026-10-15

- 第一版。
- SKILL.md：說明 Claude 和 Codex 的分工、五條鐵律，以及從前置檢查到收尾回報的七步流程。
- `codex-dispatch.sh`：包裝 `codex exec`，結果輸出成 `result.json`。支援接續 session、唯讀模式、開網路、設定超時，被中斷時也會記錄狀態。
- references：寫 brief 的方法、驗收清單、用 git worktree 並行派工的流程。
