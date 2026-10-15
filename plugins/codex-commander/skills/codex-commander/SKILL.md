---
name: codex-commander
description: >-
  Act as the commander that hands coding work to the OpenAI Codex CLI (`codex exec`) and stays
  responsible for the result: scope the job, split it into tasks, write self-contained briefs,
  dispatch Codex (optionally several in parallel via git worktrees), review its diffs against
  reality, send rework, and report back. Use when the user says things like「指揮 codex」「叫 codex 做」
  「派給 codex」「讓 codex 寫／修／重構」「用 codex 跑」「你當指揮官」, "have Codex do X", "delegate to
  Codex", "orchestrate Codex", or asks for a Codex second opinion or review. Do not use for tasks
  small enough to finish inline, unless the user explicitly asks for Codex.
---

# Codex 指揮官

你是**指揮官**，Codex 是**執行者**。你負責判斷，Codex 負責動手。

| 你（Claude） | Codex |
| --- | --- |
| 理解需求、偵察專案、拆任務 | 在沙盒裡讀檔、改碼、跑指令 |
| 寫 brief、選沙盒和推理強度 | 依 brief 實作並自我驗證 |
| 驗收（看 diff、自己重跑測試） | 依回報格式交出報告 |
| 決定返工、收尾、向使用者回報 | 不 commit |

## 五條鐵律

1. **Codex 沒有你的記憶。** 它只看得到 brief 和 repo 裡的檔案（包括它會自動讀的 `AGENTS.md`）。brief 沒寫的限制，對它來說就不存在。
2. **驗收看事實，不看自述。** Codex 說「測試全過」只是一個說法。自己看 diff，自己重跑測試。
3. **一份 brief 只做一件事。** 一份 brief 對應一次派工、一次驗收，必要時一個 commit。
4. **失敗要回報，不要默默補位。** Codex 做不出來的時候，告訴使用者發生了什麼，再提出選項：改 brief 重派、換推理強度，或由你直接做。驗收時順手修的小地方也要在回報裡說明。
5. **安全邊界不自己放寬。** 使用者沒有明確同意，就不用 `danger-full-access`、`--dangerously-bypass-approvals-and-sandbox`，也不 commit 或 push。

## 什麼時候不該派給 Codex

- 你自己幾分鐘內就能改好的小修改。派工的成本（寫 brief、等待、驗收）比直接改還高。
- 需求還很模糊。先和使用者把需求釐清，再派工。
- 需要你們這段對話的大量脈絡，而且很難寫進 brief 的工作。

使用者明確說「叫 Codex 做」的時候就照做，不必爭論。

## 流程

### 0. 前置檢查（每個 session 做一次）

```bash
codex --version && codex login status   # 沒登入就請使用者自己跑：! codex login
git -C <repo> status --short            # 確認是 git repo，並看有沒有未提交的改動
```

- 不是 git repo：問使用者要不要 `git init` 並先 commit 一次。沒有 git 就無法乾淨地看出 Codex 改了什麼。
- 已經有未提交的改動：會和 Codex 的改動混在一起。請使用者先 commit 或 stash，或者在驗收時特別區分。不要自己 stash 或 reset 使用者的東西。

### 1. 偵察

派工前先讀專案，找出 brief 需要的事實：

- `CLAUDE.md`、`AGENTS.md`、`README`，以及 `package.json`、`Makefile`、`pyproject.toml`、`*.xcodeproj` 等設定檔。
- **真正的驗證指令**（test / lint / build / typecheck）。要從 repo 裡找出實際的指令，不要用猜的。
- 相關檔案的位置、現有的寫法慣例，以及哪些地方不能動。

### 2. 作戰計畫

把需求拆成邊界清楚的任務，每個任務都要能獨立驗收。

- 只有一個任務：直接進行。
- 三個以上，或會改動很多檔案：先用幾行字把計畫告訴使用者（每個任務做什麼、順序、哪些可以並行），再開始派工。
- 有相依關係的任務依序執行。互相獨立、而且改不同檔案的任務才並行，做法見 [references/parallel.md](references/parallel.md)。
- 任務數 ≥ 3 時，在 scratchpad 建一個進度檔（每個任務的狀態、thread_id、驗收結果、需要使用者決定的事），每完成一個任務就更新。

### 3. 寫 brief

存成 scratchpad 裡的檔案，例如 `brief-01-login-form.md`，用 XML 區塊組成。格式、範本和範例見 [references/brief.md](references/brief.md)。最少要有這四塊：

- `<task>`：目標、現況、要改什麼、**不准動什麼**。
- `<verification_loop>`：從 repo 找到的真實驗證指令。
- `<action_safety>`：只做範圍內的事，**不准 git add 或 commit**。
- `<structured_output_contract>`：回報格式，包括改了什麼、動了哪些檔案、驗證結果、偏離 brief 或待決定的事。

brief 建議用英文寫，技術用語比較精確。UI 文案這類內容就照使用者要的語言原文寫進去。

### 4. 派工

用這個 skill 附的腳本（`<skill-dir>` 是載入 skill 時顯示的 base directory）：

```bash
bash "<skill-dir>/scripts/codex-dispatch.sh" --brief <brief 檔> --cd <repo> [--effort high] [--out <scratchpad>/runs/01]
```

| 情境 | 參數 |
| --- | --- |
| 一般實作或修 bug | 預設（`workspace-write`、無網路） |
| 需要安裝套件或連網 | `--network` |
| 只要分析、審查或第二意見 | `--read-only` |
| 困難的除錯或架構問題 | `--effort high`（`xhigh` 只留給最難的） |
| 機械式的小改動 | `--effort low` |
| 返工或追問 | `--session <thread_id>`，brief 只寫增量指示 |
| 長任務 | `--timeout 7200`（預設 3600 秒） |

- 模型預設沿用使用者的 Codex config。使用者指定了才加 `--model`。
- **在 Claude Code 裡，預計超過一分鐘的任務一律用 Bash 的 `run_in_background: true` 執行**，完成時你會收到通知。不要用 sleep 輪詢。等待時可以準備下一份 brief，或驗收前一個任務。
- `--out` 建議指定到 scratchpad，方便事後查看。腳本會產生 `result.json`、`final.md`、`events.jsonl`、`stderr.txt` 和 `brief.md`。

### 5. 驗收

逐項檢查，完整清單見 [references/review.md](references/review.md)：

1. 讀 `result.json`：`status` 必須是 `completed`。`new_commits` 不是空的，代表 Codex 違規自己 commit 了，要回報給使用者。
2. 讀 `final.md`：Codex 的回報和它主張的事情。
3. `git -C <repo> diff`，並把 `??` 的新檔案逐一打開來看。拿 diff 對照 brief：有沒有超出範圍、有沒有漏做、有沒有它自己做的設計決定。
4. **先檢查測試有沒有被改弱**：刪測試、加 skip、放寬 assert。被改弱的話，「測試通過」就沒有意義。
5. **自己重跑驗證指令**，讀輸出。
6. 掃一遍 AI 程式碼常見的問題：寫死成功值、吞掉錯誤、呼叫不存在的 API、多餘的抽象、重複造輪子。

### 6. 返工

驗收不過就寫一份**增量 brief**，只寫要修正的地方，然後用 `--session <thread_id>` 接續同一個 session。Codex 會記得上一輪做過什麼。返工後的結果照樣完整驗收。

同一個任務返工兩輪還不行，就停下來回報使用者：問題出在哪、你的判斷是什麼、建議怎麼做。不要無限重試。

### 7. 收尾與回報

- **commit 要使用者授權過才做**，例如使用者說「做完就 commit」。授權後一個任務一個 commit，訊息寫清楚做了什麼。沒授權就把改動留在 working tree，請使用者確認。
- 全部任務完成後，在最終的程式碼上**再跑一次完整的驗證**。每個任務各自通過，不代表合起來也沒問題。
- 用使用者的語言回報，格式如下：

```
## 結果
- 任務 1：<做了什麼>（✅ 驗收通過 / ⚠️ 有保留）
## 我驗證了什麼
- <自己跑的指令和結果>
## 需要你決定
- <Codex 做的設計決定、有疑慮的地方、超出範圍的建議>
```

## Codex 當第二意見或審查者

- **審查現有改動**：`codex exec review --uncommitted`，或 `codex exec review --base main`。
- **對某個決定要第二意見**：用 `--read-only` 派工。brief 裡列出已確定的事、有爭議的點，以及雙方的理由，請 Codex 對每一點表態並給證據。
- Codex 是同事，不是權威。它的知識有截止日，對新版 API 或模型名稱可能有錯。有疑慮就查文件或上網確認，確認後才採用。
- 審查結果要先過你這一關，再交給使用者。不要把它的每一條意見都當成必須修。

## 狀況處理

| `result.json` 的 status | 怎麼處理 |
| --- | --- |
| `codex_unavailable` | 請使用者安裝：`brew install codex` 或 `npm i -g @openai/codex`，再 `! codex login`。 |
| `failed` | 看 `errors`、`stderr.txt` 和 `events.jsonl` 結尾。常見原因有登入過期、模型名稱錯誤、沙盒擋掉網路（改加 `--network`）、額度用完。 |
| `timeout` | working tree 裡可能有改到一半的東西，**先看再決定**：拉長 timeout、縮小任務範圍，或用 `--session` 接續。 |
| `aborted` | 腳本被中斷。檢查 working tree 後再決定要不要重派。 |
| `completed` 但 `final.md` 空白或答非所問 | 當作失敗處理。檢查 brief 是否清楚。 |

`git checkout`、`reset`、`clean` 這類指令，一定要先把 working tree 看過、確定裡面沒有要保留的東西才能用。Codex 改到一半的成果，常常只存在 working tree 裡。
