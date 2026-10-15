#!/usr/bin/env bash
# codex-dispatch.sh — 把一份 brief 交給 Codex CLI 執行，並把結果整理成 result.json。
# 指揮官只需要「跑一個指令、讀一個檔案」。相容 macOS 內建的 bash 3.2。

set -uo pipefail

usage() {
  cat <<'EOF'
用法: codex-dispatch.sh --brief <file> --cd <repo> [options]

  --brief <file>         任務說明檔（省略則從 stdin 讀）
  --cd <dir>             Codex 的工作目錄（預設：目前目錄）
  --read-only            唯讀沙盒：審查、診斷、提供第二意見，不能改檔
  --network              在 workspace-write 沙盒內開放網路（npm install、curl…）
  --effort <level>       推理強度 low | medium | high | xhigh（預設：使用者 config）
  --model <name>         指定模型（預設：使用者 config）
  --session <thread_id>  接續先前的 session（result.json 的 thread_id），brief 只寫增量指示
  --timeout <sec>        超時秒數（預設 3600；0 = 不限）
  --out <dir>            結果資料夾（預設：自動建立暫存資料夾）
  --skip-git-repo-check  允許在非 git 目錄執行（不建議，無法追蹤改動）
  -h, --help             顯示說明

輸出（在 --out 資料夾內）：
  result.json  狀態、thread_id、改動檔案、用量、錯誤摘要
  final.md     Codex 最後的回報
  events.jsonl 完整事件串流      stderr.txt  完整 stderr      brief.md  實際送出的 brief
EOF
}

die() { echo "codex-dispatch: $*" >&2; exit 2; }

BRIEF="" WORKDIR="$PWD" SANDBOX="workspace-write" NETWORK=false EFFORT="" MODEL=""
SESSION="" TIMEOUT=3600 OUT="" SKIP_GIT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --brief)   BRIEF="${2:-}"; shift 2 ;;
    --cd)      WORKDIR="${2:-}"; shift 2 ;;
    --read-only) SANDBOX="read-only"; shift ;;
    --network) NETWORK=true; shift ;;
    --effort)  EFFORT="${2:-}"; shift 2 ;;
    --model)   MODEL="${2:-}"; shift 2 ;;
    --session) SESSION="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --out)     OUT="${2:-}"; shift 2 ;;
    --skip-git-repo-check) SKIP_GIT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知參數：$1（用 --help 看說明）" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "需要 jq（brew install jq）"
[[ -d "$WORKDIR" ]] || die "工作目錄不存在：$WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd)"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "--timeout 必須是秒數"
[[ "$SANDBOX" == "read-only" && "$NETWORK" == true ]] && die "--read-only 與 --network 不能同時使用（唯讀沙盒一律離線）"

if [[ -z "$OUT" ]]; then
  OUT="$(mktemp -d "${TMPDIR:-/tmp}/codex-run.XXXXXX")" || die "無法建立暫存資料夾"
else
  mkdir -p "$OUT" || die "無法建立 $OUT"
fi
OUT="$(cd "$OUT" && pwd)"

if [[ -n "$BRIEF" ]]; then
  [[ -f "$BRIEF" ]] || die "找不到 brief：$BRIEF"
  cp "$BRIEF" "$OUT/brief.md"
else
  cat > "$OUT/brief.md"
fi
[[ -s "$OUT/brief.md" ]] || die "brief 是空的"

STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_result() { # $1=status $2=exit $3=thread $4=touched(json) $5=usage(json) $6=commits(json) $7=errors(json) $8=codex_version
  jq -n \
    --arg status "$1" --argjson exit "$2" --arg thread "$3" \
    --argjson touched "$4" --argjson usage "$5" --argjson commits "$6" --argjson errors "$7" \
    --arg version "$8" --arg workdir "$WORKDIR" --arg sandbox "$SANDBOX" --argjson network "$NETWORK" \
    --arg model "$MODEL" --arg effort "$EFFORT" --arg session "$SESSION" \
    --arg started "$STARTED" --arg finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson pre_dirty "${PRE_DIRTY:-0}" --arg out "$OUT" \
    '{status:$status, exit_code:$exit, thread_id:(if $thread=="" then null else $thread end),
      touched_files:$touched, pre_existing_changes:$pre_dirty, new_commits:$commits,
      errors:$errors, usage:$usage, codex_version:$version,
      workdir:$workdir, sandbox:$sandbox, network:$network,
      model:(if $model=="" then null else $model end), effort:(if $effort=="" then null else $effort end),
      resumed_session:(if $session=="" then null else $session end),
      started_at:$started, finished_at:$finished,
      files:{brief:($out+"/brief.md"), final:($out+"/final.md"), events:($out+"/events.jsonl"), stderr:($out+"/stderr.txt")}}' \
    > "$OUT/result.json"
}

if ! command -v codex >/dev/null 2>&1; then
  write_result "codex_unavailable" 127 "" null null '[]' '["codex 不在 PATH 上：brew install codex 或 npm i -g @openai/codex，再 codex login"]' ""
  echo "=== Codex run: codex_unavailable ===  result: $OUT/result.json"
  exit 127
fi
CODEX_VERSION="$(codex --version 2>/dev/null | head -1)"

IS_GIT=false
git -C "$WORKDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 && IS_GIT=true
if [[ "$IS_GIT" == false && "$SKIP_GIT" == false ]]; then
  die "$WORKDIR 不是 git repo。先 git init 並 commit 一次，或加 --skip-git-repo-check"
fi
BASE_HEAD=""
PRE_DIRTY=0
if [[ "$IS_GIT" == true ]]; then
  BASE_HEAD="$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || true)"
  PRE_DIRTY="$(git -C "$WORKDIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
fi

# 組 codex 指令。所有 exec 層級的旗標都放在 resume 之前，接續時才會套用。
args=(exec --json -o "$OUT/final.md" -s "$SANDBOX")
[[ "$NETWORK" == true ]] && args+=(-c "sandbox_workspace_write.network_access=true")
[[ -n "$MODEL" ]] && args+=(-m "$MODEL")
[[ -n "$EFFORT" ]] && args+=(-c "model_reasoning_effort=\"$EFFORT\"")
[[ "$SKIP_GIT" == true ]] && args+=(--skip-git-repo-check)
if [[ -n "$SESSION" ]]; then args+=(resume "$SESSION" -); else args+=(-); fi

TO=()
if [[ "$TIMEOUT" -gt 0 ]]; then
  if command -v timeout >/dev/null 2>&1; then TO=(timeout -k 30 "$TIMEOUT")
  elif command -v gtimeout >/dev/null 2>&1; then TO=(gtimeout -k 30 "$TIMEOUT")
  fi
fi

echo "codex-dispatch: 派工中 → ${WORKDIR}（sandbox=${SANDBOX}${SESSION:+, resume=${SESSION}}）  結果資料夾：${OUT}" >&2

ABORTED=false
( cd "$WORKDIR" && exec ${TO[@]+"${TO[@]}"} codex "${args[@]}" < "$OUT/brief.md" > "$OUT/events.jsonl" 2> "$OUT/stderr.txt" ) &
CHILD=$!
trap 'ABORTED=true; kill -TERM "$CHILD" 2>/dev/null' TERM INT HUP
wait "$CHILD"; EXIT=$?
if [[ "$ABORTED" == true ]]; then wait "$CHILD" 2>/dev/null; EXIT=130; fi
trap - TERM INT HUP

THREAD="$(jq -rR 'fromjson? | select(.type=="thread.started") | .thread_id' "$OUT/events.jsonl" 2>/dev/null | head -1)"
[[ -z "$THREAD" && -n "$SESSION" ]] && THREAD="$SESSION"
USAGE="$(jq -cR 'fromjson? | select(.type=="turn.completed") | .usage' "$OUT/events.jsonl" 2>/dev/null | tail -1)"
[[ -z "$USAGE" ]] && USAGE=null

TOUCHED=null
COMMITS='[]'
if [[ "$IS_GIT" == true ]]; then
  TOUCHED="$(git -C "$WORKDIR" status --porcelain 2>/dev/null | jq -R . | jq -s .)"
  NOW_HEAD="$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || true)"
  if [[ -n "$BASE_HEAD" && "$NOW_HEAD" != "$BASE_HEAD" ]]; then
    COMMITS="$(git -C "$WORKDIR" log --oneline "$BASE_HEAD..$NOW_HEAD" 2>/dev/null | jq -R . | jq -s .)"
  fi
fi

if [[ "$ABORTED" == true ]]; then STATUS="aborted"
elif [[ ${#TO[@]} -gt 0 && ( "$EXIT" -eq 124 || "$EXIT" -eq 137 ) ]]; then STATUS="timeout"
elif [[ "$EXIT" -eq 0 && -s "$OUT/final.md" ]]; then STATUS="completed"
else STATUS="failed"
fi

# 錯誤摘要：事件串流裡的 error / turn.failed，加上未完成時的 stderr 尾巴
ERRORS="$(jq -cR 'fromjson? | select(.type=="error" or .type=="turn.failed") | (.message // .error.message // tostring)' "$OUT/events.jsonl" 2>/dev/null | jq -s .)"
[[ -z "$ERRORS" ]] && ERRORS='[]'
if [[ "$STATUS" != "completed" ]]; then
  TAIL="$(grep -v '^[[:space:]]*$' "$OUT/stderr.txt" 2>/dev/null | tail -15 | jq -R . | jq -s .)"
  ERRORS="$(jq -n --argjson a "$ERRORS" --argjson b "${TAIL:-[]}" '$a + $b')"
fi

write_result "$STATUS" "$EXIT" "$THREAD" "$TOUCHED" "$USAGE" "$COMMITS" "$ERRORS" "$CODEX_VERSION"

echo "=== Codex run: $STATUS (exit $EXIT) ==="
echo "thread_id: ${THREAD:-（無）}"
echo "result:    $OUT/result.json"
if [[ "$TOUCHED" != null ]]; then
  echo "改動檔案:  $(jq 'length' <<<"$TOUCHED") 個（派工前已有 $PRE_DIRTY 個未提交改動）"
fi
[[ "$COMMITS" != '[]' ]] && echo "⚠ Codex 自己 commit 了：$(jq -r 'join("; ")' <<<"$COMMITS")"
if [[ "$STATUS" != "completed" ]]; then
  echo "--- 錯誤摘要 ---"; jq -r '.[]' <<<"$ERRORS"
fi
echo "--- Codex 回報 ---"
if [[ -s "$OUT/final.md" ]]; then cat "$OUT/final.md"; echo; else echo "（沒有最終回報）"; fi
exit "$EXIT"
