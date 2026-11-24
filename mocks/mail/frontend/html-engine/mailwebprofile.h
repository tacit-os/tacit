#pragma once

#include <atomic>
#include <QBuffer>
#include <QDir>
#include <QMutex>
#include <QMutexLocker>
#include <QNetworkAccessManager>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPointer>
#include <QSet>
#include <QStandardPaths>
#include <QTimer>
#include <QWebEngineUrlScheme>
#include <QWebEngineUrlSchemeHandler>
#include <QWebEngineUrlRequestJob>
#include <QQuickWebEngineProfile>
#include <QUrl>
#include <QUrlQuery>
#include <QWebEngineUrlRequestInfo>
#include <QWebEngineUrlRequestInterceptor>
#include <QtQml/qqmlregistration.h>

// Linked launchers register before QApplication; the QML plugin also registers
// before its first WebEngine view when used from Quickshell.
inline const bool mailImageSchemeRegistered = [] {
    QWebEngineUrlScheme scheme("tacit-image");
    scheme.setSyntax(QWebEngineUrlScheme::Syntax::Host);
    scheme.setFlags(QWebEngineUrlScheme::SecureScheme | QWebEngineUrlScheme::CorsEnabled);
    QWebEngineUrlScheme::registerScheme(scheme);
    return true;
}();

class MailImageHandler : public QWebEngineUrlSchemeHandler {
    Q_OBJECT
public:
    explicit MailImageHandler(QObject *parent) : QWebEngineUrlSchemeHandler(parent) {
        network.setProxy(QNetworkProxy::NoProxy);
    }
    QSet<QUrl> allowed;
    void requestStarted(QWebEngineUrlRequestJob *job) override {
        const auto url = job->requestUrl();
        if (job->requestMethod() != "GET" || url.host() != "mail" || !allowed.contains(url)) {
            job->fail(QWebEngineUrlRequestJob::RequestDenied);
            return;
        }
        requestImage(job, false);
    }
signals:
    void cacheMiss(const QString &url);
    void originStarted(const QString &url);
    void originFinished(const QString &url, bool ok);
    void imageReady(const QString &url);
private:
    void requestImage(QWebEngineUrlRequestJob *job, bool origin) {
        const auto url = job->requestUrl();
        const auto imageURL = QUrlQuery(url).queryItemValue("url", QUrl::FullyDecoded);
        const auto socket = qEnvironmentVariable("TACIT_MAIL_SOCKET",
            QDir(qEnvironmentVariable("XDG_RUNTIME_DIR", QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)))
                .filePath("tacit-mail-mock/mail.sock"));
        QNetworkRequest request(QUrl("unix+http://localhost" + url.path(QUrl::FullyEncoded)
            + (url.hasQuery() ? "?" + url.query(QUrl::FullyEncoded) : QString{})));
        request.setAttribute(QNetworkRequest::FullLocalServerNameAttribute, socket);
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
        if (!origin) request.setRawHeader("Cache-Control", "only-if-cached");
        auto *reply = network.get(request);
        const QPointer<QWebEngineUrlRequestJob> pending(job);
        connect(job, &QObject::destroyed, reply, &QObject::deleteLater);
        QTimer::singleShot(origin ? 40000 : 5000, reply, [reply] { if (reply->isRunning()) reply->abort(); });
        connect(reply, &QNetworkReply::readyRead, reply, [reply] {
            if (reply->bytesAvailable() > 20 * 1024 * 1024) reply->abort();
        });
        connect(reply, &QNetworkReply::finished, this, [this, reply, pending, imageURL, origin] {
            if (!pending) { reply->deleteLater(); return; }
            const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            if (!origin && status == 504 && !imageURL.isEmpty()) {
                if (reply->rawHeader("X-Mail-Image-Origin-Allowed") == "true") {
                    emit originStarted(imageURL);
                    requestImage(pending, true);
                } else {
                    emit cacheMiss(imageURL);
                    pending->fail(QWebEngineUrlRequestJob::UrlNotFound);
                }
                reply->deleteLater();
                return;
            }
            const auto type = reply->header(QNetworkRequest::ContentTypeHeader).toByteArray().split(';').first();
            const bool ok = reply->error() == QNetworkReply::NoError && status == 200
                && type.startsWith("image/") && reply->bytesAvailable() <= 20 * 1024 * 1024;
            if (origin) emit originFinished(imageURL, ok);
            if (ok) {
                if (!imageURL.isEmpty()) emit imageReady(imageURL);
                auto *data = new QBuffer(pending);
                data->setData(reply->readAll());
                data->open(QIODevice::ReadOnly);
                pending->reply(type, data);
            } else {
                if (!imageURL.isEmpty()) emit cacheMiss(imageURL);
                pending->fail(QWebEngineUrlRequestJob::UrlNotFound);
            }
            reply->deleteLater();
        });
    }
    QNetworkAccessManager network;
};

class MailWebProfile : public QQuickWebEngineProfile {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool remoteImages READ remoteImages WRITE setRemoteImages)
    Q_PROPERTY(QStringList localImages READ localImages WRITE setLocalImages)

public:
    explicit MailWebProfile(QObject *parent = nullptr) : QQuickWebEngineProfile(parent)
    {
        setHttpCacheType(NoCache);
        setUrlRequestInterceptor(&requests);
        images = new MailImageHandler(this);
        installUrlSchemeHandler("tacit-image", images);
        connect(images, &MailImageHandler::cacheMiss, this, &MailWebProfile::imageCacheMiss);
        connect(images, &MailImageHandler::originStarted, this, &MailWebProfile::originImageStarted);
        connect(images, &MailImageHandler::originFinished, this, &MailWebProfile::originImageFinished);
        connect(images, &MailImageHandler::imageReady, this, &MailWebProfile::cachedImageReady);
    }

    bool remoteImages() const { return requests.remoteImages.load(); }
    void setRemoteImages(bool value) { requests.remoteImages.store(value); }

    QStringList localImages() const { return sources; }
    void setLocalImages(const QStringList &value) {
        sources = value;
        QSet<QUrl> urls;
        for (const auto &source : value) {
            const QUrl url(source);
            if (url.scheme() == "tacit-image" && url.host() == "mail") urls.insert(url);
        }
        images->allowed = urls;
        QMutexLocker lock(&requests.mutex);
        requests.localImages = urls;
    }

    ~MailWebProfile() override { setUrlRequestInterceptor(nullptr); }

signals:
    void imageCacheMiss(const QString &url);
    void originImageStarted(const QString &url);
    void originImageFinished(const QString &url, bool ok);
    void cachedImageReady(const QString &url);
private:
    MailImageHandler *images;
    QStringList sources;
    class OfflineRequests : public QWebEngineUrlRequestInterceptor {
    public:
        std::atomic_bool remoteImages{false};
        QMutex mutex;
        QSet<QUrl> localImages;

        void interceptRequest(QWebEngineUrlRequestInfo &info) override
        {
            using Request = QWebEngineUrlRequestInfo;
            const auto type = info.resourceType();
            const bool inlineContent = info.requestUrl().scheme() == QStringLiteral("data")
                && (type == Request::ResourceTypeMainFrame || type == Request::ResourceTypeImage);
            const bool remoteImage = remoteImages.load() && type == Request::ResourceTypeImage
                && info.requestUrl().scheme() == QStringLiteral("https");
            QMutexLocker lock(&mutex);
            const bool localImage = type == Request::ResourceTypeImage && localImages.contains(info.requestUrl());
            info.block(!inlineContent && !remoteImage && !localImage);
        }
    } requests;
};
