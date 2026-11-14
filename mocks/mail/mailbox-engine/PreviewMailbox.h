#pragma once

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUuid>
#include <QSaveFile>
#include <QTemporaryDir>
#include <functional>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeDatabase>
#include <QObject>
#include <QProcess>
#include <QRegularExpression>
#include <QCryptographicHash>
#include <QStandardPaths>
#include <QSet>
#include <QTimer>
#include <QUrl>
#include <QVariant>
#include <QUuid>
#include <QtQml/qqmlregistration.h>

class PreviewMailbox : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool enabled READ enabled CONSTANT)

public:
    bool enabled() const { return !socket.isEmpty(); }

    void receiveDemoMail()
    {
        requestDocument("GET", "/v1/accounts", {}, [this](const QJsonDocument &accounts, bool ok) {
            if (!ok || accounts.array().isEmpty()) {
                emit demoMailReceived(false);
                return;
            }
            const auto account = accounts.array().first().toObject().value("id").toString();
            const auto id = QUuid::createUuid().toString(QUuid::WithoutBraces);
            const QVariantMap message{{"remote_id", id}, {"conversation_id", id},
                {"from", QVariantMap{{"name", "Moss Studio"}, {"email", "moss.studio@example.com"}}},
                {"subject", "A new message from maild"}, {"body_text", "This message arrived through the local demo provider."},
                {"unread", true}};
            requestJson("POST", "/v1/mock/incoming", {{"account_id", account}, {"message", message}},
                [this, account](const QJsonObject &, bool queued) {
                    if (!queued) {
                        emit demoMailReceived(false);
                        return;
                    }
                    requestJson("POST", "/v1/sync", {{"account_id", account}}, [this](const QJsonObject &, bool synced) {
                        if (synced)
                            emit mailboxInvalidated();
                        emit demoMailReceived(synced);
                    });
                });
        });
    }

    Q_INVOKABLE void loadAccounts()
    {
        requestDocument("GET", "/v1/accounts", {}, [this](const QJsonDocument &document, bool ok) {
            emit accountsLoaded(document.array().toVariantList(), ok && document.isArray());
        });
    }

    Q_INVOKABLE void loadDrafts(const QString &account, int revision)
    {
        loadPages("/v1/messages?mailbox=Drafts&account_id=" + encode(account), {},
            [this, revision](const QVariantList &messages, bool ok) {
                if (ok)
                    loadInlineImages(messages, 0, 0, revision, DraftList);
                else
                    emit draftsLoaded(revision, {}, false);
            });
    }

    Q_INVOKABLE void loadMailbox(const QString &account, const QString &mailbox, int revision)
    {
        const auto route = QStringLiteral("/v1/messages?account_id=") + encode(account)
            + "&mailbox=" + encode(mailbox);
        loadPages(route, {}, [this, revision](const QVariantList &messages, bool ok) {
            emit mailboxLoaded(revision, messages, ok);
        });
    }

    Q_INVOKABLE void loadThread(const QString &account, const QString &conversation, int revision)
    {
        auto *request = new QProcess(this);
        connect(request, &QProcess::finished, this, [this, request, revision](int code, QProcess::ExitStatus status) {
            const auto document = QJsonDocument::fromJson(request->readAllStandardOutput());
            request->deleteLater();
            if (status != QProcess::NormalExit || code != 0 || !document.isArray()) {
                emit threadLoaded(revision, {}, false);
                return;
            }
            loadInlineImages(document.array().toVariantList(), 0, 0, revision, Thread);
        });
        const auto route = QStringLiteral("http://localhost/v1/conversations/%1?account_id=%2")
            .arg(QString::fromLatin1(QUrl::toPercentEncoding(conversation)),
                 QString::fromLatin1(QUrl::toPercentEncoding(account)));
        request->start(curlExecutable, {"--disable", "--noproxy", "*", "--fail", "--silent", "--max-time", "5",
            "--unix-socket", socket, route});
    }

    Q_INVOKABLE void search(const QString &query, const QString &account, const QString &folder, int revision)
    {
        const auto route = "/v1/messages?q=" + encode(query) + "&account_id=" + encode(account)
            + "&mailbox=" + encode(folder == "Starred" || folder == "Family" || folder == "Receipts"
                || folder == "Clients" || folder == "Invoices" ? QString{} : folder);
        loadPages(route, {}, [this, revision](const QVariantList &messages, bool ok) {
            emit searched(revision, messages, ok);
        });
    }

    Q_INVOKABLE void saveDraft(const QString &localId, const QString &remoteId, QVariantMap draft)
    {
        auto files = draft.take("local_files").toList();
        const auto html = draft.value("body_html").toString();
        static const QRegularExpression imageSource(
            QStringLiteral("<img[^>]* src=\"(data:(image/(gif|png|jpeg|webp));base64,([A-Za-z0-9+/=]+))\""),
            QRegularExpression::CaseInsensitiveOption);
        auto matches = imageSource.globalMatch(html);
        QSet<QString> seen;
        while (matches.hasNext()) {
            const auto match = matches.next();
            const auto source = match.captured(1);
            if (seen.contains(source))
                continue;
            seen.insert(source);
            const auto bytes = QByteArray::fromBase64(match.captured(4).toLatin1());
            const auto digest = QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex();
            const auto before = html.left(match.capturedStart());
            const auto anchor = before.lastIndexOf(QStringLiteral("<a href=\"tacit-attachment:"));
            bool matchedFile = false;
            if (anchor >= 0 && before.endsWith('>') && before.indexOf('>', anchor) == before.size() - 1) {
                const auto idStart = anchor + QStringLiteral("<a href=\"tacit-attachment:").size();
                const auto id = before.mid(idStart, before.size() - idStart - 2);
                for (auto &entry : files) {
                    auto file = entry.toMap();
                    if (file.value("id").toString() == id) {
                        file.insert("source", source);
                        entry = file;
                        matchedFile = true;
                        break;
                    }
                }
            }
            if (matchedFile)
                continue;
            files.append(QVariantMap{{"id", QString::fromLatin1(digest)},
                {"name", "embedded." + match.captured(3)}, {"media_type", match.captured(2)},
                {"bytes", bytes}, {"source", source}});
        }
        uploadDraftFiles(localId, remoteId, draft, files, 0);
    }

    Q_INVOKABLE void sendDraft(const QString &id, int undoSeconds)
    {
        requestJson("POST", "/v1/send", {{"draft_id", id}, {"idempotency_key", QUuid::createUuid().toString()}, {"undo_seconds", undoSeconds}},
            [this, id](const QJsonObject &job, bool ok) {
                const auto jobId = job.value("id").toString();
                if (!ok || jobId.isEmpty()) {
                    emit sendRejected(id);
                    return;
                }
                publishJob(job.toVariantMap());
                pollJob(jobId);
            });
    }

    Q_INVOKABLE void undoSend(const QString &jobId)
    {
        requestJson("POST", "/v1/outbox/" + encode(jobId) + "/undo", {},
            [this, jobId](const QJsonObject &, bool ok) {
                if (ok)
                    pollJob(jobId);
                else
                    emit failed();
            });
    }

    Q_INVOKABLE void retrySend(const QString &jobId)
    {
        requestJson("POST", "/v1/outbox/" + encode(jobId) + "/retry", {},
            [this, jobId](const QJsonObject &, bool ok) {
                if (ok)
                    pollJob(jobId);
                else
                    emit failed();
            });
    }

    Q_INVOKABLE void loadOutbox()
    {
        requestJson("GET", "/v1/outbox", {}, [this](const QJsonObject &page, bool ok) {
            if (!ok) {
                emit failed();
                return;
            }
            for (const auto &entry : page.value("jobs").toArray()) {
                const auto job = entry.toObject();
                publishJob(job.toVariantMap());
                const auto state = job.value("state").toString();
                if (state == "queued" || state == "sending")
                    pollJob(job.value("id").toString());
            }
        });
    }

    Q_INVOKABLE void trashConversation(const QString &account, const QString &conversation)
    {
        requestJson("POST", "/v1/conversations/" + encode(conversation) + "/trash",
            {{"account_id", account}}, [this](const QJsonObject &result, bool ok) {
                emit conversationTrashed(ok ? result.value("undo_token").toString() : QString());
            });
    }

    Q_INVOKABLE void undoConversationTrash(const QString &token)
    {
        requestJson("POST", "/v1/conversation-trash/" + encode(token) + "/undo", {},
            [this](const QJsonObject &, bool ok) { emit conversationTrashUndone(ok); });
    }

    Q_INVOKABLE void restoreTrashedThread(const QString &id)
    {
        requestJson("POST", "/v1/messages/" + encode(id) + "/restore-trash-thread", {},
            [this, id](const QJsonObject &, bool ok) { emit messageUpdated(id, ok); });
    }

    Q_INVOKABLE void deleteFolderThread(const QString &id, const QVariantList &ids, bool spam)
    {
        requestJson("POST", "/v1/messages/" + encode(id) + (spam ? "/delete-spam-thread" : "/delete-trash-thread"), {{"ids", ids}},
            [this, id](const QJsonObject &, bool ok) { emit messageUpdated(id, ok); });
    }

    Q_INVOKABLE void deleteTrashedMessage(const QString &id)
    {
        requestJson("DELETE", "/v1/messages/" + encode(id), {},
            [this, id](const QJsonObject &, bool ok) { emit messageUpdated(id, ok); });
    }

    Q_INVOKABLE void updateMessage(const QString &id, const QVariantMap &changes)
    {
        requestJson("PATCH", "/v1/messages/" + encode(id), changes,
            [this, id](const QJsonObject &, bool ok) {
                emit messageUpdated(id, ok);
                if (!ok)
                    emit failed();
            });
    }

    Q_INVOKABLE void fetchAttachment(const QString &messageId, const QString &attachmentId, const QString &fileName)
    {
        downloadAttachment(messageId, attachmentId, {}, fileName, [this, messageId, attachmentId](const QUrl &url) {
            emit attachmentFetched(messageId, attachmentId, url);
        });
    }

    Q_INVOKABLE void saveAttachment(const QString &messageId, const QString &attachmentId, const QUrl &destination)
    {
        if (!destination.isLocalFile()) {
            emit attachmentSaved(messageId, attachmentId, false);
            return;
        }
        downloadAttachment(messageId, attachmentId, destination, {},
            [this, messageId, attachmentId](const QUrl &url) {
                emit attachmentSaved(messageId, attachmentId, !url.isEmpty());
            });
    }

private:
    static QString encode(const QString &value) { return QString::fromLatin1(QUrl::toPercentEncoding(value)); }

    void requestJson(const QString &method, const QString &route, const QVariantMap &changes,
                     const std::function<void(const QJsonObject &, bool)> &complete)
    {
        requestDocument(method, route, changes, [complete](const QJsonDocument &document, bool ok) {
            complete(document.object(), ok && document.isObject());
        });
    }

    void requestDocument(const QString &method, const QString &route, const QVariantMap &changes,
                         const std::function<void(const QJsonDocument &, bool)> &complete)
    {
        auto *request = new QProcess(this);
        QStringList args{"--disable", "--noproxy", "*", "--fail", "--silent", "--max-time", "10", "--unix-socket", socket, "-X", method};
        if (method != "GET") {
            args << "-H" << "Content-Type: application/json" << "--data-binary" << "@-";
            const auto payload = QJsonDocument::fromVariant(changes).toJson(QJsonDocument::Compact);
            connect(request, &QProcess::started, request, [request, payload] {
                request->write(payload);
                request->closeWriteChannel();
            });
        }
        connect(request, &QProcess::errorOccurred, this, [request, complete](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart) {
                request->deleteLater();
                complete({}, false);
            }
        });
        connect(request, &QProcess::finished, this, [request, complete](int code, QProcess::ExitStatus status) {
            const auto document = QJsonDocument::fromJson(request->readAllStandardOutput());
            request->deleteLater();
            complete(document, status == QProcess::NormalExit && code == 0 && !document.isNull());
        });
        args << "http://localhost" + route;
        request->start(curlExecutable, args);
    }

    void loadPages(const QString &route, QVariantList messages,
                   const std::function<void(const QVariantList &, bool)> &complete)
    {
        requestJson("GET", route + "&limit=100&offset=" + QString::number(messages.size()), {},
            [this, route, messages, complete](const QJsonObject &page, bool ok) mutable {
                if (!ok || !page.value("messages").isArray()) {
                    complete({}, false);
                    return;
                }
                const auto rows = page.value("messages").toArray().toVariantList();
                messages.append(rows);
                if (!rows.isEmpty() && messages.size() < page.value("total").toInt())
                    loadPages(route, std::move(messages), complete);
                else
                    complete(messages, true);
            });
    }

    void publishJob(const QVariantMap &job)
    {
        const auto id = job.value("id").toString();
        if (id.isEmpty() || knownJobs.value(id) == job)
            return;
        knownJobs.insert(id, job);
        emit outboxChanged(job);
    }

    void pollJob(const QString &id)
    {
        if (pollingJobs.contains(id))
            return;
        pollingJobs.insert(id);
        requestJson("GET", "/v1/outbox/" + encode(id), {},
            [this, id](const QJsonObject &job, bool ok) {
                pollingJobs.remove(id);
                if (!ok) {
                    emit failed();
                    return;
                }
                publishJob(job.toVariantMap());
                const auto state = job.value("state").toString();
                if (state == "queued" || state == "sending")
                    QTimer::singleShot(250, this, [this, id] { pollJob(id); });
                else {
                    emit mailboxInvalidated();
                }
            });
    }

    void downloadAttachment(const QString &messageId, const QString &attachmentId, const QUrl &destination,
                            const QString &fileName, const std::function<void(const QUrl &)> &complete)
    {
        if (!attachmentCache.isValid() || messageId.isEmpty() || attachmentId.isEmpty()) {
            complete({});
            return;
        }
        // Use an isolated folder per transfer and let curl derive no path from the server response.
        const auto directory = attachmentCache.filePath(QUuid::createUuid().toString(QUuid::WithoutBraces));
        if (!QDir().mkpath(directory)) {
            complete({});
            return;
        }
        const auto base = QFileInfo(fileName).fileName();
        const auto path = QDir(directory).filePath(
            base.isEmpty() || base == "." || base == ".." ? "attachment" : base);
        auto *request = new QProcess(this);
        connect(request, &QProcess::errorOccurred, this, [request, complete](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart) {
                request->deleteLater();
                complete({});
            }
        });
        connect(request, &QProcess::finished, this,
            [request, path, destination, complete](int code, QProcess::ExitStatus status) {
                request->deleteLater();
                if (status != QProcess::NormalExit || code != 0) {
                    QFile::remove(path);
                    complete({});
                    return;
                }
                if (destination.isEmpty()) {
                    complete(QUrl::fromLocalFile(path));
                    return;
                }
                QFile source(path);
                QSaveFile target(destination.toLocalFile());
                bool ok = source.open(QIODevice::ReadOnly) && target.open(QIODevice::WriteOnly);
                while (ok && !source.atEnd()) {
                    const auto bytes = source.read(64 * 1024);
                    ok = source.error() == QFileDevice::NoError && target.write(bytes) == bytes.size();
                }
                ok = ok && target.commit();
                source.close();
                QFile::remove(path);
                complete(ok ? destination : QUrl());
            });
        request->start(curlExecutable, {"--disable", "--noproxy", "*", "--fail", "--silent", "--max-time", "120",
            "--unix-socket", socket, "--output", path,
            "http://localhost/v1/messages/" + encode(messageId) + "/attachments/" + encode(attachmentId)});
    }

    void uploadDraftFiles(const QString &localId, const QString &remoteId, QVariantMap draft,
                          const QVariantList &files, qsizetype index)
    {
        if (index == files.size()) {
            writeDraft(localId, remoteId, draft);
            return;
        }
        const auto file = files[index].toMap();
        const auto filename = file.value("name").toString();
        const auto localFile = QUrl(file.value("url").toString()).toLocalFile();
        const auto account = draft.value("account_id").toString();
        const auto key = localId + "/" + account + "/" + file.value("id").toString();
        auto append = [this, localId, remoteId, draft, files, index, file](const QString &id) mutable {
            auto attachments = draft.value("attachments").toList();
            const auto source = file.value("source").toString();
            if (!source.isEmpty()) {
                auto html = draft.value("body_html").toString();
                html.replace(source, "cid:" + id);
                draft.insert("body_html", html);
            }
            attachments.append(QVariantMap{{"id", id}});
            draft.insert("attachments", attachments);
            uploadDraftFiles(localId, remoteId, draft, files, index + 1);
        };
        if (uploadedFiles.contains(key)) {
            auto next = append;
            next(uploadedFiles.value(key));
            return;
        }
        const auto bytes = file.value("bytes").toByteArray();
        if (localFile.isEmpty() && bytes.isEmpty()) {
            emit draftSaved(localId, {});
            return;
        }
        auto *request = new QProcess(this);
        connect(request, &QProcess::finished, this, [this, request, localId, key, append](int code, QProcess::ExitStatus status) mutable {
            const auto id = QJsonDocument::fromJson(request->readAllStandardOutput()).object().value("id").toString();
            request->deleteLater();
            if (status != QProcess::NormalExit || code != 0 || id.isEmpty()) {
                emit draftSaved(localId, {});
                return;
            }
            uploadedFiles.insert(key, id);
            append(id);
        });
        const auto type = localFile.isEmpty() ? file.value("media_type").toString()
                                               : QMimeDatabase().mimeTypeForFile(localFile).name();
        if (localFile.isEmpty()) {
            connect(request, &QProcess::started, request, [request, bytes] {
                request->write(bytes);
                request->closeWriteChannel();
            });
        } else {
            request->setStandardInputFile(localFile);
        }
        request->start(curlExecutable, {
            "--disable", "--noproxy", "*", "--fail", "--silent", "--max-time", "120", "--unix-socket", socket,
            "-H", "Content-Type: " + type, "--data-binary", "@-",
            "http://localhost/v1/accounts/" + account + "/attachments?filename="
                + QString::fromLatin1(QUrl::toPercentEncoding(filename))
        });
    }

    void writeDraft(const QString &localId, const QString &remoteId, const QVariantMap &draft)
    {
        auto *request = new QProcess(this);
        connect(request, &QProcess::finished, this, [this, request, localId](int code, QProcess::ExitStatus status) {
            const auto id = QJsonDocument::fromJson(request->readAllStandardOutput()).object().value("id").toString();
            emit draftSaved(localId, status == QProcess::NormalExit && code == 0 ? id : QString());
            request->deleteLater();
        });
        const auto payload = QJsonDocument::fromVariant(draft).toJson(QJsonDocument::Compact);
        connect(request, &QProcess::started, request, [request, payload] {
            request->write(payload);
            request->closeWriteChannel();
        });
        const auto url = QStringLiteral("http://localhost/v1/drafts")
            + (remoteId.isEmpty() ? QString() : "/" + QString::fromLatin1(QUrl::toPercentEncoding(remoteId)));
        request->start(curlExecutable, {
            "--disable", "--noproxy", "*", "--fail", "--silent", "--max-time", "10", "--unix-socket", socket,
            "-X", remoteId.isEmpty() ? "POST" : "PUT", "-H", "Content-Type: application/json",
            "--data-binary", "@-", url
        });
    }

signals:
    void conversationTrashed(const QString &token);
    void conversationTrashUndone(bool ok);
    void accountsLoaded(const QVariantList &accounts, bool ok);
    void draftsLoaded(int revision, const QVariantList &messages, bool ok);
    void mailboxLoaded(int revision, const QVariantList &messages, bool ok);
    void threadLoaded(int revision, const QVariantList &messages, bool ok);
    void demoMailReceived(bool ok);
    void searched(int revision, const QVariantList &messages, bool ok);
    void failed();
    void outboxChanged(const QVariantMap &job);
    void sendRejected(const QString &draftId);
    void mailboxInvalidated();
    void messageUpdated(const QString &id, bool ok);
    void attachmentFetched(const QString &messageId, const QString &attachmentId, const QUrl &localUrl);
    void attachmentSaved(const QString &messageId, const QString &attachmentId, bool ok);
    void draftSaved(const QString &localId, const QString &remoteId);

private:
    enum ImageTarget { Thread, DraftList };

    void loadInlineImages(QVariantList messages, qsizetype row, qsizetype firstFile,
                          int revision, ImageTarget target)
    {
        for (; row < messages.size(); ++row, firstFile = 0) {
            auto message = messages[row].toMap();
            auto html = message.value("body_html").toString();
            const auto files = message.value("attachments").toList();
            for (auto index = firstFile; index < files.size(); ++index) {
                const auto file = files[index].toMap();
                const auto id = file.value("id").toString();
                const auto reference = QRegularExpression(QStringLiteral("cid:")
                    + QRegularExpression::escape(id) + QStringLiteral("(?=[\"'\\s)>]|$)"));
                const auto type = file.value("media_type").toString();
                if (!html.contains(reference) || !QStringList{"image/gif", "image/png", "image/jpeg", "image/webp"}.contains(type))
                    continue;
                auto *request = new QProcess(this);
                connect(request, &QProcess::finished, this,
                    [this, request, messages, row, index, message, html, reference, type, revision, target](int code, QProcess::ExitStatus status) mutable {
                        if (status == QProcess::NormalExit && code == 0) {
                            const auto uri = QStringLiteral("data:") + type + ";base64,"
                                + QString::fromLatin1(request->readAllStandardOutput().toBase64());
                            html.replace(reference, uri);
                            message.insert("body_html", html);
                            auto files = message.value("attachments").toList();
                            auto file = files[index].toMap();
                            file.insert("inline", true);
                            file.insert("inlineSource", uri);
                            files[index] = file;
                            message.insert("attachments", files);
                            messages[row] = message;
                        }
                        request->deleteLater();
                        loadInlineImages(std::move(messages), row, index + 1, revision, target);
                    });
                const auto path = QStringLiteral("http://localhost/v1/messages/%1/attachments/%2")
                    .arg(QString::fromLatin1(QUrl::toPercentEncoding(message.value("id").toString())),
                         QString::fromLatin1(QUrl::toPercentEncoding(id)));
                request->start(curlExecutable, {
                    "--disable", "--noproxy", "*", "--fail", "--silent", "--max-time", "5", "--max-filesize", "20971520",
                    "--unix-socket", socket, path
                });
                return;
            }
        }
        switch (target) {
        case DraftList: emit draftsLoaded(revision, messages, true); break;
        case Thread: emit threadLoaded(revision, messages, true); break;
        }
    }

    QTemporaryDir attachmentCache;
    QHash<QString, QVariantMap> knownJobs;
    QSet<QString> pollingJobs;
    QHash<QString, QString> uploadedFiles;
    const QString curlExecutable = QStandardPaths::findExecutable(QStringLiteral("curl"));
    const QString socket = qEnvironmentVariable("TACIT_MAIL_SOCKET",
        QDir(qEnvironmentVariable("XDG_RUNTIME_DIR",
            QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)))
            .filePath("tacit-mail-mock/mail.sock"));
};

