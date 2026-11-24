import QtQuick
import QtTest
import ".." as Mail

Item {
    id: fixture
    width: 640; height: 480
    QtObject {
        id: client
        property int ticket: 0
        signal imageStateLoaded(string id, int ticket, var result, bool ok)
        signal imagePoliciesChanged()
        signal messageImagesAllowed(string id, bool ok)
        function inspectImages(id) { return ++ticket; }
    }
    Component {
        id: documentComponent
        Mail.MailHtmlView { width: fixture.width; mailboxClient: client; messageId: "cited-images" }
    }
    TestCase {
        name: "CitedImages"
        when: windowShown
        property var document: null
        function cleanup() { if (document) document.destroy(); document = null; wait(0); }
        function test_alwaysPermissionDoesNotFlashPrompt_data() {
            return [{tag: "always", allowed: true, cached: false, prompt: false},
                {tag: "cached", allowed: false, cached: true, prompt: false},
                {tag: "ask", allowed: false, cached: false, prompt: true}];
        }
        function test_alwaysPermissionDoesNotFlashPrompt(row) {
            document = documentComponent.createObject(fixture, {html: "<p>New body</p>"});
            tryVerify(() => document.ready);
            const browser = findChild(document, "mailHtmlBrowser");
            const profile = findChild(document, "mailImageProfile");
            const url = "https://example.invalid/cited.png";
            browser.inspectImageState([url]);
            profile.imageCacheMiss(url);
            verify(!document.hasExternalImages, "Do not offer consent before maild's permission reply");
            client.imageStateLoaded("cited-images", client.ticket, {
                origin_allowed: row.allowed, cached_images: row.cached ? [{url}] : []
            }, true);
            compare(document.hasExternalImages, row.prompt);
            if (row.allowed) {
                profile.imageCacheMiss(url);
                verify(!document.hasExternalImages, "An older failed probe must not override Always");
            }
        }
        function test_lateMissWithAlwaysRetriesOnce() {
            document = documentComponent.createObject(fixture, {html: "<p>New body</p>"});
            tryVerify(() => document.ready);
            const browser = findChild(document, "mailHtmlBrowser");
            const profile = findChild(document, "mailImageProfile");
            const url = "https://example.invalid/late-cited.png";
            browser.inspectImageState([url]);
            client.imageStateLoaded("cited-images", client.ticket, {origin_allowed: true, cached_images: []}, true);
            const before = browser.imageAttempt;
            profile.imageCacheMiss(url);
            compare(browser.imageAttempt, before + 1);
            verify(!document.hasExternalImages);
            profile.imageCacheMiss(url);
            compare(browser.imageAttempt, before + 1, "Broken origins must not trigger an endless retry loop");
        }
        function test_permissionRetryWaitsForCurrentDownload() {
            document = documentComponent.createObject(fixture, {html: "<p>New body</p>"});
            tryVerify(() => document.ready);
            const browser = findChild(document, "mailHtmlBrowser");
            const profile = findChild(document, "mailImageProfile");
            browser.inspectImageState(["https://example.invalid/late.png"]);
            client.imageStateLoaded("cited-images", client.ticket, {origin_allowed: true, cached_images: []}, true);
            profile.originImageStarted("https://example.invalid/current.png");
            const before = browser.imageAttempt;
            profile.imageCacheMiss("https://example.invalid/late.png");
            compare(browser.imageAttempt, before);
            profile.originImageFinished("https://example.invalid/current.png", true);
            compare(browser.imageAttempt, before + 1);
            verify(!document.hasExternalImages);
        }

        function test_revealedResponsiveImageIsRegistered() {
            const url = "https://example.invalid/responsive-cited.png";
            document = documentComponent.createObject(fixture, {
                html: "<p>New body</p><div data-tacit-quoted-history hidden><img id='responsive'></div>"
            });
            tryVerify(() => document.ready);
            const browser = findChild(document, "mailHtmlBrowser");
            let installed = false;
            browser.runJavaScript("(() => { const img = document.getElementById('responsive');"
                + " Object.defineProperty(img, 'currentSrc', {get: () => img.closest('[data-tacit-quoted-history]').hidden"
                + " ? '' : '" + url + "'}); return true; })()", 1, value => installed = value);
            tryVerify(() => installed);
            const revision = browser.documentRevision;
            document.quotedHistoryExpanded = true;
            tryVerify(() => browser.documentImageURLs.includes(url));
            verify(browser.savedImages.get(url).startsWith('tacit-image://mail/'));
            compare(browser.documentRevision, revision);
        }

        function test_revealedBackgroundUsesCachedImageWithoutReload() {
            const source = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7";
            const url = "https://example.invalid/cited-background.gif";
            document = documentComponent.createObject(fixture, {
                html: "<style>[data-tacit-quoted-history][hidden] .asset{background-image:none!important}"
                    + ".asset{width:30px;height:30px;background-image:url('" + url + "')}</style>"
                    + "<p>New body</p><div data-tacit-quoted-history hidden><div class='asset'></div></div>",
                remoteImageSources: [{url, source}]
            });
            tryVerify(() => document.ready);
            const browser = findChild(document, "mailHtmlBrowser");
            const revision = browser.documentRevision;
            document.quotedHistoryExpanded = true;
            let localImage = false;
            function inspect() {
                browser.runJavaScript("getComputedStyle(document.querySelector('.asset')).backgroundImage.includes('data:image/gif')"
                    + " && globalThis.tacitBackgroundImages?.some(image => image.complete && image.naturalWidth > 0)",
                    1, value => localImage = value);
                return localImage;
            }
            tryVerify(inspect);
            verify(!document.hasExternalImages);
            compare(browser.documentRevision, revision);
        }
    }
}
