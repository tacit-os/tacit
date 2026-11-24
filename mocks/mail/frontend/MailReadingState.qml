import QtQuick
import QtCore
import "mail-store.js" as Store

QtObject {
    id: reader

    required property var data
    property var client: null
    property var visibleRows: []
    property var messageExpansion: ({})
    property var threadScrollPositions: new Map()
    property var quotedHistoryExpansion: ({})
    property var approvedRemoteImages: ({})
    // The workspace owns the visual cache; reading-state invalidation controls its contents.
    property var htmlCache: null
    onClientChanged: approvedRemoteImages = ({})

    property Settings preferences: Settings {
        location: "file://" + StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)
            + "/tacit/mail-reading.ini"
        property string bodyInk: "meta"
        property string htmlBackground: "none"
    }
    readonly property string bodyInk: ["main", "sec", "meta", "faint"].includes(preferences.bodyInk)
        ? preferences.bodyInk : "meta"
    readonly property string htmlBackground: ["none", "primary", "overlay", "auto"].includes(preferences.htmlBackground)
        ? preferences.htmlBackground : "none"

    function setQuotedHistoryExpanded(messageId, expanded) {
        if (!messageId || !!quotedHistoryExpansion[messageId] === expanded) return;
        const updated = Object.assign({}, quotedHistoryExpansion);
        if (expanded) updated[messageId] = true;
        else delete updated[messageId];
        quotedHistoryExpansion = updated;
    }

    function setPreference(key, value) {
        if (key === "bodyInk" && ["main", "sec", "meta", "faint"].includes(value))
            preferences.bodyInk = value;
        if (key === "htmlBackground" && ["none", "primary", "overlay", "auto"].includes(value))
            preferences.htmlBackground = value;
    }
    function allowRemoteImages(messageId) {
        if (client) client.allowMessageImages(messageId);
        else approvedRemoteImages = Object.assign({}, approvedRemoteImages, {[messageId]: true});
    }
    function invalidate(ids) {
        htmlCache?.invalidate(ids);
        threadQuery.resetPrefetch(false);
    }

    readonly property var selectedRow: Store.current(data)
    property MailThreadQuery threadQuery: MailThreadQuery {
        client: reader.client
        prefetchRows: reader.visibleRows
        account: reader.selectedRow?.backendAccount ?? ""
        conversation: reader.selectedRow?.backendConversation ?? ""
    }
    readonly property var threadMessages: Store.mailboxRows(data.accounts, threadQuery.messages)
    readonly property var selected: {
        if (!selectedRow)
            return null;
        const current = threadMessages.find(message => message.id === selectedRow.id);
        if (!current)
            return data.ui.view === "read" && threadQuery.loading && !threadQuery.messages.length ? null : selectedRow;
        return Object.assign({}, selectedRow, {
            body: current.body,
            bodyHtml: current.bodyHtml,
            bodyParts: current.bodyParts,
            remoteImages: current.remoteImages,
            remoteImagesAllowed: current.remoteImagesAllowed,
            to: current.to || selectedRow.to,
            cc: current.cc || selectedRow.cc,
            files: current.files,
            history: threadMessages.filter(message => message.id !== current.id
                && !(message.folder === "Trash" && message.trashOrigin === "Drafts")).map(message =>
                Object.assign({}, message, {date: [message.day, message.time].join(" "), expanded: false}))
        });
    }
    readonly property bool canReplyAll: Store.canReplyAll(selected, data.accounts)
}
