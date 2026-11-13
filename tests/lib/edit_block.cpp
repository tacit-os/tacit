// For tests/edit-block.test.mjs: EditBlock::apply (native/edit) on a TextEdit's own document, offscreen. argv[1] the text,
// argv[2] the edits as JSON ([[start, end, text], ...]); the text after them on stdout.
#include "editblock.h"
#include <QGuiApplication>
#include <QJsonDocument>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickTextDocument>
#include <cstdio>
int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    QQmlEngine engine;
    QQmlComponent c(&engine);
    c.setData("import QtQuick\nTextEdit {}", QUrl());
    auto *item = qobject_cast<QQuickItem *>(c.create());
    if (!item) { std::fprintf(stderr, "%s\n", qPrintable(c.errorString())); return 2; }
    item->setProperty("text", QString::fromUtf8(argv[1]));
    auto *doc = item->property("textDocument").value<QQuickTextDocument *>();
    EditBlock e;
    e.apply(doc, QJsonDocument::fromJson(argv[2]).toVariant().toList());
    std::fputs(qPrintable(e.text(doc)), stdout);
    return 0;
}
