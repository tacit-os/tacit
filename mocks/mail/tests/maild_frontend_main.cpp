#include "PreviewMailbox.h"

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
        engine->rootContext()->setContextProperty("testMailbox", &mailbox);
        engine->rootContext()->setContextProperty("testPhase", qEnvironmentVariable("TACIT_MAIL_TEST_PHASE"));
    }

private:
    PreviewMailbox mailbox;
};

QUICK_TEST_MAIN_WITH_SETUP(maild_frontend, IntegrationSetup)
#include "maild_frontend_main.moc"
