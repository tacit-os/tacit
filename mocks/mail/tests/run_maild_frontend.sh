#!/bin/sh
set -eu
mail_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="${1:-$mail_dir/mac-preview/build-local}"
test_dir=$(mktemp -d /tmp/tacit-mail-ui.XXXXXX)
daemon_pid=
stop_daemon() {
    if [ -n "$daemon_pid" ]; then
        kill "$daemon_pid" 2>/dev/null || true
        wait "$daemon_pid" || true
        daemon_pid=
    fi
}
cleanup() {
    stop_daemon
    rm -rf "$test_dir"
}
trap cleanup EXIT
(cd "$mail_dir/backend" && go build -o "$test_dir/maild" ./cmd/maild)
export TACIT_MAIL_SOCKET="$test_dir/mail.sock"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
for phase in create send read; do
    "$test_dir/maild" --seed --data-dir "$test_dir/data" --socket "$TACIT_MAIL_SOCKET" &
    daemon_pid=$!
    ready=0
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if curl -fs --unix-socket "$TACIT_MAIL_SOCKET" http://localhost/v1/health >/dev/null; then
            ready=1
            break
        fi
        sleep .2
    done
    test "$ready" = 1
    TACIT_MAIL_TEST_PHASE="$phase" "$build_dir/TacitMailIntegrationTest" \
        -input "$mail_dir/tests/integration" -import "$build_dir/qml"
    stop_daemon
done
