# cx-skill

一個 Claude Code plugin marketplace。目前收錄一個 plugin：

| Plugin | 說明 |
| --- | --- |
| [codex-commander](plugins/codex-commander) | 讓 Claude 當指揮官，把寫程式的工作派給 OpenAI Codex CLI，再自己驗收 |

## 安裝

在 Claude Code 裡執行：

```
/plugin marketplace add TobyWu666/cx-skill
/plugin install codex-commander@cx-skill
```

使用前要先準備好：

- [Codex CLI](https://github.com/openai/codex)，已經安裝並執行過 `codex login`
- `jq`
- `git`

## 更新

```
/plugin marketplace update cx-skill
```

也可以打開 `/plugin`，到 Marketplaces 分頁開啟自動更新。

## codex-commander

```
你 ──需求──▶ Claude（指揮官）──brief──▶ Codex（執行者）
                │  偵察、拆任務、寫 brief         │  在沙盒裡改碼、跑測試
                │◀────────── 回報 + diff ─────────┘
                │  看 diff、重跑測試、返工、收尾
你 ◀──結果、驗證過程、需要你決定的事──┘
```

裝好之後直接說「叫 codex 幫我做 X」或「你當指揮官指揮 codex」，skill 就會啟動。

```
plugins/codex-commander/skills/codex-commander/
├── SKILL.md                    角色、鐵律、七步流程、狀況處理
├── scripts/codex-dispatch.sh   派工腳本：包裝 codex exec，輸出 result.json
└── references/
    ├── brief.md                怎麼寫 Codex 看得懂的 brief
    ├── review.md               驗收清單
    └── parallel.md             用 git worktree 同時派多個 Codex
```

`codex-dispatch.sh` 也可以單獨使用，`--help` 可以看完整參數。輸出的 `result.json` 包含這些欄位：

| 欄位 | 說明 |
| --- | --- |
| `status` | `completed`、`failed`、`timeout`、`aborted`、`codex_unavailable` |
| `thread_id` | 返工時用 `--session <thread_id>` 接續同一個 session |
| `touched_files` | 跑完後的 `git status --porcelain` |
| `pre_existing_changes` | 派工前就已經存在的未提交改動數 |
| `new_commits` | Codex 違規自己 commit 的紀錄（正常應該是空陣列） |
| `errors` | 錯誤摘要 |
| `usage` | token 用量 |

## 發新版（維護者）

1. 修改 skill 的內容。
2. 同時更新兩個地方的版本號，兩邊必須一致：
   - `plugins/codex-commander/.claude-plugin/plugin.json` 的 `version`
   - `.claude-plugin/marketplace.json` 裡這個 plugin 的 `version`
3. 在 `CHANGELOG.md` 寫下這一版改了什麼。
4. 檢查格式：`claude plugin validate .`
5. commit 並 push。
6. 打版本標籤並推上去：`claude plugin tag plugins/codex-commander --push`

已經安裝的人執行 `/plugin marketplace update cx-skill` 就會拿到新版。**沒有提高版本號的話，已安裝的人不會收到更新。**

版本號這樣跳：

| 改動 | 版本 |
| --- | --- |
| 修錯字、修 bug | 0.1.0 → 0.1.1 |
| 新增功能、調整流程 | 0.1.0 → 0.2.0 |
| 不相容的大改 | 0.x → 1.0.0 |

## 參考來源

- [amElnagdy/delegate-skills](https://github.com/amElnagdy/delegate-skills)：「brief → 派工 → 驗收 → 收尾」流程與驗收清單
- [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc)：Codex prompt 區塊寫法
- [skills-directory/skill-codex](https://github.com/skills-directory/skill-codex)：把 Codex 當同事而非權威

## License

MIT
