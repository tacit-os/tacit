// For tests/graphis-sideways-scroll.test.mjs: a scene (argv[1], with argv[2] on its import path) shown offscreen, and
// wheel events sent to it as Qt's Wayland client makes them (qwaylandinputdevice.cpp), argv[3] as JSON:
// [[phase, synthesized, pixelX, pixelY, angleX, angleY], ...], 16 ms apart. Then the root's "flick" contentX and
// contentY on stdout as JSON, once the scroll animations are done.
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QThread>
#include <QWheelEvent>
#include <cstdio>
int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    QQuickView view;
    view.engine()->addImportPath(QString::fromLocal8Bit(argv[2]));
    view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (view.status() != QQuickView::Ready || !view.rootObject()) {
        for (const auto &e : view.errors()) std::fprintf(stderr, "%s\n", qPrintable(e.toString()));
        return 2;
    }
    view.show();
    app.processEvents();
    const QPointF at(view.width() / 2.0, view.height() / 2.0);
    ulong t = 1000;
    for (const auto &v : QJsonDocument::fromJson(argv[3]).array()) {
        const QJsonArray e = v.toArray();
        const auto phase = Qt::ScrollPhase(e[0].toInt());
        QWheelEvent ev(at, view.mapToGlobal(at), QPoint(e[2].toInt(), e[3].toInt()), QPoint(e[4].toInt(), e[5].toInt()),
                       Qt::NoButton, Qt::NoModifier, phase, false,
                       e[1].toBool() ? Qt::MouseEventSynthesizedBySystem : Qt::MouseEventNotSynthesized);
        ev.setTimestamp(t += 16);
        QCoreApplication::sendEvent(&view, &ev);
        app.processEvents();
        QThread::msleep(16);
        app.processEvents();
    }
    for (int i = 0; i < 60; i++) {   // a second for the easing and Flickable's own timeline
        QThread::msleep(16);
        app.processEvents();
    }
    auto *flick = view.rootObject()->findChild<QQuickItem *>("flick");
    if (!flick) { std::fprintf(stderr, "no flick\n"); return 2; }
    std::printf("{\"x\": %g, \"y\": %g}\n", flick->property("contentX").toReal(), flick->property("contentY").toReal());
    return 0;
}
