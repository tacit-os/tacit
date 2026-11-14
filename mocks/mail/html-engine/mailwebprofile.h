#pragma once

#include <QQuickWebEngineProfile>
#include <QUrl>
#include <QWebEngineUrlRequestInfo>
#include <QWebEngineUrlRequestInterceptor>
#include <QtQml/qqmlregistration.h>

class MailWebProfile : public QQuickWebEngineProfile {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit MailWebProfile(QObject *parent = nullptr) : QQuickWebEngineProfile(parent)
    {
        setHttpCacheType(NoCache);
        setUrlRequestInterceptor(&requests);
    }

    ~MailWebProfile() override { setUrlRequestInterceptor(nullptr); }

private:
    class OfflineRequests : public QWebEngineUrlRequestInterceptor {
        void interceptRequest(QWebEngineUrlRequestInfo &info) override
        {
            using Request = QWebEngineUrlRequestInfo;
            const auto type = info.resourceType();
            const bool inlineContent = info.requestUrl().scheme() == QStringLiteral("data")
                && (type == Request::ResourceTypeMainFrame || type == Request::ResourceTypeImage);
            info.block(!inlineContent);
        }
    } requests;
};
