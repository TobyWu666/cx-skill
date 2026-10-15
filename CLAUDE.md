# cx-skill 維護規則

這個 repo 是 Claude Code plugin marketplace，發布在 GitHub：TobyWu666/cx-skill（public）。

- 只要改了 plugin 的內容，就要同時更新 `plugins/<name>/.claude-plugin/plugin.json` 和 `.claude-plugin/marketplace.json` 裡的 `version`，兩邊的版本號必須一致。沒有提高版本號，已安裝的人就收不到更新。
- 每次發版都要在 `CHANGELOG.md` 補上這一版的紀錄。
- 發版前先跑 `claude plugin validate .`。
- 發版流程：commit → push → `claude plugin tag plugins/<name> --push`。
- 改了 `codex-dispatch.sh` 之後，要在 scratchpad 用一個暫時的 git repo 實際跑過再發版。至少測新任務、`--session` 接續、`--read-only`。腳本要相容 macOS 內建的 bash 3.2：不能用 associative array，變數後面緊接中文字元時要寫成 `${VAR}`。
- 這個資料夾在 iCloud 裡，git 資料放在 `~/.git-repos/cx-skill.git`（用 `--separate-git-dir` 分開），所以 `.git` 是一個檔案，不是資料夾。
