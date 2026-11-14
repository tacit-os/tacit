"""Run with python3 tests/test_maild_integration.py from the mail directory."""
import json
from pathlib import Path
import subprocess
import tempfile
import time
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="maild-test-") as directory:
        root = Path(directory)
        binary = root / "maild"
        socket = root / "mail.sock"
        subprocess.run(["go", "build", "-o", binary, "./cmd/maild"],
                       cwd=ROOT / "backend", check=True)

        def request(route, payload=None, content_type="application/json", method=None):
            args = ["curl", "-fsS", "--max-time", "5", "--unix-socket", socket]
            if method:
                args += ["-X", method]
            if payload is not None:
                args += ["-H", f"Content-Type: {content_type}", "--data-binary", "@-"]
                if not isinstance(payload, bytes):
                    payload = json.dumps(payload).encode()
            return subprocess.check_output(args + ["http://localhost/v1/" + route], input=payload)

        def start():
            process = subprocess.Popen([binary, "--seed", "--data-dir", root / "data",
                                        "--socket", socket, "--worker-interval=0"])
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and process.poll() is None:
                if socket.exists():
                    try:
                        request("health")
                        return process
                    except subprocess.CalledProcessError:
                        pass
                time.sleep(0.05)
            stop(process)
            raise RuntimeError("maild did not become ready")

        def stop(process):
            process.terminate()
            process.wait(timeout=10)

        gif = (ROOT / "fixtures/funny-cat-52.gif").read_bytes()
        pdf = (ROOT / "fixtures/review-summary.pdf").read_bytes()
        process = start()
        try:
            files = []
            for name, media, data in [
                ("cat.gif", "image/gif", gif),
                ("review.pdf", "application/pdf", pdf),
            ]:
                route = "accounts/work/attachments?" + urlencode({"filename": name})
                files.append(json.loads(request(route, data, media))["id"])
            html = f'<p>Before</p><img src="cid:{files[0]}"><p>lol</p>'
            draft = json.loads(request("drafts", {
                "account_id": "work", "conversation_id": "review",
                "to": [{"email": "mara@example.com"}], "subject": "GIF integration check",
                "body_text": "Before\nlol", "body_html": html,
                "attachments": [{"id": value} for value in files],
            }))
        finally:
            stop(process)

        def check_message(message):
            assert message["body_text"] == "Before\nlol"
            assert message["body_html"] == html
            assert {file["id"] for file in message["attachments"]} == set(files)
            for file, original in zip(files, (gif, pdf)):
                assert request(f'messages/{message["id"]}/attachments/{file}') == original

        process = start()
        try:
            saved = json.loads(request(f'messages/{draft["id"]}'))
            assert saved["mailbox"] == "Drafts"
            check_message(saved)
            request("send", {"draft_id": draft["id"], "idempotency_key": "gif-test"})
            request("mock/flush", {})
        finally:
            stop(process)

        process = start()
        try:
            sent = json.loads(request("messages?mailbox=Sent"))["messages"]
            message = next(item for item in sent if item["subject"] == draft["subject"])
            check_message(message)
            hits = json.loads(request("messages?mailbox=Sent&q=lol"))["messages"]
            assert any(item["id"] == message["id"] for item in hits)
        finally:
            stop(process)


if __name__ == "__main__":
    main()
