// The Bluetooth passkey field holds only digits, the number the agent reads (modules/ii/bluetooth/BluetoothPairContent.qml):
// the field's own validator binding and validator run in a TextInput under Qt's qml tool offscreen, in English and German,
// with keys typed one at a time. What the field holds goes to quiet-btagent, whose g_ascii_strtoull stops at the first
// character that is not a digit (session/btagent/quiet-btagent.c).
import { readExpression } from "./lib/qml.mjs";
import { logged, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== typing a Bluetooth passkey (BluetoothPairContent.qml)");
const src = read("modules/ii/bluetooth/BluetoothPairContent.qml");
const binding = readExpression(src, src.indexOf("validator:") + "validator:".length).expr;
const validator = objectWith(src, "id: passkeyValidator");
const typed = ["123,456", "123.456", "+123", "1234567", "12ab34"];
const scene = `import QtQuick
Item {
    QtObject { id: root; property string kind: "passkey" }
    TextInput {
        id: field
        validator: ${binding}
        ${validator}
    }
    Component.onCompleted: {
        const out = {}
        for (const s of ${JSON.stringify(typed)}) {
            field.text = ""
            for (const c of s) field.insert(field.text.length, c)
            out[s] = field.text
        }
        console.log("FIELD " + JSON.stringify({ locale: Qt.locale().name, out }))
        Qt.quit()
    }
}
`;
// the number quiet-btagent sends: the digits up to the first other character (a leading + is skipped, as strtoull does)
const agentReads = text => +(/^\+?(\d*)/.exec(text)[1] || 0);
const meant = s => +(s.replace(/\D/g, "").slice(0, 6) || 0);

for (const lang of ["en_US.UTF-8", "de_DE.UTF-8"]) {
  try {
    const { locale, out } = logged(runScene({ "field.qml": scene }, { env: { LANG: lang, LC_ALL: lang } }), "FIELD");
    for (const s of typed) {
      check(`${locale}: typed "${s}", the field holds digits only and the agent reads ${meant(s)}`,
        /^\d{0,6}$/.test(out[s]) && agentReads(out[s]) === meant(s), `the field holds "${out[s]}", the agent reads ${agentReads(out[s])}`);
    }
  } catch (e) {
    check(`${lang}: the scene ran`, false, String(e.message ?? e));
  }
}
done();
