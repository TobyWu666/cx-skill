# 並行派工（多個 Codex 同時執行）

預設**依序執行**：一個任務驗收完、收尾之後，才派下一個。這樣每次的 diff 都只包含那個任務的改動，驗收最乾淨。

只有在下面三個條件**全部成立**時才並行：

1. 任務之間沒有相依關係，B 不需要 A 的成果。
2. 改動的檔案幾乎不重疊。
3. 每個任務都要花上幾分鐘以上，並行才省得到時間。

同時最多 **2 到 3 個**。ChatGPT 方案有速率和額度限制，而且驗收的負擔也落在你身上。

## 每個任務一個 git worktree

絕對不要讓兩個 Codex 在同一個資料夾裡同時改東西。

```bash
REPO=<repo 絕對路徑>
WT=<scratchpad>/wt          # worktree 放在 scratchpad，不要污染使用者的資料夾
git -C "$REPO" worktree add -b codex/<slug-a> "$WT/<slug-a>" HEAD
git -C "$REPO" worktree add -b codex/<slug-b> "$WT/<slug-b>" HEAD
```

worktree 裡**沒有** `node_modules`、`Pods`、build 產物和 `.env` 這類沒被 git 追蹤的檔案。所以要嘛在 brief 裡告訴 Codex 先跑安裝指令（並加 `--network`），要嘛事先由你準備好，例如把 `node_modules` symlink 過去。

## 同時派工

每個任務各下一次 Bash call，都設成 `run_in_background: true`：

```bash
bash "<skill-dir>/scripts/codex-dispatch.sh" --brief <scratchpad>/brief-a.md --cd "$WT/<slug-a>" --out <scratchpad>/runs/a
bash "<skill-dir>/scripts/codex-dispatch.sh" --brief <scratchpad>/brief-b.md --cd "$WT/<slug-b>" --out <scratchpad>/runs/b
```

哪個先完成就先驗收哪個。驗收步驟和 [review.md](review.md) 一樣，只是指令裡的路徑換成各自的 worktree。

## 把成果合回主 repo

驗收通過後，看使用者有沒有授權 commit：

**使用者授權過 commit**：在 worktree 裡 commit，再到主 repo 合併。

```bash
git -C "$WT/<slug-a>" add -A && git -C "$WT/<slug-a>" commit -m "<message>"
git -C "$REPO" merge --no-ff codex/<slug-a>     # 或 cherry-pick
```

**沒授權**：把改動以未提交的狀態帶回主 repo，交給使用者看。

```bash
git -C "$WT/<slug-a>" add -A                    # 只是為了讓新檔案也進 diff，不會 commit
git -C "$WT/<slug-a>" diff --cached --binary | git -C "$REPO" apply
```

合回第二個任務時如果有衝突，停下來處理，並告訴使用者。全部合併完之後，在主 repo **跑一次完整驗證**。

## 清理

確定改動都已經合回主 repo、不再需要之後：

```bash
git -C "$REPO" worktree remove --force "$WT/<slug-a>"
git -C "$REPO" branch -D codex/<slug-a>
```

刪 worktree 之前，確認裡面沒有還沒帶回的改動。
