# 寫 brief

brief 就是 Codex 看到的**整個世界**。它在一個全新的 process 裡執行，不知道你和使用者聊過什麼、讀過哪些檔案、做過哪些決定，只看得到 brief 和 working tree。

最常見的失敗就是 brief 預設了 Codex 根本沒有的脈絡。寫完之後用這個問題檢查一遍：**一個第一天報到、很聰明的工程師，只拿到這份文件，能不能做對？**

## 基本骨架

用 XML 區塊，不要寫成長篇散文。要什麼區塊就加什麼，不要為了格式塞空區塊。

```xml
<task>
One or two sentences: the concrete job and where it lives.
Current state: what exists now and what is wrong / missing.
Change: exactly what to do.
Do NOT touch: files, APIs, behaviours that must stay as they are.
Context Codex cannot discover itself: decisions already made with the user, constraints, naming.
</task>

<verification_loop>
Run these before finishing and fix anything they surface — do not just report failures:
  <real test command found in the repo>
  <real lint / format command>
  <real build / typecheck command>
Then confirm `git status` shows only the intended files changed.
</verification_loop>

<action_safety>
Keep changes strictly scoped to the task. No unrelated refactors, renames, reformatting or cleanup.
Do NOT run git add, git commit, git push, or switch branches — leave all work uncommitted in the
working tree; the reviewer commits after verification.
Do not weaken, skip or delete existing tests to make them pass.
</action_safety>

<structured_output_contract>
End with a report in exactly this shape:
1. What changed and why (short)
2. Files touched
3. Verification commands run and their results (paste counts / key lines)
4. Deviations from this brief, open questions, or decisions you made that the reviewer should confirm
</structured_output_contract>
```

## 依任務類型加的區塊

**除錯或開放式修復**

```xml
<completeness_contract>
Find the root cause before changing code. Do not stop at the first plausible fix; check for
follow-on fixes, edge cases and cleanup required for a correct result.
</completeness_contract>

<missing_context_gating>
Do not guess repository facts. If something required is missing, find it with tools, or state
exactly what remains unknown instead of inventing it.
</missing_context_gating>
```

**審查、診斷、第二意見**（搭配 `--read-only`）

```xml
<grounding_rules>
Ground every claim in files or command output you inspected; cite file:line.
Label inferences and hypotheses explicitly. Do not present guesses as facts.
</grounding_rules>
```

**想讓 Codex 不要停下來問問題**

```xml
<default_follow_through_policy>
Pick the most reasonable low-risk interpretation and keep going. Only stop when a missing detail
changes correctness or would require an irreversible action.
</default_follow_through_policy>
```

**研究或技術選型**

```xml
<research_mode>
Separate observed facts, inferences, and open questions. Prefer primary sources.
</research_mode>
```

## 寫好 brief 的要點

- **驗證指令要是真的。** 從 `package.json`、`Makefile`、`CLAUDE.md`、`AGENTS.md` 抄實際的指令下來。只寫「跑測試」的話，Codex 會自己猜，或乾脆跳過。
- **「不准動」清單寫具體一點。** 這是防止 Codex 順手重構的主要手段。
- **把你已經知道的事實寫進去。** 你偵察時查到的檔案路徑、函式名稱、和使用者談好的設計決定都放進 brief，省下 Codex 重新探索的時間，也避免它做出不同的判斷。
- **repo 的規矩要重申一次。** `AGENTS.md` 裡的規則 Codex 會自己讀，但最關鍵的幾條還是在 brief 裡再講一次比較保險。
- **不要叫它「想仔細一點」。** 要提升品質，就把驗收條件寫清楚、把回報格式訂好。真的需要更多推理，就用 `--effort high`。
- **一份 brief 一件事。** 「審查、修 bug、更新文件、規劃 roadmap」要拆成四次派工。
- **派工那一刻前提就固定了。** Codex 執行中你無法插話。發現前提錯了就中止，修正 brief 再重派，不要事後才把結果打折扣。
- **iOS / Xcode 專案**：寫出完整的 `xcodebuild` 指令（scheme、destination）。沙盒裡可能跑不了模擬器，可以請它至少跑 `build`，模擬器測試由你在驗收時跑。

## 增量 brief（返工用）

搭配 `--session <thread_id>`，只寫要修正的地方，不必重寫整份：

```
Review of your change: the fix in auth.ts is correct, but
1. The new test mocks `validateToken` — use the real implementation with the fixture in tests/fixtures/tokens.json.
2. Remove the unused `lodash` import you added in session.ts.
Re-run `npm test -- auth` and report in the same format as before.
```

## 完整範例

```xml
<task>
In the SwiftUI app at ChatBotApp/, the chat list (Views/ChatListView.swift) does not refresh after a
conversation is deleted from ChatDetailView — the deleted row stays until relaunch.
Root cause hint from the reviewer: ChatStore.delete(_:) mutates `conversations` on a background
queue without publishing on the main actor.
Change: make deletion publish on the main actor so the list updates immediately.
Do NOT touch: the persistence format in Storage/, the LLM inference code in Engine/, any UI layout.
</task>

<completeness_contract>
Confirm the root cause before changing code; check whether ChatStore.rename(_:) has the same bug and
fix it the same way if so.
</completeness_contract>

<verification_loop>
xcodebuild -scheme ChatBotApp -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme ChatBotApp -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:ChatBotAppTests/ChatStoreTests
If the simulator is unavailable in your sandbox, run the build only and say so in the report.
</verification_loop>

<action_safety>
Scope strictly to ChatStore and its tests. Do NOT git add or commit. Do not weaken existing tests.
</action_safety>

<structured_output_contract>
1. Root cause (confirmed or not) and fix
2. Files touched
3. Build / test results
4. Anything left open
</structured_output_contract>
```
