#!/bin/bash
# Stand-in for the claude CLI, used by Scripts/test.sh. Behaviour comes from
# the file `stub-mode` in the project folder the app is pointed at:
#   echo    answer with the arguments it was called with (the default)
#   noconv  refuse `--continue` like a folder with no conversation, else answer
#   write   wait a second, then write today's briefing page
#   fail    exit 1 with an error line, like a logged-out CLI
#   denied  answer, but report a refused tool
# Answers are in Claude's `--output-format json` shape, with a fixed cost.
dir="${CONCIERGE_DIR:-$PWD}"
mode=$(cat "$dir/stub-mode" 2>/dev/null || echo echo)

answer() { # $1 = result text, $2 = extra JSON fields (optional)
  printf '{"type":"result","subtype":"success","is_error":false,"duration_ms":1234,"num_turns":3,"result":"%s","session_id":"stub-session","total_cost_usd":0.0125,"usage":{"input_tokens":100,"cache_creation_input_tokens":2000,"cache_read_input_tokens":3000,"output_tokens":50},"modelUsage":{"claude-opus-5-5[1m]":{}},"permission_denials":[%s]}\n' "$1" "${2:-}"
}

case "$mode" in
  noconv)
    case " $* " in
      *" --continue "*) echo "No conversation found to continue" >&2; exit 1;;
    esac
    answer "fallback: $*";;
  write)
    sleep 1
    mkdir -p "$dir/briefings"
    echo "<html><body>rebuilt $(date +%s)</body></html>" > "$dir/briefings/$(TZ=Europe/London date +%F).html"
    answer "Wrote the page.";;
  fail)
    echo "Failed to authenticate: stub" >&2; exit 1;;
  denied)
    answer "Could not read mail." '{"tool_name":"mcp__claude_ai_Gmail__search_threads","tool_use_id":"x","tool_input":{}}';;
  *)
    answer "args: $*";;
esac
