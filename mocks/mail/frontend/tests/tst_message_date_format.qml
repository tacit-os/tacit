import QtQuick
import QtTest
import ".." as Mail

Item {
    width: 800; height: 200
    QtObject {
        id: controller
        property var ui: ({selected: "", draftId: "", view: "read"})
        property int signedInAccountCount: 1
        function agentDraft(id) { return null; }
        function highlight(text) { return text; }
    }
    Mail.MailMessagePreview {
        id: preview
        width: parent.width
        controller: controller
        modelData: ({id: "date", from: "Sender", subject: "Subject", unread: false,
            time: "Not sent", files: []})
    }
    TestCase {
        name: "MessageDateFormat"
        when: windowShown
        function test_formats_data() {
            return [
                {tag: "today-de", locale: "de_DE", date: new Date(2026, 10, 23, 8, 5), expected: "08:05"},
                {tag: "today-us", locale: "en_US", date: new Date(2026, 10, 23, 8, 5), expected: "8:05\u202fAM"},
                {tag: "this-year", locale: "de_DE", date: new Date(2026, 10, 22), expected: "22 Nov"},
                {tag: "this-year-us", locale: "en_US", date: new Date(2026, 0, 2), expected: "2 Jan"},
                {tag: "older-de", locale: "de_DE", date: new Date(2025, 10, 23), expected: "23.11.25"},
                {tag: "older-us", locale: "en_US", date: new Date(2025, 10, 23), expected: "11/23/25"},
                {tag: "older-gb", locale: "en_GB", date: new Date(2025, 10, 23), expected: "23/11/25"}
            ];
        }
        function test_formats(row) {
            compare(preview.dateLabel(row.date.getTime(), new Date(2026, 10, 23, 12), Qt.locale(row.locale)), row.expected);
        }
        function test_yearBoundaryAndFallback() {
            compare(preview.dateLabel(new Date(2025, 11, 31).getTime(), new Date(2026, 0, 1), Qt.locale("de_DE")), "31.12.25");
            compare(preview.dateLabel(undefined), "Not sent");
            compare(preview.dateLabel(NaN), "Not sent");
        }
    }
}
