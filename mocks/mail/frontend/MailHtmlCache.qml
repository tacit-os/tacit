import QtQuick

Item {
    id: cache
    visible: false
    readonly property int capacity: 3
    property var slots: []
    property int clock: 0
    readonly property int count: slots.length

    Component {
        id: slotComponent
        Loader {
            id: slot
            property string messageKey: ""
            property var documentData: ({})
            property var owner: null
            property int used: 0
            property bool discard: false
            asynchronous: true
            visible: owner !== null
            width: 1
            Connections {
                target: slot.owner
                function onWidthChanged() { slot.width = slot.owner.width; }
            }
            sourceComponent: MailHtmlView {
                html: slot.documentData.html ?? ""
                searchTerm: slot.documentData.searchTerm ?? ""
                messageId: slot.documentData.messageId ?? ""
                mailboxClient: slot.documentData.client ?? null
                attachments: slot.documentData.attachments ?? []
                remoteImageSources: slot.documentData.sources ?? []
                remoteImages: slot.documentData.allowed ?? false
                backgroundMode: slot.documentData.background ?? "none"
                quotedHistoryExpanded: slot.documentData.historyExpanded ?? false
                onExternalLinkRequested: link => Qt.openUrlExternally(link)
            }
        }
    }

    function acquire(key, data, owner) {
        let slot = slots.find(entry => entry.messageKey === key && !entry.discard && (!entry.owner || entry.owner === owner));
        if (!slot) {
            slot = slotComponent.createObject(cache, {messageKey: key, documentData: data});
            slots = slots.concat([slot]);
        } else {
            slot.documentData = data;
        }
        slot.used = ++clock;
        slot.width = owner.width;
        slot.owner = owner;
        slot.parent = owner;
        trim();
        return slot;
    }

    function release(slot, owner) {
        if (!slot || slot.owner !== owner) return;
        slot.owner = null;
        slot.parent = cache;
        trim();
    }

    function trim() {
        const idle = slots.filter(slot => !slot.owner).sort((a, b) => a.used - b.used);
        const remove = new Set(idle.filter(slot => slot.discard));
        for (const slot of idle) {
            if (slots.length - remove.size <= capacity) break;
            remove.add(slot);
        }
        if (!remove.size) return;
        slots = slots.filter(slot => !remove.has(slot));
        for (const slot of remove) slot.destroy();
    }

    // Deleted/account-removed content must not survive in an idle rendered view.
    function invalidate(ids) {
        for (const slot of slots) {
            if (!ids || ids.includes(slot.messageKey)) slot.discard = true;
        }
        trim();
    }
}
