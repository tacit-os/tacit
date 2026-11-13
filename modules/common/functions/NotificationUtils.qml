pragma Singleton
import Quickshell
import qs.services

Singleton {
    id: root
    /**
     * @param { string } summary 
     * @returns { string }
     */
    function findSuitableMaterialSymbol(summary = "") {
        const defaultType = 'chat';
        if (summary.length === 0) return defaultType;

        const keywordsToTypes = {
            'reboot': 'restart_alt',
            'record': 'screen_record',
            'battery': 'power',
            'power': 'power',
            'screenshot': 'screenshot_monitor',
            'welcome': 'waving_hand',
            'time': 'schedule',
            'installed': 'download',
            'configuration reloaded': 'reset_wrench',
            'unable': 'question_mark',
            "couldn't": 'question_mark',
            'config': 'reset_wrench',
            'update': 'update',
            'ai response': 'neurology',
            'control': 'settings',
            'upsca': 'compare',
            'music': 'queue_music',
            'install': 'deployed_code_update',
            'input': 'keyboard_alt',
            'preedit': 'keyboard_alt',
            'startswith:file': 'folder_copy', // Declarative startsWith check
        };

        const lowerSummary = summary.toLowerCase();

        for (const [keyword, type] of Object.entries(keywordsToTypes)) {
            if (keyword.startsWith('startswith:')) {
                const startsWithKeyword = keyword.replace('startswith:', '');
                if (lowerSummary.startsWith(startsWithKeyword)) {
                    return type;
                }
            } else if (lowerSummary.includes(keyword)) {
                return type;
            }
        }

        return defaultType;
    }

    /**
     * @param { number | string | Date } timestamp 
     * @returns { string }
     */
    function getFriendlyNotifTimeString(timestamp) {
        if (!timestamp) return '';
        const messageTime = new Date(timestamp);
        const now = new Date();
        const diffMs = now.getTime() - messageTime.getTime();

        // Less than 1 minute
        if (diffMs < 60000)
            return Translation.tr('Now');

        // Same day - show relative time
        if (messageTime.toDateString() === now.toDateString()) {
            const diffMinutes = Math.floor(diffMs / 60000);
            const diffHours = Math.floor(diffMs / 3600000);

            if (diffHours > 0) {
                return `${diffHours}h`;
            } else {
                return `${diffMinutes}m`;
            }
        }

        // Yesterday
        if (messageTime.toDateString() === new Date(now.getTime() - 86400000).toDateString())
            return Translation.tr('Yesterday');

        // Older dates
        return Qt.formatDateTime(messageTime, "MMMM dd");
    }

    function processNotificationBody(body, appName) {
        body = body ?? ""   // undefined while a removed notification's delegate is torn down
        let processedBody = body
        
        // Clean Chromium-based browsers notifications - remove first line
        if (appName) {
            const lowerApp = appName.toLowerCase()
            const chromiumBrowsers = [
                "brave", "chrome", "chromium", "vivaldi", "opera", "microsoft edge"
            ]

            if (chromiumBrowsers.some(name => lowerApp.includes(name))) {
                const lines = body.split('\n\n')

                if (lines.length > 1 && lines[0].startsWith('<a')) {
                    processedBody = lines.slice(1).join('\n\n')
                }
            }
        }

        processedBody = processedBody.replace(/<img/gi, '\n\n<img');

        return root.tidyBody(processedBody)
    }

    // What an app sends is not always meant to be read in a notification: the phone forwards Gmail with the whole
    // email (up to ~1000 characters), each line twice, and the footer ("Was this email useful? Yes No ... Unsubscribe
    // ... 651 Brannan Street"). Kept: the lines a person wrote, once each, up to the first footer line.
    readonly property var footerLine: /^(see more|read more|view (this )?(email|message|it) in( your)? browser|was this (email|message) (useful|helpful)\??|based on your activity|unsubscribe\b|manage (your )?(email|notification)s?|help cent(er|re)|privacy policy|terms (of (service|use)|& conditions)|you('re| are) receiving this|this (email|message) was sent to|©|copyright )/i
    function tidyBody(body) {
        const out = [], seen = {};
        for (let line of String(body ?? "").replace(/\r\n?/g, "\n").split("\n")) {
            // and the invisible filler mail puts after its preview text (U+034F, braille blanks, zero-width spaces)
            line = line.replace(/\u00a0|&nbsp;/g, " ").replace(/[\u034f\u2800\u200b\u200c\u2060\ufeff\u00ad]/g, "").replace(/[ \t]+/g, " ").trim();
            if (!line.length)
                continue;
            if (root.footerLine.test(line.replace(/<[^>]+>/g, "")))
                break;
            // "Me and you Me and you": a title Gmail repeats on one line
            const twice = /^(.{3,}?) \1$/.exec(line);
            if (twice)
                line = twice[1];
            // "best outfit for m... best outfit for men old money style": the cut title, then the whole one
            const cut = /^(.{3,}?)(?:\.\.\.|…) (.+)$/.exec(line);
            if (cut && cut[2].startsWith(cut[1]))
                line = cut[2];
            const key = line.toLowerCase();
            if (seen[key])
                continue;
            seen[key] = true;
            out.push(line);
        }
        return out.join("\n");
    }
    // The body as the row reads it, without markup, for the copy button: tidied the same way, line breaks kept,
    // tags dropped and entities decoded (&amp; last, so "&amp;lt;" stays "&lt;").
    function plainBody(body, appName) {
        return root.processNotificationBody(body, appName)
            .replace(/<br\s*\/?>/gi, "\n")
            .replace(/<[^>]+>/g, "")
            .replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, '"').replace(/&#0?39;|&apos;/g, "'")
            .replace(/&#(\d+);/g, (m, n) => String.fromCodePoint(Number(n)))
            .replace(/&#x([0-9a-f]+);/gi, (m, n) => String.fromCodePoint(parseInt(n, 16)))
            .replace(/&amp;/g, "&")
            .trim()
    }
    // What an expanded row shows of it: eight lines and about 360 characters (~8 lines at the popup's width; a line
    // limit does not hold rich text). The row's click opens the rest. Never cut inside a tag.
    function preview(body) {
        const lines = String(body ?? "").split("\n");
        let text = lines.slice(0, 8).join("\n");
        let cut = lines.length > 8;
        if (text.length > 360) {
            let at = text.lastIndexOf(" ", 360);
            if (at < 270)
                at = 360;
            if (text.lastIndexOf("<", at) > text.lastIndexOf(">", at))
                at = text.lastIndexOf("<", at);
            text = text.substring(0, at);
            cut = true;
        }
        return cut ? text.replace(/\s+$/, "") + "…" : text;
    }

    // A person wrote this, as opposed to a status line: the category hint, an inline reply, or
    // a messenger as the sender. Messages get the sender's name weighted, the body at full
    // colour and an initials avatar when the sender sent no picture.
    readonly property var messengers: ["signal", "telegram", "discord", "whatsapp", "element", "slack",
        "matrix", "beeper", "teams", "zulip", "thunderbird", "mail", "messages", "sms",
        "fractal", "dino", "gajim", "mattermost", "rocket"]
    function isMessage(notif) {
        if (!notif)
            return false
        const cat = (notif.category ?? "").toLowerCase()
        if (cat.startsWith("im") || cat.startsWith("email"))
            return true
        if (notif.hasInlineReply)
            return true
        // the app's name only: every phone notification carries KDE Connect's desktop entry, and "kdeconnect" in the
        // list made Monzo, a CAPTCHA and a Pinterest email chats, with a reply. A phone chat offers its reply (above).
        const app = (notif.appName ?? "").toLowerCase()
        return app.length > 0 && messengers.some(m => app.includes(m))
    }
    function initials(name) {
        // leading symbols and emoji (surrogate pairs) are dropped, so w[0] below is a whole letter
        const words = (name ?? "").replace(/<[^>]+>/g, "").trim().split(/\s+/)
            .map(w => w.replace(/^[^A-Za-z0-9\u00C0-\uD7FF\uE000-\uFFFF]+/, "")).filter(w => w.length > 0)
        return words.slice(0, 2).map(w => w[0].toUpperCase()).join("")
    }

    // The first link a body carries: an <a href> when it has markup, else a bare URL.
    // The row's open button and a click on the row open it, so the text stays plain.
    // A bare name is a site only where its name ends at the domain (app.config is not app.co, report.de.pdf not report.de),
    // and never by .sh: that is the script a notification names ("Finished install.sh"), and https://install.sh opened.
    readonly property var urlPattern: /\b(?:https?:\/\/[^\s<"]+|www\.[^\s<"]+|[\w-]+(?:\.[\w-]+)*\.(?:com|org|net|io|dev|app|co|me|gg|tv|ai|edu|gov|uk|de)(?![\w-]|\.[\w-])(?:\/[^\s<"]*)?)/i
    function firstLink(body) {
        const href = /<a\s[^>]*href="([^"]+)"/i.exec(body ?? "")
        // an href is the sender's exact link (entities decoded, &amp; last); trailing punctuation is trimmed only
        // from a bare URL, where it belongs to the sentence
        const url = href ? href[1].replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&")
            : (urlPattern.exec((body ?? "").replace(/<[^>]+>/g, " ")) ?? [""])[0].replace(/[.,;:!?)]+$/, "")
        if (!url)
            return ""
        // only web and mail links open from a click; any other scheme would start whatever handler is registered
        const scheme = /^([a-z]+):/i.exec(url)
        if (scheme)
            return /^(https?|mailto)$/i.test(scheme[1]) ? url : ""
        return `https://${url}`
    }
}
