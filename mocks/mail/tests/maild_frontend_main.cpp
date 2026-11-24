#include "PreviewMailbox.h"
#include "../frontend/html-engine/mailwebprofile.h"

#include <QFile>
#include <QJsonDocument>
#include <QQmlContext>
#include <QQmlEngine>
#include <QtQuickTest/quicktest.h>
#include <QtWebEngineQuick>

class IntegrationSetup : public QObject {
    Q_OBJECT
public slots:
    void applicationAvailable() { QtWebEngineQuick::initialize(); }
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        QFile contract(qEnvironmentVariable("TACIT_MAIL_TEST_CONTRACT"));
        if (!contract.open(QIODevice::ReadOnly)) qFatal("Cannot open list contract fixture");
        engine->rootContext()->setContextProperty("testListContract", QJsonDocument::fromJson(contract.readAll()).object().toVariantMap());
        engine->rootContext()->setContextProperty("testMailbox", &mailbox);
        engine->rootContext()->setContextProperty("testPhase", qEnvironmentVariable("TACIT_MAIL_TEST_PHASE"));
    }

private:
    PreviewMailbox mailbox;
};

QUICK_TEST_MAIN_WITH_SETUP(maild_frontend, IntegrationSetup)
#include "maild_frontend_main.moc"
