#!/usr/bin/env bash
# Reports a workflow run to a Pingstack heartbeat check. Written for bash 3.2
# (macOS runners) with only curl, so it runs on every GitHub-hosted runner.
# The ping URL is a credential: it's masked and never printed.
set -u

url="${INPUT_PING_URL:-}"
status="$(printf '%s' "${INPUT_STATUS:-success}" | tr '[:upper:]' '[:lower:]')"
value="${INPUT_VALUE:-}"
message="${INPUT_MESSAGE:-}"
retries="${INPUT_RETRIES:-3}"
timeout="${INPUT_TIMEOUT:-10}"
fail_on_error="$(printf '%s' "${INPUT_FAIL_ON_ERROR:-false}" | tr '[:upper:]' '[:lower:]')"
output="${GITHUB_OUTPUT:-/dev/null}"

[ -n "$url" ] && echo "::add-mask::$url"
echo "http-status=" >> "$output"

give_up() {
  if [ "$fail_on_error" = "true" ]; then
    echo "::error title=Pingstack::$1"
    exit 1
  fi
  echo "::warning title=Pingstack::$1"
  exit 0
}

case "$retries" in ''|*[!0-9]*) give_up "retries must be a whole number." ;; esac
case "$timeout" in ''|*[!0-9]*) give_up "timeout must be a whole number of seconds." ;; esac
if [ -n "$value" ] && ! printf '%s' "$value" | grep -Eq '^-?[0-9]+(\.[0-9]+)?$'; then
  give_up "value must be a number."
fi

# Only https URLs on pingstack.io, so a misconfigured secret can't send run
# details anywhere else. PINGSTACK_TEST_BASE_URL is for this repo's own tests.
if [ -z "$url" ]; then
  give_up "ping-url is empty. Set it from a repository secret, for example \${{ secrets.PINGSTACK_PING_URL }}."
fi
host="$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://([^/:?]+).*#\1#' | tr '[:upper:]' '[:lower:]')"
if [ -n "${PINGSTACK_TEST_BASE_URL:-}" ] && [ "${url#"$PINGSTACK_TEST_BASE_URL"}" != "$url" ]; then
  :
elif [ "${url#https://}" = "$url" ] || { [ "$host" != "pingstack.io" ] && [ "${host%.pingstack.io}" = "$host" ]; }; then
  give_up "ping-url must be a Pingstack ping URL (https://app.pingstack.io/ping/...)."
fi

case "$status" in
  success) endpoint="$url" ;;
  failure) endpoint="${url%%\?*}"; endpoint="${endpoint%/}/fail" ;;
  cancelled|skipped)
    echo "Job was $status; nothing sent to Pingstack."
    exit 0
    ;;
  *) give_up "status must be success, failure, cancelled or skipped (got \"$status\")." ;;
esac

# The value is a plain number (checked above), so it needs no encoding.
if [ -n "$value" ]; then
  case "$endpoint" in *\?*) endpoint="$endpoint&value=$value" ;; *) endpoint="$endpoint?value=$value" ;; esac
fi

if [ -z "$message" ]; then
  run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
  message="${GITHUB_WORKFLOW:-Workflow} run #${GITHUB_RUN_NUMBER:-?} $status: $run_url"
fi

attempt=0
while :; do
  # The body goes through stdin so a message starting with "@" isn't read as a file name.
  code="$(printf '%s' "$message" | curl --silent --output /dev/null --write-out '%{http_code}' --max-time "$timeout" \
    --request POST --header 'Content-Type: text/plain; charset=utf-8' --data-binary @- \
    "$endpoint" 2>/dev/null)"
  curl_exit=$?
  [ "$curl_exit" -ne 0 ] && code=""

  case "$code" in
    2??)
      echo "http-status=$code" >> "$output"
      echo "Reported $status to Pingstack."
      exit 0
      ;;
    ""|429|5??) ;;
    *)
      echo "http-status=$code" >> "$output"
      give_up "Pingstack answered $code. Check that ping-url is the check's current ping URL."
      ;;
  esac

  if [ "$attempt" -ge "$retries" ]; then
    echo "http-status=$code" >> "$output"
    if [ -z "$code" ]; then
      give_up "couldn't reach Pingstack (curl exit $curl_exit) after $((attempt + 1)) tries."
    fi
    give_up "Pingstack answered $code after $((attempt + 1)) tries."
  fi
  attempt=$((attempt + 1))
  sleep "$((1 << (attempt - 1)))"
done
