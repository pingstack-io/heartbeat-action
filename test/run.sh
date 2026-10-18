#!/usr/bin/env bash
# Runs ping.sh against a local stub server. Usage: test/run.sh
set -u
cd "$(dirname "$0")/.."

python_bin="$(command -v python3 || command -v python)"
port=48217
base="http://127.0.0.1:$port"
work="$(mktemp -d)"
failures=0
server_pid=""

start_server() {
  [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null && wait "$server_pid" 2>/dev/null
  : > "$work/requests"
  "$python_bin" test/stub_server.py --port "$port" --log "$work/requests" --statuses "$1" &
  server_pid=$!
  for _ in $(seq 1 50); do curl -sf -o /dev/null "$base/__ready" && break; sleep 0.1; done
}
trap '[ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null; rm -rf "$work"' EXIT

# run_action KEY=VALUE... : runs ping.sh with those INPUT_ variables; sets $exit_code, $out, $stdout.
run_action() {
  : > "$work/output"
  env -i PATH="$PATH" HOME="${HOME:-}" GITHUB_OUTPUT="$work/output" PINGSTACK_TEST_BASE_URL="$base" \
    GITHUB_WORKFLOW="Nightly export" GITHUB_RUN_NUMBER=7 GITHUB_RUN_ID=99 GITHUB_REPOSITORY=acme/app \
    GITHUB_SERVER_URL=https://github.com INPUT_RETRIES=0 INPUT_TIMEOUT=5 "$@" "${PING_BASH:-bash}" ./ping.sh > "$work/stdout" 2>&1
  exit_code=$?
  out="$(grep '^http-status=' "$work/output" | tail -1)"
  stdout="$(cat "$work/stdout")"
}

check() {
  if eval "$2"; then
    echo "ok - $1"
  else
    echo "not ok - $1"
    echo "  requests: $(cat "$work/requests")"
    echo "  output: $stdout"
    failures=$((failures + 1))
  fi
}

start_server 200
run_action INPUT_PING_URL="$base/ping/tok123" INPUT_STATUS=success
check "success posts to the ping URL with a run summary" \
  '[ $exit_code -eq 0 ] && [ "$out" = "http-status=200" ] && grep -q "^POST /ping/tok123	Nightly export run #7 success: https://github.com/acme/app/actions/runs/99$" "$work/requests"'

run_action INPUT_PING_URL="$base/ping/tok123" INPUT_STATUS=failure
check "failure posts to the fail URL" 'grep -q "^POST /ping/tok123/fail	Nightly export run #7 failure" "$work/requests"'

: > "$work/requests"
run_action INPUT_PING_URL="$base/ping/tok123" INPUT_STATUS=success INPUT_VALUE=42.5 INPUT_MESSAGE="@/etc/passwd"
check "value goes in the query and a message starting with @ is sent as text" \
  'grep -q "^POST /ping/tok123?value=42.5	@/etc/passwd$" "$work/requests"'

for status in cancelled skipped; do
  : > "$work/requests"
  run_action INPUT_PING_URL="$base/ping/tok123" INPUT_STATUS=$status
  check "$status sends nothing" '[ $exit_code -eq 0 ] && [ ! -s "$work/requests" ] && [ "$out" = "http-status=" ]'
done

start_server 503,503,200
run_action INPUT_PING_URL="$base/ping/tok123" INPUT_RETRIES=3
check "retries a 503 until it's accepted" '[ "$out" = "http-status=200" ] && [ "$(wc -l < "$work/requests")" -eq 3 ]'

start_server 404
run_action INPUT_PING_URL="$base/ping/tok123" INPUT_RETRIES=3
check "doesn't retry a 404 and only warns" \
  '[ $exit_code -eq 0 ] && [ "$(wc -l < "$work/requests")" -eq 1 ] && echo "$stdout" | grep -q "^::warning title=Pingstack::Pingstack answered 404"'

run_action INPUT_PING_URL="$base/ping/tok123" INPUT_FAIL_ON_ERROR=true
check "fail-on-error fails the step" '[ $exit_code -eq 1 ] && echo "$stdout" | grep -q "^::error"'

: > "$work/requests"
for bad in "https://example.com/ping/tok123" "http://app.pingstack.io/ping/tok123" "https://pingstack.io.example.com/ping/x" ""; do
  run_action INPUT_PING_URL="$bad" INPUT_FAIL_ON_ERROR=true
  check "refuses ping-url '$bad'" '[ $exit_code -eq 1 ] && [ ! -s "$work/requests" ]'
done

run_action INPUT_PING_URL="$base/ping/tok123" INPUT_VALUE=lots INPUT_FAIL_ON_ERROR=true
check "refuses a value that isn't a number" '[ $exit_code -eq 1 ] && [ ! -s "$work/requests" ]'

run_action INPUT_PING_URL="$base/ping/tok123"
check "masks the ping URL and never prints it otherwise" \
  '[ "$(echo "$stdout" | grep -c "tok123")" -eq 1 ] && echo "$stdout" | grep -q "^::add-mask::"'

kill "$server_pid" 2>/dev/null; wait "$server_pid" 2>/dev/null; server_pid=""
run_action INPUT_PING_URL="$base/ping/tok123" INPUT_RETRIES=1 INPUT_TIMEOUT=2
check "reports an unreachable server as a warning" \
  '[ $exit_code -eq 0 ] && echo "$stdout" | grep -q "couldn.t reach Pingstack (curl exit 7) after 2 tries"'

[ "$failures" -eq 0 ] && echo "All tests passed." || { echo "$failures failed."; exit 1; }
