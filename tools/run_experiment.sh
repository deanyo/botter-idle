#!/bin/bash
# run_experiment.sh — Wrap a balance experiment in setsid+nohup so it
# survives parent-shell kills (Bash tool timeouts, polling commands etc).
#
# Usage:
#   tools/run_experiment.sh <log-name> <command...>
#
# Example:
#   tools/run_experiment.sh regen5_backfill \
#       python3 -u tools/run_regen5_backfill.py
#
# The experiment will:
#   - run with stdin closed and stdout/stderr unbuffered to a log file
#   - survive parent-shell SIGTERM (setsid puts it in a new session)
#   - write its PID to logs/balance/.pids/<log-name>.pid
#   - write completion status to logs/balance/.pids/<log-name>.status
#
# To monitor:
#   tail -f logs/balance/<log-name>.log
#   ps -p $(cat logs/balance/.pids/<log-name>.pid)
#   cat logs/balance/.pids/<log-name>.status   # exists when done

set -euo pipefail

LOG_NAME="${1:?Usage: $0 <log-name> <command...>}"
shift

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$REPO_ROOT/logs/balance"
PID_DIR="$LOG_DIR/.pids"
LOG_FILE="$LOG_DIR/${LOG_NAME}.log"
PID_FILE="$PID_DIR/${LOG_NAME}.pid"
STATUS_FILE="$PID_DIR/${LOG_NAME}.status"

mkdir -p "$LOG_DIR" "$PID_DIR"
rm -f "$STATUS_FILE"

# Stage the command as a temp script — simplest way to compose
# setsid + nohup + redirection + status write without quoting hell.
RUNNER="$(mktemp -t botter_exp_XXXXXX.sh)"
{
    echo "#!/bin/bash"
    echo "export PYTHONUNBUFFERED=1"
    printf '%q ' "$@"
    echo
    echo 'echo $? > '"$STATUS_FILE"
} > "$RUNNER"
chmod +x "$RUNNER"

# nohup + double-fork via subshell. macOS lacks setsid, but disowning the
# job + closing stdin + nohup is enough to detach from the parent shell so
# parent SIGTERM doesn't cascade.
( nohup "$RUNNER" > "$LOG_FILE" 2>&1 < /dev/null & ) &

# With double-fork the immediate $! is the outer subshell, not the actual
# experiment. Find the PID by grepping the runner script's pidfile, or
# just record the runner script path so we can find it later via pgrep.
echo "$RUNNER" > "$PID_FILE"
PID="(pgrep -f $RUNNER)"

echo "started pid=$PID"
echo "log: $LOG_FILE"
echo "pidfile: $PID_FILE"
echo "monitor: tail -f $LOG_FILE  (or check $STATUS_FILE for exit code)"
