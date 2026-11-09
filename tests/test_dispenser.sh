#!/usr/bin/env bash
# The token dispenser's account list is the only source: the account on show is
# picked by name, its usageData is the usage body, and a paused, logged-out or
# missing account is said instead of shown.
source "$(dirname "$0")/lib.sh"

export CLAUDEBAR_TEST_NET_QUICK_BUDGET=0
export CLAUDEBAR_TEST_NET_LONG_BUDGET=0

OE='{"five_hour":null,"seven_day":{"utilization":88,"resets_at":"2100-01-01T00:00:00Z"}}'
YB='{"five_hour":{"utilization":23,"resets_at":"2100-01-01T00:00:00Z"},"seven_day":{"utilization":18,"resets_at":"2100-01-01T00:00:00Z"}}'

STUB='#!/usr/bin/env bash
cfg=$(cat)
url=""; for a in "$@"; do [[ "$a" == http*://* ]] && url="$a"; done
printf "%s\n%s\n" "$url" "$cfg" > "$HOME/.curl_seen"
cat "$HOME/.list"; printf "\n200"
'

_run_d() {  # <account-list-json> [args...]
    local list="$1"; shift
    DHOME="$(mktemp -d)" || { echo "HARNESS SETUP FAILED" >&2; exit 1; }
    mkdir -p "$DHOME/bin" "$DHOME/.cache/claudebar/oe" "$DHOME/.cache/claudebar/yb"
    printf '%s' "$STUB" > "$DHOME/bin/curl" && chmod +x "$DHOME/bin/curl"
    printf '%s' "$list" > "$DHOME/.list"
    OUT=$(run_pinned "$DHOME" "$SCRIPT" --json --refresh "$@"); RC=$?
}

both() {  # [oe-extra-fields-json]
    jq -nc --argjson oe "$OE" --argjson yb "$YB" --argjson x "${1:-{\}}" '[
        {name:"yotabyte-chatgpt", provider:"codex", usageData:{}},
        ({name:"claude-ecommerce", provider:"anthropic", priority:25, paused:false, requiresReauth:false, usageData:$oe} + $x),
        {name:"claude-yotabyte", provider:"anthropic", priority:0, paused:false, requiresReauth:false, usageData:$yb}]'
}

echo "== oe reads claude-ecommerce, yb reads claude-yotabyte"
_run_d "$(both)" --account oe
assert_exit0 "oe: exit 0"
assert_jq_value "oe: weekly from its usageData" '.windows[] | select(.id=="weekly") | .used_pct' '88'
assert_jq_value "oe: no error" '.error' 'null'
seen=$(cat "$DHOME/.curl_seen"); rm -rf "$DHOME"
grep -q '^http://100.64.0.8:8793/api/accounts$' <<< "$seen" && _ok "asks the dispenser's account list" || _no "asks the dispenser's account list" "$seen"
grep -q '^header = "x-api-key: test-key"$' <<< "$seen" && _ok "sends the key as x-api-key" || _no "sends the key as x-api-key" "$seen"
_run_d "$(both)" --account yb
assert_jq_value "yb: session from its usageData" '.windows[] | select(.id=="session") | .used_pct' '23'
rm -rf "$DHOME"

echo "== an account the dispenser cannot serve is said"
_run_d "$(both '{"paused":true}')" --account oe
assert_exit0 "paused: exit 0"
assert_jq_value "paused: says so" '.error.message' 'OE: paused in the token dispenser.'
rm -rf "$DHOME"
_run_d "$(both '{"requiresReauth":true}')" --account oe
assert_jq_value "reauth: says so" '.error.message | startswith("OE: needs logging in again.")' 'true'
rm -rf "$DHOME"
_run_d '[]' --account yb
assert_jq_value "missing: says so" '.error.message' 'YB: claude-yotabyte is not in the token dispenser.'
rm -rf "$DHOME"

finish
