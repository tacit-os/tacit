import QtQuick
import QtWebEngine
import Tacit.Kit as K
import Tacit.MailHtml

Rectangle {
    id: view

    required property string html
    property string backgroundMode: "none"
    property bool quotedHistoryExpanded: false
    readonly property bool quotedHistoryAnimating: browser.animatingHistory
    readonly property real quotedHistoryToggleY: browser.quoteToggleY
    readonly property string appliedBackground: browser.fallbackBackground
    property bool remoteImages: false
    property var attachments: []
    property var mailboxClient: null
    property string searchTerm: ""
    readonly property int searchMatchCount: browser.searchMatchCount
    property string messageId: ""
    property var remoteImageSources: []
    property Connections imagePermissions: Connections {
        target: view.mailboxClient
        ignoreUnknownSignals: true
        function onImageStateLoaded(id, ticket, result, ok) {
            if (id !== view.messageId || ticket !== browser.imageStateTicket || !browser.documentPrepared || !ok) return;
            const cached = new Set((result.cached_images ?? []).map(image => image.url));
            for (const url of browser.documentImageURLs) {
                if (cached.has(url) || browser.cachedImageCompletions.has(url)) browser.cacheMisses.delete(url);
                else if (!result.origin_allowed) browser.cacheMisses.add(url);
            }
            browser.originPermissionKnown = true;
            browser.originAllowed = !!result.origin_allowed;
            browser.updateImagePrompt();
            browser.retryPermittedImages();
        }
        function onImagePoliciesChanged() { browser.refreshPermissions(); }
        function onMessageImagesAllowed(id, ok) {
            if (ok && id === view.messageId) browser.refreshPermissions();
        }
    }
    readonly property bool displayReady: browser.bodyReady && !(browser.loadingMessage && browser.imageCount > 0)
    readonly property bool imagePromptReady: displayReady && !(loading && browser.imageAttempt > 0)
    readonly property bool ready: browser.loaded
    readonly property bool loading: browser.loadingMessage
    readonly property bool hasExternalImages: browser.hasExternalImages
    readonly property int imageCount: browser.imageCount
    readonly property int finishedImages: browser.finishedImages
    readonly property real progress: ready ? 1 : imageCount > 0 && finishedImages < imageCount
        ? finishedImages / imageCount : 0
    signal externalLinkRequested(url link)
    function retryExternalImages() { browser.retryProxyImages(); }
    function scrollHorizontally(delta) {
        if (!Number.isFinite(delta)) return;
        htmlViewport.contentX = Math.max(0, Math.min(htmlViewport.contentWidth - htmlViewport.width,
            htmlViewport.contentX + delta));
    }
    implicitHeight: browser.displayHeight
    color: appliedBackground === "primary" ? K.Kit.tokens.inkMain
        : appliedBackground === "overlay" ? K.Kit.tokens.overlay : "transparent"
    clip: true

    function openLink(link) {
        if (/^https?:\/\//i.test(link.toString()))
            externalLinkRequested(link);
    }

    MailWebProfile {
        id: mailProfile
        objectName: "mailImageProfile"
        remoteImages: view.remoteImages && !view.mailboxClient
        onImageCacheMiss: url => {
            if (browser.cachedImageCompletions.has(url)) return;
            browser.cacheMisses.add(url);
            browser.updateImagePrompt();
            browser.retryPermittedImages();
            measureLayout.restart();
        }
        onCachedImageReady: url => {
            browser.cachedImageCompletions.add(url);
            browser.cacheMisses.delete(url);
            browser.updateImagePrompt();
        }
        onOriginImageStarted: url => {
            browser.originStarted(url);
        }
        onOriginImageFinished: (url, ok) => {
            browser.originFinished(url, ok);
        }
        localImages: view.attachments.map(file => file.inlineSource ?? "")
            .concat(view.remoteImageSources.map(image => image.source), browser.savedSources)
            .filter(source => source.startsWith("tacit-image:"))
        onDownloadRequested: download => download.cancel()
    }

    Flickable {
        id: htmlViewport
        objectName: "htmlHorizontalViewport"
        anchors.fill: parent
        contentWidth: browser.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width
        clip: true
    }

    WebEngineView {
        id: browser
        parent: htmlViewport.contentItem
        objectName: view.visible ? "mailHtmlBrowser" : ""

        property real documentWidth: 0
        property bool bodyReady: false
        property bool animatingHistory: false
        property real displayHeight: 1
        property int historyRevision: 0
        property real quoteToggleY: 0
        property var quoteRegions: []
        property bool loaded: false
        property bool loadingMessage: false
        property int searchMatchCount: 0
        property bool documentPrepared: false
        property string fallbackBackground: "none"
        property bool initialized: false
        property bool hasExternalImages: false
        property bool originPermissionKnown: false
        property bool originAllowed: false
        property var permissionRetries: new Set()
        property int imageCount: -1
        property int finishedImages: 0
        property int documentRevision: 0
        property string pendingHtml: ""
        property var savedImages: new Map()
        property var savedSources: []
        property var activeImages: new Set()
        property var cacheMisses: new Set()
        property var cachedImageCompletions: new Set()
        property var documentImageURLs: []
        property int imageStateTicket: 0
        property var completedOrigins: new Set()
        property int imageAttempt: 0
        property bool retryOnShow: false
        property int remoteTotal: 0
        property int remoteFinished: 0
        width: Math.max(view.width, documentWidth)
        height: 1
        profile: mailProfile
        lifecycleState: !view.visible && loaded && !loadingMessage
            ? WebEngineView.LifecycleState.Frozen : WebEngineView.LifecycleState.Active
        backgroundColor: "transparent"

        settings.javascriptEnabled: false
        settings.javascriptCanOpenWindows: false
        settings.localContentCanAccessFileUrls: false
        settings.localContentCanAccessRemoteUrls: false
        settings.dnsPrefetchEnabled: false
        settings.hyperlinkAuditingEnabled: false
        settings.errorPageEnabled: false
        settings.unknownUrlSchemePolicy: WebEngineSettings.DisallowUnknownUrlSchemes

        function loadMessage() {
            documentWidth = 0;
            htmlViewport.contentX = 0;
            ++historyRevision;
            historyResize.stop();
            animatingHistory = false;
            ++documentRevision;
            savedImages = new Map(view.remoteImageSources.map(image => [image.url, image.source]));
            savedSources = Array.from(savedImages.values());
            activeImages = new Set();
            cacheMisses = new Set();
            cachedImageCompletions = new Set();
            documentImageURLs = [];
            imageStateTicket = 0;
            originPermissionKnown = false;
            originAllowed = false;
            permissionRetries = new Set();
            permissionRefresh.stop();
            completedOrigins = new Set();
            imageAttempt = 0;
            remoteTotal = 0;
            remoteFinished = 0;
            measureLayout.stop();
            documentPrepared = false;
            bodyReady = false;
            fallbackBackground = "none";
            loaded = false;
            hasExternalImages = false;
            imageCount = -1;
            finishedImages = 0;
            loadingMessage = true;
            height = 1;
            displayHeight = 1;
            const t = K.Kit.tokens;
            const html = view.html;
            // Keep the initial data URL below Chromium's navigation limit.
            pendingHtml = html.length > 200000 ? html : "";
            loadHtml("<!doctype html><meta charset='utf-8'>"
                + "<meta name='tacit-document' content='" + documentRevision + "'>"
                + "<meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; img-src data: tacit-image:" + (view.remoteImages && !view.mailboxClient ? " https:" : "") + "; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\">"
                + "<meta name='referrer' content='no-referrer'>"
                + "<meta http-equiv='x-dns-prefetch-control' content='off'>"
                + "<style>body{margin:0;color:" + t.inkMain
                + ";font:" + t.size.body + "px sans-serif;overflow-wrap:anywhere}"
                + ":where(body > :first-child, body > style + :first-of-type){margin-block-start:0}"
                + "a{color:" + t.accent + "}img{max-width:100%;height:auto}"
                + "[data-tacit-quoted-history]{display:block!important}"
                + "[data-tacit-quoted-history][hidden]{display:none!important}</style>"
                + (pendingHtml ? "<body></body>" : html));
            measureLayout.restart();
        }
        function inlineImageScript() {
            const images = attachments.filter(file => file.inline).map(file => ({
                source: "cid:" + file.id, width: file.width, height: file.height, data: file.inlineSource
            }));
            return "(() => { const files = " + JSON.stringify(images)
                + "; for (const img of document.images) {"
                + " const file = files.find(file => file.source === (img.dataset.tacitCid || img.getAttribute('src')));"
                + " if (!file) continue; img.dataset.tacitCid = file.source;"
                + " if (file.width && file.height) {"
                + " if (!img.hasAttribute('width')) img.setAttribute('width', file.width);"
                + " if (!img.hasAttribute('height')) img.setAttribute('height', file.height);"
                + " if (!img.style.aspectRatio && img.getAttribute('width') && img.getAttribute('height'))"
                + " img.style.aspectRatio = img.getAttribute('width') + ' / ' + img.getAttribute('height');"
                + " } if (file.data && img.getAttribute('src') !== file.data) img.src = file.data;"
                + " } return true; })()";
        }

        function cachedImageScript() {
            if (!savedImages.size) return "true";
            return "(() => { const images = new Map(" + JSON.stringify(Array.from(savedImages)) + ");"
                + " for (const img of document.images) {"
                + " const url = img.dataset.tacitRemote || img.currentSrc || img.src;"
                + " const source = images.get(url); if (!source) continue;"
                + " img.dataset.tacitRemote = url; img.removeAttribute('srcset');"
                + " img.closest('picture')?.querySelectorAll('source').forEach(element => element.removeAttribute('srcset'));"
                + " if (img.src !== source) img.src = source; }"
                + " for (const element of document.querySelectorAll('*')) {"
                + " let background = element.dataset.tacitBackground || getComputedStyle(element).backgroundImage;"
                + " if (background === 'none') continue; element.dataset.tacitBackground = background;"
                + " background = background.replace(/url\\((['\"]?)(.*?)\\1\\)/g, (all, quote, url) => images.has(url) ? 'url(' + JSON.stringify(images.get(url)) + ')' : all);"
                + " if (background !== getComputedStyle(element).backgroundImage) element.style.backgroundImage = background;"
                + " }"
                + " const cssImages = []; for (const element of document.querySelectorAll('*')) {"
                + " const bg = getComputedStyle(element).backgroundImage;"
                + " for (const [url, source] of images) if (bg.includes(source)) { const img = new Image(); img.src = source; cssImages.push(img); }"
                + " } globalThis.tacitBackgroundImages = cssImages; return true; })()";
        }

        function externalImageURLsScript() {
            return "(() => { const urls = new Set(Array.from(document.images)"
                + " .map(img => img.dataset.tacitRemote || img.currentSrc || img.src).filter(url => /^https:/i.test(url)));"
                + " for (const element of document.querySelectorAll('*')) {"
                + " for (const part of getComputedStyle(element).backgroundImage.split('url(').slice(1)) {"
                + " const url = part.split(')')[0].trim().split(String.fromCharCode(34)).join('').split(String.fromCharCode(39)).join('');"
                + " if (/^https:/i.test(url)) urls.add(url); }"
                + " } return Array.from(urls); })()";
        }

        function applyLocalImages() {
            if (!documentPrepared) return;
            for (const image of view.remoteImageSources) if (!savedImages.has(image.url)) savedImages.set(image.url, image.source);
            savedSources = Array.from(savedImages.values());
            const revision = documentRevision;
            runJavaScript(inlineImageScript() + ";" + cachedImageScript(), 1, () => {
                if (revision === documentRevision) measureLayout.restart();
            });
        }

        function proxySource(url) {
            return "tacit-image://mail/v1/messages/" + encodeURIComponent(view.messageId)
                + "/remote-image?url=" + encodeURIComponent(url) + "&attempt=" + imageAttempt;
        }

        function originStarted(url) {
            if (activeImages.has(url)) return;
            activeImages.add(url);
            if (!loadingMessage) { remoteTotal = 0; remoteFinished = 0; completedOrigins = new Set(); }
            ++remoteTotal;
            imageCount = remoteTotal;
            finishedImages = remoteFinished;
            loaded = false;
            loadingMessage = true;
            measureLayout.restart();
        }

        function originFinished(url, ok) {
            if (!activeImages.delete(url)) return;
            ++remoteFinished;
            completedOrigins.add(url);
            if (!ok) { cacheMisses.add(url); updateImagePrompt(); }
            retryPermittedImages();
            measureLayout.restart();
        }

        // A late failed cache probe may arrive after Always was confirmed. Retry
        // each URL once per permission refresh, without looping on broken origins.
        function retryPermittedImages() {
            if (!originPermissionKnown || !originAllowed || activeImages.size
                    || !Array.from(cacheMisses).some(url => !permissionRetries.has(url))) return;
            for (const url of cacheMisses) permissionRetries.add(url);
            retryProxyImages();
        }

        function updateImagePrompt() {
            const canInspectPermission = typeof view.mailboxClient?.inspectImages === "function";
            hasExternalImages = cacheMisses.size > 0
                && (!canInspectPermission || (originPermissionKnown && !originAllowed));
        }

        function refreshPermissions() {
            imageStateTicket = 0;
            originPermissionKnown = false;
            permissionRetries = new Set();
            updateImagePrompt();
            if (!view.visible) { retryOnShow = true; return; }
            permissionRefresh.restart();
            retryProxyImages();
        }

        Timer {
            id: permissionRefresh
            interval: 0
            onTriggered: browser.inspectImageState(browser.documentImageURLs)
        }

        function retryProxyImages() {
            if (!documentPrepared || !view.mailboxClient || !cacheMisses.size) return;
            ++imageAttempt;
            if (!activeImages.size) { remoteTotal = 0; remoteFinished = 0; completedOrigins = new Set(); }
            for (const url of cacheMisses) savedImages.set(url, proxySource(url));
            savedSources = Array.from(savedImages.values());
            loaded = false;
            loadingMessage = true;
            applyLocalImages();
        }

        // Highlight ranges in the existing document; typing must not reload a cached mail.
        function highlightSearch() {
            if (!documentPrepared || !view.visible) return;
            const revision = documentRevision;
            const term = view.searchTerm.trim();
            runJavaScript("(() => {"
                + " if (!CSS.highlights || typeof Highlight === 'undefined') return 0;"
                + " CSS.highlights.delete('tacit-search');"
                + " const term = " + JSON.stringify(term.toLowerCase()) + "; if (!term) return 0;"
                + " let style = document.getElementById('tacit-search-style');"
                + " if (!style) { style = document.createElement('style'); style.id = 'tacit-search-style';"
                + " style.textContent = " + JSON.stringify("::highlight(tacit-search) { background-color: "
                    + K.Kit.tokens.accent + "; color: " + K.Kit.tokens.inkOnAccent + "; }")
                + "; document.head.appendChild(style); }"
                + " const ranges = []; const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);"
                + " let node; while ((node = walker.nextNode())) {"
                + " if (!node.parentElement || node.parentElement.closest('script,style,noscript')) continue;"
                + " const text = node.textContent.toLowerCase(); let start = 0, index;"
                + " while ((index = text.indexOf(term, start)) !== -1) {"
                + " const range = new Range(); range.setStart(node, index); range.setEnd(node, index + term.length);"
                + " ranges.push(range); start = index + term.length; } }"
                + " CSS.highlights.set('tacit-search', new Highlight(...ranges)); return ranges.length; })()", 1,
                count => { if (revision === documentRevision && term === view.searchTerm.trim()) searchMatchCount = count || 0; });
        }

        function inspectImageState(urls) {
            documentImageURLs = urls;
            if (urls.length && typeof view.mailboxClient?.inspectImages === "function")
                imageStateTicket = view.mailboxClient.inspectImages(view.messageId);
        }

        function registerImageURLs(urls) {
            const added = urls.filter(url => !documentImageURLs.includes(url));
            if (!added.length) return;
            const all = documentImageURLs.concat(added);
            if (view.mailboxClient) {
                for (const url of added) if (!savedImages.has(url)) savedImages.set(url, proxySource(url));
                savedSources = Array.from(savedImages.values());
                inspectImageState(all);
                applyLocalImages();
            } else documentImageURLs = all;
        }

        function prepareDocument() {
            const revision = documentRevision;
            const primary = K.Kit.tokens.inkMain;
            const overlay = K.Kit.tokens.overlay;
            const candidates = JSON.stringify([
                {mode: "primary", css: String(primary), rgb: [primary.r, primary.g, primary.b]},
                {mode: "overlay", css: String(overlay), rgb: [overlay.r, overlay.g, overlay.b]}
            ]);
            const insert = pendingHtml ? "const html = " + JSON.stringify(pendingHtml)
                + "; const parsed = new DOMParser().parseFromString(html, 'text/html');"
                + " for (const name of ['style', 'bgcolor', 'background', 'class', 'id']) {"
                + " if (parsed.body.hasAttribute(name)) document.body.setAttribute(name, parsed.body.getAttribute(name)); }"
                + " document.body.innerHTML = html;" : "";
            runJavaScript("(() => {"
                + " if (document.querySelector('meta[name=tacit-document]')?.content !== '" + revision + "'"
                + " || document.readyState === 'loading') return false;"
                + insert
                + " const firstQuote = document.querySelector('[data-tacit-quoted-history]');"
                + " if (firstQuote && !document.querySelector('[data-tacit-quote-toggle]')) {"
                + " const slot = document.createElement('div'); slot.dataset.tacitQuoteToggle = '';"
                + " slot.setAttribute('aria-hidden', 'true');"
                + " slot.style.setProperty('height', '" + (K.Kit.tokens.height.action + K.Kit.tokens.space.m) + "px', 'important');"
                + " slot.style.setProperty('display', 'block', 'important');"
                + " firstQuote.before(slot); }"
                + " for (const quote of document.querySelectorAll('[data-tacit-quoted-history]')) {"
                + " const hasQuoteLine = Array.from(quote.querySelectorAll('blockquote, div, table, td'))"
                + " .some(element => { const style = getComputedStyle(element);"
                + " return style.borderLeftStyle !== 'none' && parseFloat(style.borderLeftWidth) > 0; });"
                + " if (!hasQuoteLine) {"
                + " quote.dataset.tacitQuoteLine = 'true';"
                + " quote.style.setProperty('padding-inline-start', '" + K.Kit.tokens.space.m + "px');"
                + " } }"
                + historyVisibilityScript()
                + " const hasBackground = element => {"
                + " if (!element) return false; const style = getComputedStyle(element);"
                + " return (style.backgroundColor !== 'transparent' && style.backgroundColor !== 'rgba(0, 0, 0, 0)')"
                + " || style.backgroundImage !== 'none'; };"
                + " const wrapper = Array.from(document.body.children)"
                + " .find(element => ['DIV', 'TABLE', 'MAIN', 'ARTICLE', 'SECTION'].includes(element.tagName));"
                + " let background = 'none';"
                + " if (![document.documentElement, document.body, wrapper].some(hasBackground)) {"
                + " const candidates = " + candidates + ";"
                + " const mode = " + JSON.stringify(view.backgroundMode) + ";"
                + " let selected = candidates.find(candidate => candidate.mode === mode);"
                + " if (mode === 'auto') {"
                + " const luminance = rgb => rgb.map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4)"
                + " .reduce((sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index], 0);"
                + " const score = candidate => samples.reduce((sum, sample) => {"
                + " const rgb = sample.rgb.map((value, index) => value * sample.alpha + candidate.rgb[index] * (1 - sample.alpha));"
                + " const a = luminance(rgb), b = luminance(candidate.rgb);"
                + " return sum + sample.weight * (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05); }, 0);"
                + " const samples = []; const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);"
                + " let node; while ((node = walker.nextNode()) && samples.length < 200) {"
                + " const text = node.textContent.trim(), element = node.parentElement;"
                + " if (!text || !element || ['STYLE', 'SCRIPT', 'NOSCRIPT'].includes(element.tagName)) continue;"
                + " const style = getComputedStyle(element);"
                + " if (!element.getClientRects().length || style.visibility !== 'visible' || Number(style.opacity) === 0) continue;"
                + " const values = style.color.match(/[0-9.]+/g)?.map(Number);"
                + " if (values && values.length >= 3) samples.push({rgb: values.slice(0, 3).map(value => value / 255),"
                + " alpha: values[3] ?? 1, weight: Math.min(text.length, 1000)});"
                + " }"
                + " selected = score(candidates[0]) > score(candidates[1]) ? candidates[0] : candidates[1];"
                + " }"
                + " if (selected) { background = selected.mode;"
                + " document.body.style.padding = '" + K.Kit.tokens.space.s + "px'; }"
                + " }"
                + " for (const img of document.images) if (img.loading === 'lazy') img.loading = 'eager';"
                + " " + inlineImageScript() + ";"
                + " return {background, urls: " + externalImageURLsScript() + "}; })()", 1, prepared => {
                    if (revision !== documentRevision || !loadingMessage)
                        return;
                    if (prepared) {
                        pendingHtml = "";
                        fallbackBackground = prepared.background;
                        documentPrepared = true;
                        inspectImageState(prepared.urls);
                        highlightSearch();
                        if (view.mailboxClient) {
                            for (const url of prepared.urls) {
                                if (!savedImages.has(url)) savedImages.set(url, proxySource(url));
                            }
                            savedSources = Array.from(savedImages.values());
                        }
                        runJavaScript(cachedImageScript(), 1, () => {
                            if (revision === documentRevision) fitDocument();
                        });
                    } else {
                        measureLayout.restart();
                    }
                });
        }

        function quoteRegionsScript() {
            return "Array.from(document.querySelectorAll('[data-tacit-quote-line]'))"
                + " .map(quote => { const rect = quote.getBoundingClientRect();"
                + " return {x: rect.left + window.scrollX, y: rect.top + window.scrollY, height: rect.height}; })"
                + " .filter(rect => rect.height > 0)";
        }

        function historyVisibilityScript() {
            return " for (const quote of document.querySelectorAll('[data-tacit-quoted-history]'))"
                + " quote.hidden = " + (!view.quotedHistoryExpanded) + ";";
        }
        function syncHistoryDocument() {
            const revision = documentRevision;
            runJavaScript("(() => {" + historyVisibilityScript()
                + " return " + externalImageURLsScript() + "; })()", 1, urls => {
                if (revision !== documentRevision) return;
                registerImageURLs(urls ?? []);
                applyLocalImages();
                highlightSearch();
                fitDocument();
            });
        }

        function updateHistoryVisibility() {
            if (!documentPrepared) return;
            const ticket = ++historyRevision;
            historyResize.stop();
            animatingHistory = false;
            if (K.Kit.reducedMotion || !view.visible || !bodyReady) {
                syncHistoryDocument();
                return;
            }
            const revision = documentRevision;
            const expanding = view.quotedHistoryExpanded;
            animatingHistory = true;
            // Measure the destination without painting a hidden intermediate frame.
            // During closing the full DOM stays alive behind QML's shrinking clip.
            runJavaScript("(() => { const quotes = Array.from(document.querySelectorAll('[data-tacit-quoted-history]'));"
                + " for (const quote of quotes) quote.hidden = " + (!expanding) + ";"
                + " const range = document.createRange(); range.selectNodeContents(document.body);"
                + " const height = Math.max(document.body.scrollHeight, document.body.offsetHeight,"
                + " range.getBoundingClientRect().bottom + window.scrollY);"
                + " for (const quote of quotes) quote.hidden = false;"
                + " return {height, quoteRegions: " + quoteRegionsScript()
                + ", urls: " + externalImageURLsScript() + "}; })()", 1, result => {
                    if (revision !== documentRevision || ticket !== historyRevision) return;
                    if (!result || !Number.isFinite(result.height)) {
                        animatingHistory = false;
                        syncHistoryDocument();
                        return;
                    }
                    quoteRegions = result.quoteRegions;
                    registerImageURLs(result.urls ?? []);
                    applyLocalImages();
                    const motion = K.Kit.motion(expanding ? "arriveSmall" : "leave");
                    const destination = Math.max(1, Math.ceil(result.height));
                    // Keep Chromium's viewport stable; only QML's outer clip moves.
                    height = Math.max(height, destination);
                    historyResize.from = displayHeight;
                    historyResize.to = destination;
                    historyResize.duration = K.Kit.ms(motion.ms);
                    historyResize.easing.bezierCurve = motion.curve;
                    historyResize.start();
                });
        }

        NumberAnimation {
            id: historyResize
            target: browser
            property: "displayHeight"
            easing.type: Easing.BezierSpline
            onFinished: {
                browser.animatingHistory = false;
                browser.syncHistoryDocument();
            }
        }

        function fitDocument() {
            if (animatingHistory) return;
            if (!documentPrepared) {
                prepareDocument();
                return;
            }
            const revision = documentRevision;
            const measuredWidth = width;
            const countRemote = view.remoteImages;
            // Broken or blocked images are complete, so they cannot keep the message hidden.
            runJavaScript("(() => {"
                + " const images = Array.from(document.images).concat(globalThis.tacitBackgroundImages || []);"
                + " const completed = " + JSON.stringify(Array.from(completedOrigins)) + ";"
                + " const decoded = completed.filter(url => images.filter(img => img.dataset?.tacitRemote === url"
                + " || (img.src && new URL(img.src, document.baseURI).searchParams.get('url') === url))"
                + " .every(img => img.complete)).length;"
                + " const external = images.filter(image => /^https:/i.test(image.currentSrc || image.src));"
                + " const imageURLs = " + externalImageURLsScript() + ";"
                + " const externalCount = imageURLs.length;"
                + " const remote = " + countRemote + " ? external : [];"
                + " const finished = remote.filter(image => image.complete).length;"
                + " const pending = images.some(image => !image.complete) || document.readyState !== 'complete';"
                + " const range = document.createRange(); range.selectNodeContents(document.body);"
                + " const height = Math.max(document.body.scrollHeight, document.body.offsetHeight,"
                + " range.getBoundingClientRect().bottom + window.scrollY);"
                + " const toggle = document.querySelector('[data-tacit-quote-toggle]');"
                + " const quoteToggleY = toggle ? toggle.getBoundingClientRect().top + window.scrollY : 0;"
                + " const quoteRegions = " + quoteRegionsScript() + ";"
                + " return {width: Math.max(document.documentElement.scrollWidth, document.body.scrollWidth), external: externalCount, total: remote.length, finished, decoded, pending, height, quoteToggleY, quoteRegions, imageURLs}; })()", 1, result => {
                    if (animatingHistory || revision !== documentRevision || measuredWidth !== width || (!loadingMessage && !loaded))
                        return;
                    if (!result || !Number.isFinite(result.height)) {
                        bodyReady = false;
                        loaded = false;
                        loadingMessage = false;
                        return;
                    }
                    registerImageURLs(result.imageURLs ?? []);
                    if (!view.mailboxClient) hasExternalImages = result.external > 0;
                    const managed = !!view.mailboxClient;
                    imageCount = managed ? remoteTotal : result.total;
                    finishedImages = managed ? result.decoded : result.finished;
                    // Local cache probes may still be pending; they must not hide the HTML body.
                    documentWidth = Math.max(view.width, Math.ceil(result.width));
                    height = Math.max(1, Math.ceil(result.height));
                    displayHeight = height;
                    quoteToggleY = result.quoteToggleY;
                    quoteRegions = result.quoteRegions;
                    bodyReady = true;
                    if (result.pending || (managed && remoteFinished < remoteTotal)) {
                        measureLayout.restart();
                        return;
                    }
                    loaded = true;
                    loadingMessage = false;
                });
        }

        Timer {
            id: measureLayout
            interval: browser.documentPrepared ? 100 : 20
            onTriggered: browser.fitDocument()
        }

        Component.onCompleted: {
            initialized = true;
            loadMessage();
        }
        onWidthChanged: if (loaded || loadingMessage) measureLayout.restart()
        onLoadingChanged: info => {
            if (info.status === WebEngineView.LoadFailedStatus) {
                measureLayout.stop();
                bodyReady = false;
                loadingMessage = false;
            }
        }
        onRenderProcessTerminated: {
            measureLayout.stop();
            bodyReady = false;
            loaded = false;
            loadingMessage = false;
        }
        onNavigationRequested: request => {
            if (request.navigationType === WebEngineNavigationRequest.LinkClickedNavigation) {
                request.reject();
                view.openLink(request.url);
            } else if (!request.isMainFrame || request.navigationType !== WebEngineNavigationRequest.TypedNavigation
                       || !request.url.toString().startsWith("data:text/html")) {
                request.reject();
            }
        }
        onNewWindowRequested: request => {
            if (request.userInitiated)
                view.openLink(request.requestedUrl);
        }
        onContextMenuRequested: request => request.accepted = true
        onFileDialogRequested: request => request.dialogReject()
        onPermissionRequested: permission => permission.deny()
    }

    // Geometry comes from the document; the rule is drawn by QML, like the header.
    Repeater {
        model: (view.quotedHistoryExpanded || browser.animatingHistory) && browser.bodyReady ? browser.quoteRegions : []
        delegate: Rectangle {
            required property var modelData
            required property int index
            objectName: "htmlQuoteHairline-" + view.messageId + "-" + index
            x: modelData.x - htmlViewport.contentX
            y: modelData.y
            width: 1
            height: modelData.height
            z: 1
            color: Qt.alpha(K.Kit.tokens.inkMain, K.Kit.tokens.wash.hover + 0.02)
            Accessible.ignored: true
        }
    }

    onWidthChanged: {
        browser.documentWidth = 0;
        if (browser.initialized) browser.fitDocument();
    }
    onRemoteImagesChanged: if (browser.initialized) {
        if (!mailboxClient) browser.loadMessage();
    }
    onRemoteImageSourcesChanged: if (browser.initialized) browser.applyLocalImages()
    onAttachmentsChanged: if (browser.initialized) browser.applyLocalImages()
    onQuotedHistoryExpandedChanged: browser.updateHistoryVisibility()
    onSearchTermChanged: browser.highlightSearch()
    onVisibleChanged: {
        if (visible) browser.highlightSearch();
        if (visible && browser.initialized && browser.retryOnShow) {
            browser.retryOnShow = false;
            browser.refreshPermissions();
        }
    }
    onHtmlChanged: if (browser.initialized) browser.loadMessage()
    onBackgroundModeChanged: if (browser.initialized) browser.loadMessage()
}
