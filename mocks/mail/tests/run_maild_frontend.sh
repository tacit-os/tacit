#!/bin/sh
set -eu
mail_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="${1:-$mail_dir/frontend/mac-preview/build-local}"
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
export TACIT_MAIL_TEST_CONTRACT="$mail_dir/backend/internal/backend/testdata/list-contract.json"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
for phase in create send read contract; do
    data_dir="$test_dir/data"
    test_input="$mail_dir/tests/integration"
    if [ "$phase" = contract ]; then
        data_dir="$test_dir/contract-data"
        test_input="$mail_dir/tests/contracts"
    fi
    "$test_dir/maild" --seed --data-dir "$data_dir" --socket "$TACIT_MAIL_SOCKET" &
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
    python3 - "$data_dir/mail.sqlite" "$TACIT_MAIL_TEST_CONTRACT" "$phase" <<'PYFIXTURE'
import json, sqlite3, sys
fixture = json.load(open(sys.argv[2]))
with sqlite3.connect(sys.argv[1]) as db:
    if sys.argv[3] == "contract":
        for account in fixture["accounts"]:
            db.execute("INSERT OR IGNORE INTO accounts VALUES(?,?,?,?)", tuple(account[key] for key in ("id", "name", "email", "provider")))
        for message in fixture["messages"]:
            db.execute("INSERT OR IGNORE INTO messages(id,account_id,remote_id,conversation_id,mailbox,date,payload,search_text) VALUES(?,?,?,?,?,?,?,?)", (message["id"], message["account_id"], message["remote_id"], message["conversation_id"], message["mailbox"], message["date"], json.dumps(message).encode(), message["subject"] + " " + message["body_text"]))
            if not db.execute("SELECT 1 FROM search WHERE message_id=?", (message["id"],)).fetchone():
                db.execute("INSERT INTO search(message_id,content) VALUES(?,?)", (message["id"], message["subject"] + " " + message["body_text"]))
    if sys.argv[3] == "contract":
        db.execute("INSERT INTO accounts VALUES(?,?,?,?)", ("category-transport", "Category fixture", "category@example.test", "Gmail"))
        for name, labels in (("promotion", ["INBOX", "CATEGORY_PROMOTIONS"]), ("primary", ["INBOX"])):
            message = dict(id="category-transport-" + name, account_id="category-transport", remote_id="gmail:" + name,
                           conversation_id="category-transport-" + name, mailbox="Inbox", date="2026-01-01T12:00:00Z",
                           subject="Category transport " + name, body_text="Local category fixture", gmail_labels=labels)
            db.execute("INSERT INTO messages(id,account_id,remote_id,conversation_id,mailbox,date,payload,search_text) VALUES(?,?,?,?,?,?,?,?)", (message["id"], message["account_id"], message["remote_id"], message["conversation_id"], message["mailbox"], message["date"], json.dumps(message).encode(), message["subject"]))
    if sys.argv[3] == "contract":
        db.execute("INSERT INTO accounts VALUES(?,?,?,?)", ("category-pages", "Category pages", "pages@example.test", "Gmail"))
        for label in ("CATEGORY_PERSONAL", "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES"):
            for index in range(105):
                message = dict(id=label + "-" + str(index), account_id="category-pages", remote_id="gmail:" + label + str(index),
                               conversation_id=label + "-" + str(index), mailbox="Inbox", date="2026-01-01T12:00:00Z",
                               subject="Category pagination", body_text="Local pagination fixture", gmail_labels=["INBOX", label])
                db.execute("INSERT INTO messages(id,account_id,remote_id,conversation_id,mailbox,date,payload,search_text) VALUES(?,?,?,?,?,?,?,?)", (message["id"], message["account_id"], message["remote_id"], message["conversation_id"], message["mailbox"], message["date"], json.dumps(message).encode(), message["subject"]))
    digest = db.execute("SELECT digest FROM attachments WHERE id=?", ("seed-rich-text-gif",)).fetchone()[0]
    message = json.loads(db.execute("SELECT payload FROM messages WHERE id='seed-rich-text'").fetchone()[0])
    html = message["body_html"]
    if 'proxy-cached' not in html:
        html += '<img id="proxy-cached" src="https://images.example.invalid/cached.gif?q=a%20b&amp;size=2">'
        html += '<img id="proxy-missing" src="https://images.example.invalid/missing.gif">'
        message["body_html"] = html
        db.execute("UPDATE messages SET payload=? WHERE id='seed-rich-text'", (json.dumps(message).encode(),))
    db.execute("INSERT OR IGNORE INTO remote_images VALUES(?,?,?,?)", ("seed-rich-text", "https://images.example.invalid/cached.gif?q=a%20b&size=2", digest, "image/gif"))
PYFIXTURE
    TACIT_MAIL_TEST_PHASE="$phase" "$build_dir/TacitMailIntegrationTest" \
        -input "$test_input" -import "$build_dir/qml"
    stop_daemon
done
