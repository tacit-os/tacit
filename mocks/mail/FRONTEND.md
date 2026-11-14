# Tacit Mail frontend

Tacit Mail loads mailbox, search, thread and saved draft data from local maild over its Unix socket. The workspace owns a UI session and the editor keeps a working copy. MailDraftSync writes changes after 400 ms or immediately after attachment changes and before sending.

## macOS preview

From `mocks/mail`, with Xcode Command Line Tools, CMake, Python 3, desktop Qt 6.8+ with Qt WebEngine, and a sibling `tacit-kit` checkout:

```sh
./mac-preview/run.sh
```

Pass `draft` to start in the draft view or `html` to open the sample newsletter. Set `QT_ROOT` if Qt is outside CMake's search path and `TACIT_KIT_DIR` if the Kit is elsewhere. For Qt Creator, open `mac-preview/CMakeLists.txt` with a desktop Qt kit.

The launcher builds the versioned host and stages the Kit and its fonts in the ignored `mac-preview/build-local/` directory. The staged copy gets the patch in `kit-style/` and 90% typography. The Mac host draws the Tacit window ground over native blur. Free areas can be used to drag the window.

Saving a mail QML or JavaScript file reloads the view in place and preserves the local mail model. A load error leaves the last working view open and is printed in the terminal. Restart with the launcher after changes to the native host or the staged Kit.

The **Preview** menu can simulate incoming mail, connectivity and sign-in, undo a send, or reset the session. **Preview → Palette** switches between Dusk, Moss and a Tacit `colors.json` file. Set `MAIL_PALETTE` to `dusk`, `moss` or the JSON file's absolute path to choose it at launch. A neighbouring `seethrough.json` can set the glass scale.

## Behaviour and boundaries

- The reader and message list share the window at wider sizes. At narrow widths they become separate views, with the mailbox menu providing access to folders, accounts and settings.
- Demo messages are seeded by maild. SQLite stores message content and attachment references. The daemon streams attachment bytes from its blob directory.
- Expanded messages with HTML use Qt WebEngine and an in-memory profile. If the inbox contains HTML mail, the app warms the engine once with an empty local document. Scripts, external resources, downloads and embedded navigation are blocked. Clicking an HTTP(S) link opens it in the default browser. Plain text remains the fallback if the HTML module or rendering is unavailable.
- Quickshell starts through `mail.qml` with the `Tacit.Mailbox` module on its QML import path. Set `TACIT_MAIL_SOCKET` to use a separate daemon.

The editor supports bold, italic, links and bulleted lists. Drafts and the local send queue keep both plain text and formatted HTML. Paste uses plain text to keep the editor's typography consistent.

For Quickshell development, build the three Qt modules and include their absolute QML paths. From this directory, with the same Qt installation used by Quickshell:

```sh
mail_build="$(mktemp -d)"
for module in mailbox-engine html-engine editor-engine; do
    cmake -S "$module" -B "$mail_build/$module"
    cmake --build "$mail_build/$module" --parallel
done
export QML_IMPORT_PATH="$mail_build/mailbox-engine/qml:$mail_build/html-engine/qml:$mail_build/editor-engine/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
```

Run the Tacit Quickshell entry point with this environment and `curl` on `PATH`. The Mac launcher builds all three modules and sets its own import path. Without the editor module, the composer remains usable in plain text.

## Checks

From `mocks/mail` with Node 18+ and Qt tools on PATH:

```sh
node tests/state.test.cjs
python3 mac-preview/prepare.py
for test in tst_frontend tst_responsive; do
    QT_QPA_PLATFORM=offscreen qmltestrunner -input "tests/$test.qml" -import mac-preview/build-local/qml || exit 1
done
```

Run the backend walkthrough with `sh tests/run_maild_frontend.sh` after building the Mac preview. It exercises the shared workspace with a real maild, saved replies, inline GIFs and PDF attachments across restarts.
