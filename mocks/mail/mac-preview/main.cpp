#include "PreviewMailbox.h"
#include <QApplication>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMenuBar>
#include <QMimeDatabase>
#include <QHash>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <QtWebEngineQuick>

#include <memory>

void installMacWindowMaterial(QQuickWindow &window, qreal radius);
void dragMacWindow(QQuickWindow &window);
void setMacPointingCursor(bool pointing);

class PreviewWindow : public QQuickWindow {
    Q_OBJECT

public:
    Q_INVOKABLE void dragBackground() { dragMacWindow(*this); }
    Q_INVOKABLE void setPointingCursor(bool pointing) { setMacPointingCursor(pointing); }
};

class PreviewFiles : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    QString error() const { return message; }

    Q_INVOKABLE bool copy(const QUrl &source, const QUrl &destination)
    {
        QFile input(source.toLocalFile());
        QSaveFile output(destination.toLocalFile());
        if (!input.open(QIODevice::ReadOnly))
            return fail(input.errorString());
        if (!output.open(QIODevice::WriteOnly))
            return fail(output.errorString());

        while (!input.atEnd()) {
            const auto bytes = input.read(64 * 1024);
            if (bytes.isEmpty() && input.error() != QFileDevice::NoError)
                return fail(input.errorString());
            if (output.write(bytes) != bytes.size())
                return fail(output.errorString());
        }
        return output.commit() || fail(output.errorString());
    }

signals:
    void errorChanged();

private:
    bool fail(const QString &error)
    {
        message = error;
        emit errorChanged();
        return false;
    }

    QString message;
};

static QVariantMap readJson(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).toVariant().toMap();
}

int main(int argc, char *argv[])
{
    QtWebEngineQuick::initialize();
    QApplication app(argc, argv);
    QQuickStyle::setStyle("Basic");
    const QDir source(PREVIEW_SOURCE_DIR);
    const QDir mail(source.absoluteFilePath(".."));
    const QDir imports(PREVIEW_IMPORT_DIR);
    const auto palettePath = [&](const QString &name) {
        return name == "dusk" || name == "moss" ? imports.filePath(name + ".json")
                                                : QFileInfo(name).absoluteFilePath();
    };
    auto palette = palettePath(qEnvironmentVariable("MAIL_PALETTE", "dusk"));

    QQuickWindow::setDefaultAlphaBuffer(true);
    PreviewWindow window;
    window.setColor(Qt::transparent);
    window.setTitle(QStringLiteral("Tacit Mail · Mac preview"));
    window.setMinimumSize(QSize(400, 400));
    window.resize(1320, 780);

    PreviewFiles files;
    PreviewMailbox mailbox;
    std::unique_ptr<QQmlEngine> engine;
    std::unique_ptr<QQuickItem> scene;
    const auto resizeScene = [&] {
        if (scene)
            scene->setSize(QSizeF(window.width(), window.height()));
    };
    QObject::connect(&window, &QWindow::widthChanged, &window, resizeScene);
    QObject::connect(&window, &QWindow::heightChanged, &window, resizeScene);

    const auto loadScene = [&](bool keepState) {
        auto nextEngine = std::make_unique<QQmlEngine>();
        nextEngine->addImportPath(imports.absolutePath());
        auto *context = nextEngine->rootContext();
        context->setContextProperty("previewFiles", &files);
        context->setContextProperty("previewMailbox", &mailbox);
        context->setContextProperty("previewWindow", &window);
        context->setContextProperty("previewPalette", readJson(palette));
        context->setContextProperty("previewScale",
            readJson(QFileInfo(palette).dir().filePath("seethrough.json")).value("scale", 1.0));

        QQmlComponent component(nextEngine.get(), QUrl::fromLocalFile(source.filePath("PreviewScene.qml")));
        std::unique_ptr<QObject> object(component.create());
        auto *next = qobject_cast<QQuickItem *>(object.get());
        if (!next) {
            qWarning().noquote() << component.errorString();
            return false;
        }

        if (scene && keepState) {
            QVariant state;
            QMetaObject::invokeMethod(scene.get(), "snapshot", Q_RETURN_ARG(QVariant, state));
            if (state.isValid())
                QMetaObject::invokeMethod(next, "restore", Q_ARG(QVariant, state));
        }
        object.release();
        scene.reset(next);
        engine = std::move(nextEngine);
        scene->setParentItem(window.contentItem());
        resizeScene();
        scene->forceActiveFocus();
        return true;
    };

    QFileSystemWatcher watcher;
    const auto refreshWatch = [&] {
        QStringList paths{source.absolutePath(), mail.absolutePath(), QFileInfo(palette).absolutePath()};
        const auto addFiles = [&](const QDir &dir) {
            for (const auto &name : dir.entryList({"*.qml", "*.js"}, QDir::Files))
                paths.append(dir.absoluteFilePath(name));
        };
        addFiles(source);
        addFiles(mail);
        for (const auto &path : {palette, QFileInfo(palette).dir().absoluteFilePath("seethrough.json")}) {
            if (QFileInfo::exists(path))
                paths.append(path);
        }
        paths.removeDuplicates();
        const auto current = watcher.files() + watcher.directories();
        for (const auto &path : current) {
            if (!paths.contains(path))
                watcher.removePath(path);
        }
        for (const auto &path : paths) {
            if (!current.contains(path))
                watcher.addPath(path);
        }
    };

    QTimer debounce;
    debounce.setInterval(150);
    debounce.setSingleShot(true);
    QObject::connect(&watcher, &QFileSystemWatcher::fileChanged, &debounce, qOverload<>(&QTimer::start));
    QObject::connect(&watcher, &QFileSystemWatcher::directoryChanged, &debounce, qOverload<>(&QTimer::start));
    QObject::connect(&debounce, &QTimer::timeout, &window, [&] {
        refreshWatch();
        if (loadScene(true))
            qInfo("Reloaded Tacit Mail QML");
    });

    if (!loadScene(false))
        return 1;
    if (app.arguments().contains("--check"))
        return 0;
    refreshWatch();

    QMenuBar menuBar;
    auto *preview = menuBar.addMenu(QObject::tr("Preview"));
    const auto simulate = [&](const QString &label, const QString &action) {
        preview->addAction(label, &window, [&, action] {
            QMetaObject::invokeMethod(scene.get(), "simulate", Q_ARG(QVariant, QVariant(action)));
        });
    };
    preview->addAction(QObject::tr("Receive demo mail"), &mailbox, &PreviewMailbox::receiveDemoMail);
    simulate(QObject::tr("Settings"), "settings");

    auto *palettes = preview->addMenu(QObject::tr("Palette"));
    const auto selectPalette = [&](const QString &name) {
        palette = palettePath(name);
        refreshWatch();
        loadScene(true);
    };
    palettes->addAction(QObject::tr("Dusk"), &window, [&] { selectPalette("dusk"); });
    palettes->addAction(QObject::tr("Moss"), &window, [&] { selectPalette("moss"); });
    palettes->addAction(QObject::tr("Open colors.json…"), &window, [&] {
        const auto path = QFileDialog::getOpenFileName(nullptr, QObject::tr("Open palette"), {}, "JSON (*.json)");
        if (!path.isEmpty())
            selectPalette(path);
    });

    window.show();
    installMacWindowMaterial(window, scene->property("groundRadius").toReal());
    qInfo("Watching Tacit Mail QML and JavaScript");
    return app.exec();
}

#include "main.moc"
