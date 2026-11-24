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

backend_dir="$preview_dir/../../backend"
# Keep the account-only mailbox separate from the older seeded and .env stores.
socket="${XDG_RUNTIME_DIR:-$HOME/Library/Caches}/tacit-mail-accounts/mail.sock"
data_dir="$HOME/Library/Application Support/tacit/mail-accounts"
backend_ready() {
    curl -q --noproxy '*' -fs --max-time 1 --unix-socket "$socket" \
        http://localhost/v1/health >/dev/null
}

if backend_ready; then
    TACIT_MAIL_SOCKET="$socket" exec "$preview" "$@"
fi

(cd "$backend_dir" && go build -o "$build_dir/maild" ./cmd/maild)
(
    unset TACIT_MAIL_EMAIL TACIT_MAIL_IMAP TACIT_MAIL_SMTP TACIT_MAIL_USERNAME TACIT_MAIL_PASSWORD
    if [ -f "$backend_dir/.env" ]; then
        while IFS= read -r setting || [ -n "$setting" ]; do
            case "$setting" in
                TACIT_GOOGLE_CREDENTIALS=*|TACIT_GOOGLE_CLIENT_ID=*|TACIT_GOOGLE_CLIENT_SECRET=*)
                    key=${setting%%=*}
                    value=${setting#*=}
                    case "$value" in
                        \"*\") value=${value#\"}; value=${value%\"} ;;
                        \'*\') value=${value#\'}; value=${value%\'} ;;
                    esac
                    case "$key" in
                        TACIT_GOOGLE_CREDENTIALS)
                            case "$value" in
                                ""|/*) ;;
                                *) value="$backend_dir/$value" ;;
                            esac
                            : "${TACIT_GOOGLE_CREDENTIALS=$value}"
                            ;;
                        TACIT_GOOGLE_CLIENT_ID) : "${TACIT_GOOGLE_CLIENT_ID=$value}" ;;
                        TACIT_GOOGLE_CLIENT_SECRET) : "${TACIT_GOOGLE_CLIENT_SECRET=$value}" ;;
                    esac
                    export "$key"
                    ;;
            esac
        done < "$backend_dir/.env"
    fi
    exec "$build_dir/maild" --socket "$socket" --data-dir "$data_dir"
) &
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
