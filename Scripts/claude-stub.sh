#!/bin/bash
# Stand-in for the claude CLI, used by Scripts/test.sh. Behaviour comes from
# the file `stub-mode` in the project folder the app is pointed at:
#   echo    print the arguments it was called with (the default)
#   noconv  refuse `--continue` like a folder with no conversation, else answer
#   write   wait a second, then write today's briefing page
#   fail    exit 1 with an error line, like a logged-out CLI
dir="${CLAUDE_ASSISTANT_DIR:-$PWD}"
mode=$(cat "$dir/stub-mode" 2>/dev/null || echo echo)
case "$mode" in
  noconv)
    case " $* " in
      *" --continue "*) echo "No conversation found to continue" >&2; exit 1;;
    esac
    echo "fallback: $*";;
  write)
    sleep 1
    mkdir -p "$dir/briefings"
    echo "<html><body>rebuilt $(date +%s)</body></html>" > "$dir/briefings/$(TZ=Europe/London date +%F).html";;
  fail)
    echo "Failed to authenticate: stub" >&2; exit 1;;
  *)
    echo "args: $*";;
esac
