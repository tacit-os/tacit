// Tacit's login screen while it signs in (session/sddm/tacit/Main.qml): the theme's own file under qmltestrunner
// offscreen, with stand-ins for what SDDM gives a theme (sddm, config, userModel, sessionModel), a password typed into
// its field and Enter pressed, as a person does. Nothing changed on screen for the seconds PAM takes, and a second Enter
// signed in again while more keys went into the field.
import { logged, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the login screen while it signs in (session/sddm/tacit/Main.qml)");
const main = read("session/sddm/tacit/Main.qml");
const theme = main.slice(main.search(/^Rectangle \{/m));
const scene = `import QtQuick
import QtQuick.Controls
import QtTest
Item {
    width: 1920; height: 1080
    // SDDM's config map: onSurface is no name a QML property can have
    property var config: ({ surface: "#151312", surfaceContainerHigh: "#2c2928", onSurface: "#e8e1df", onSurfaceVariant: "#d3c3bd",
        primary: "#dfc0b2", error: "#ffb4ab", ground: "", symbols: "" })
    QtObject {
        id: sddm
        signal loginFailed()
        signal loginSucceeded()
        property var logins: []
        property bool canSuspend: true; property bool canReboot: true; property bool canPowerOff: true
        function login(user, password, session) { logins = logins.concat([[user, password, session]]) }
        function suspend() {} function reboot() {} function powerOff() {}
    }
    QtObject {
        id: userModel
        property int lastIndex: 0; property int count: 1
        function index(row, column) { return row }
        function data(i, role) { return role === Qt.UserRole + 1 ? "sam" : "Sam" }
    }
    QtObject {
        id: sessionModel
        property int lastIndex: 0
        function rowCount() { return 1 }
        function index(row, column) { return row }
        function data(i, role) { return "/usr/share/wayland-sessions/tacit.desktop" }
    }
${theme}
    TestCase {
        name: "login"; when: windowShown
        // the password field, wherever the theme keeps it
        function field(item) {
            for (let i = 0; i < item.children.length; i++) {
                const c = item.children[i];
                if (c.echoMode === TextInput.Password) return c;
                const f = field(c);
                if (f) return f;
            }
            return null;
        }
        function test_signing_in() {
            const out = {};
            const box = field(root);
            box.forceActiveFocus();
            keyClick(Qt.Key_H); keyClick(Qt.Key_U); keyClick(Qt.Key_N); keyClick(Qt.Key_T); keyClick(Qt.Key_E); keyClick(Qt.Key_R);
            out.typed = box.text;
            keyClick(Qt.Key_Return);
            out.while = { says: box.placeholderText, text: box.text, readOnly: box.readOnly, logins: sddm.logins };
            // a second Enter and more typing while PAM checks it
            keyClick(Qt.Key_Return); keyClick(Qt.Key_X);
            out.again = { logins: sddm.logins.length, text: box.text };
            sddm.loginFailed();
            out.failed = { says: box.placeholderText, readOnly: box.readOnly };
            keyClick(Qt.Key_A);
            out.after = { text: box.text, says: box.placeholderText };
            console.log("LOGIN " + JSON.stringify(out));
        }
    }
}
`;
try {
  const r = logged(runScene({ "tst_login.qml": scene, "DockedRect.qml": read("session/sddm/tacit/DockedRect.qml") }), "LOGIN");
  check("the password is typed into the field", r.typed === "hunter", `"${r.typed}"`);
  check("Enter signs in with it, once", JSON.stringify(r.while.logins) === JSON.stringify([["sam", "hunter", 0]]), JSON.stringify(r.while.logins));
  check('and the field says "Signing in…" while it does', r.while.says === "Signing in…" && r.while.text === "", `says "${r.while.says}", holds "${r.while.text}"`);
  check("a second Enter and more keys meanwhile go nowhere", r.again.logins === 1 && r.again.text === "" && r.while.readOnly === true,
    `${r.again.logins} logins, holds "${r.again.text}"`);
  check('a wrong password: "Incorrect password", and the field takes keys again', r.failed.says === "Incorrect password" && r.failed.readOnly === false
    && r.after.text === "a" && r.after.says === "Password", JSON.stringify([r.failed, r.after]));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
