#!/bin/sh
set -eu

preview_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build_dir="$preview_dir/build-local"
qt_prefix=${QT_ROOT:-}
if [ -z "$qt_prefix" ] && command -v qtpaths >/dev/null 2>&1; then
    qt_prefix=$(qtpaths --query QT_INSTALL_PREFIX)
fi
if [ -n "$qt_prefix" ]; then
    cmake -S "$preview_dir" -B "$build_dir" "-DCMAKE_PREFIX_PATH=$qt_prefix"
else
    cmake -S "$preview_dir" -B "$build_dir"
fi
cmake --build "$build_dir" --parallel
preview="$build_dir/TacitMailMacPreview.app/Contents/MacOS/TacitMailMacPreview"
if [ -n "${TACIT_MAIL_SOCKET:-}" ]; then
    exec "$preview" "$@"
fi

socket="${XDG_RUNTIME_DIR:-$HOME/Library/Caches}/tacit-mail-mock/mail.sock"
backend_ready() {
    curl -q --noproxy '*' -fs --max-time 1 --unix-socket "$socket" \
        http://localhost/v1/health >/dev/null
}

if backend_ready; then
    TACIT_MAIL_SOCKET="$socket" exec "$preview" "$@"
fi

(cd "$preview_dir/../backend" && go build -o "$build_dir/maild" ./cmd/maild)
"$build_dir/maild" --seed --socket "$socket" &
maild_pid=$!
trap 'kill "$maild_pid" 2>/dev/null || true; wait "$maild_pid" || true' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

attempt=0
until backend_ready; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 50 ] || ! kill -0 "$maild_pid" 2>/dev/null; then
        echo "Tacit Mail: maild did not become ready at $socket" >&2
        exit 1
    fi
    sleep .1
done
TACIT_MAIL_SOCKET="$socket" "$preview" "$@"
