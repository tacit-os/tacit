#pragma once

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUuid>
#include <QSaveFile>
#include <QTemporaryDir>
#include <functional>
#include <memory>
#include <QFutureWatcher>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeDatabase>
#include <QLocale>
#include <QNetworkAccessManager>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QNetworkRequest>
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
#include <QtConcurrentRun>
#include <QtQml/qqmlregistration.h>

class PreviewMailbox : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool enabled READ enabled CONSTANT)

public:
    explicit PreviewMailbox(QObject *parent = nullptr) : QObject(parent)
    {
        network.setProxy(QNetworkProxy::NoProxy);
    }

    Q_INVOKABLE void reconnectInternetAccount(const QString &account, const QString &password)
    {
        requestDocument("POST", "/v1/accounts/" + encode(account) + "/reconnect",
            {{"password", password}}, [this, account](const QJsonDocument &document, bool ok) {
                const auto result = document.object();
                emit internetAccountReconnected(account, ok && result.value("ok").toBool(),
                    result.value("error").toString());
            }, "28");
    }
    Q_INVOKABLE void requestDraftSuggestion(const QString &account, const QString &source, const QString &instruction,
                                            const QString &subject, const QStringList &recipients, bool allAccounts)
    {
        requestDocument("POST", "/v1/agent/draft-suggestion",
            {{"account_id", account}, {"source_id", source}, {"instruction", instruction},
                {"subject", subject}, {"recipients", recipients}, {"all_accounts", allAccounts}},
            [this](const QJsonDocument &document, bool ok) {
                const auto result = document.object();
                emit draftSuggestionReady(ok ? result.value("draft").toString() : QString{},
                    result.value("error").toString());
            }, "128");
    }
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

    Q_INVOKABLE bool syncInbox(const QString &account)
    {
        if (syncingAccounts.contains(account))
            return false;
        syncingAccounts.insert(account);
        syncInboxPage(account, true);
        return true;
    }

private:
    QSet<QString> syncingAccounts;

    void syncInboxPage(const QString &account, bool initial)
    {
        if (!syncingAccounts.contains(account)) {
            if (initial)
                emit inboxSyncFinished(account, true);
            return;
        }
        if (initial) {
            importInbox(account);
            return;
        }
        requestDocument("POST", "/v1/sync", {{"account_id", account}},
            [this, account, initial](const QJsonDocument &document, bool ok) {
                const auto snapshot = document.object();
                ok = ok && !snapshot.value("google_sign_in_again").toBool();
                if (!ok || !snapshot.value("has_more").toBool())
                    emit accountSyncStatus(account, snapshot.toVariantMap(), ok);
                if (ok && document.isObject()) {
                    const auto result = document.object();
                    if (result.value("received").toInt() > 0)
                        emit mailboxInvalidated();
                    if (result.value("new_unread").toInt() > 0)
                        emit newMailArrived(result.value("new_unread").toInt(),
                            result.value("new_likely_personal").toInt());
                    if (result.value("has_more").toBool()) {
                        QTimer::singleShot(0, this, [this, account, initial] { syncInboxPage(account, initial); });
                        return;
                    }
                }
                QTimer::singleShot(ok ? 0 : 5000, this, [this, account] { watchInbox(account); });
            }, "29");
    }

    void importInbox(const QString &account)
    {
        requestDocument("POST", "/v1/sync/import", {{"account_id", account}},
            [this, account](const QJsonDocument &document, bool ok) {
                const auto end = document.object();
                const bool imported = ok && end.value("done").toBool() && end.value("ok").toBool();
                if (imported && end.value("result").toObject().value("has_more").toBool()) {
                    QTimer::singleShot(0, this, [this, account] { syncInboxPage(account, true); });
                    return;
                }
                const auto snapshot = end.value("result").toObject();
                if (imported || snapshot.value("received").toInt() > 0)
                    emit mailboxInvalidated();
                emit accountSyncStatus(account, snapshot.toVariantMap(), imported);
                emit inboxSyncFinished(account, imported);
                if (!imported && !snapshot.value("google_sign_in_again").toBool()) {
                    QTimer::singleShot(5000, this, [this, account] {
                        if (syncingAccounts.contains(account))
                            importInbox(account);
                    });
                    return;
                }
                QTimer::singleShot(imported ? 0 : 5000, this, [this, account] { watchInbox(account); });
            }, "0", [this, account](const QJsonObject &event) {
                if (event.contains("downloaded"))
                    emit inboxImportProgress(account, event.value("downloaded").toInt(), event.value("total").toInt());
            });
    }

    void watchInbox(const QString &account)
    {
        if (!syncingAccounts.contains(account))
            return;
        requestDocument("POST", "/v1/sync/wait", {{"account_id", account}},
            [this, account](const QJsonDocument &, bool ok) {
                QTimer::singleShot(ok ? 0 : 5000, this, [this, account] {
                    syncInboxPage(account, false);
                });
            }, "25");
    }

public:
    Q_INVOKABLE void loadAccountFolders(const QString &account)
    {
        requestDocument("GET", "/v1/accounts/" + encode(account) + "/folders", {},
            [this, account](const QJsonDocument &document, bool ok) {
                emit accountFoldersLoaded(account, document.object().toVariantMap(), ok);
            }, "28");
    }

    Q_INVOKABLE void saveAccountFolders(const QString &account, const QVariantMap &manual)
    {
        requestDocument("PUT", "/v1/accounts/" + encode(account) + "/folders", {{"manual", manual}},
            [this, account](const QJsonDocument &document, bool ok) {
                emit accountFoldersSaved(account, document.object().toVariantMap(), ok);
            }, "28");
    }
    Q_INVOKABLE void imagePolicy(const QString &messageId, const QString &policy, int revision)
    {
        const auto route = messageId.isEmpty() ? QStringLiteral("/v1/settings/image-policy")
            : QStringLiteral("/v1/messages/") + encode(messageId) + "/image-policy";
        requestJson(policy.isEmpty() ? "GET" : "PUT", route, {{"policy", policy}},
            [this, messageId, policy, revision](const QJsonObject &result, bool ok) {
                emit imagePolicyLoaded(messageId, revision, result.toVariantMap(), ok);
                if (ok && !policy.isEmpty())
                    emit imagePoliciesChanged();
            });
    }

    Q_INVOKABLE int inspectImages(const QString &messageId)
    {
        const int ticket = ++nextImageStateTicket;
        requestJson("GET", "/v1/messages/" + encode(messageId) + "/image-state", {},
            [this, messageId, ticket](const QJsonObject &result, bool ok) {
                emit imageStateLoaded(messageId, ticket, result.toVariantMap(), ok);
            });
        return ticket;
    }

    Q_INVOKABLE void allowMessageImages(const QString &messageId)
    {
        requestJson("POST", "/v1/messages/" + encode(messageId) + "/image-consent", {},
            [this, messageId](const QJsonObject &result, bool ok) {
                emit messageImagesAllowed(messageId, ok && result.value("ok").toBool());
            });
    }

    Q_INVOKABLE void loadAccounts()
    {
        requestDocument("GET", "/v1/accounts", {}, [this](const QJsonDocument &document, bool ok) {
            if (ok && document.isArray()) {
                QSet<QString> active;
                for (const auto &entry : document.array()) {
                    const auto account = entry.toObject();
                    const auto provider = account.value("provider").toString();
                    if (provider == "managed-imap" || provider == "imap-smtp")
                        active.insert(account.value("id").toString());
                }
                syncingAccounts.intersect(active);
            }
            emit accountsLoaded(document.array().toVariantList(), ok && document.isArray());
        });
    }

    Q_INVOKABLE void connectGoogleAccount()
    {
        const int revision = ++googleLoginRevision;
        requestJson("POST", "/v1/oauth/google", {}, [this, revision](const QJsonObject &result, bool ok) {
            const auto id = result.value("id").toString();
            if (revision != googleLoginRevision) {
                cancelGoogleRequest(id);
                return;
            }
            const QUrl url(result.value("url").toString());
            if (!ok || id.isEmpty() || url.scheme() != "https" || url.host() != "accounts.google.com"
                || !QDesktopServices::openUrl(url)) {
                cancelGoogleRequest(id);
                emit internetAccountConnected(false, result.value("error").toString(), {});
                return;
            }
            googleLoginID = id;
            pollGoogleAccount(revision, id);
        });
    }

    Q_INVOKABLE void cancelGoogleAccount()
    {
        ++googleLoginRevision;
        cancelGoogleRequest(googleLoginID);
        googleLoginID.clear();
    }

    Q_INVOKABLE void connectInternetAccount(const QVariantMap &settings)
    {
        requestDocument("POST", "/v1/accounts/imap", settings,
            [this](const QJsonDocument &document, bool ok) {
                const auto result = document.object();
                const bool connected = ok && result.value("account").isObject();
                const auto account = result.value("account").toObject();
                emit internetAccountConnected(connected, result.value("error").toString(),
                    account.value("import_pending").toBool() ? account.value("id").toString() : QString{});
                if (connected) {
                    loadAccounts();
                    emit mailboxInvalidated();
                }
            }, "28");
    }

    Q_INVOKABLE void loadDisconnectSummary(const QString &account)
    {
        requestJson("GET", "/v1/accounts/" + encode(account) + "/disconnect", {},
            [this, account](const QJsonObject &result, bool ok) {
                emit disconnectSummaryLoaded(account, result.toVariantMap(), ok);
            });
    }

    Q_INVOKABLE void disconnectInternetAccount(const QString &account, bool remove)
    {
        std::function<void(const QJsonObject &)> progress;
        if (remove) {
            progress = [this, account](const QJsonObject &event) {
                if (event.contains("removed"))
                    emit internetAccountRemovalProgress(account, event.value("removed").toInt(), event.value("total").toInt());
            };
        }
        requestDocument("POST", "/v1/accounts/" + encode(account) + "/disconnect" + (remove ? "?progress=1" : ""),
            {{"remove_local_copy", remove}}, [this, account, remove](const QJsonDocument &document, bool ok) {
                emit internetAccountDisconnected(account, remove, ok && document.object().value("ok").toBool());
                loadAccounts();
                emit mailboxInvalidated();
            }, remove ? "910" : "28", progress);
    }

    Q_INVOKABLE void loadDrafts(const QString &account, int revision)
    {
        loadPages("/v1/messages?mailbox=Drafts&account_id=" + encode(account), {},
            [this, revision](const QVariantList &messages, bool ok) {
                if (ok) {
                    loadDraftInlineImages(messages, 0, 0, [this, revision](const QVariantList &loaded) {
                        emit draftsLoaded(revision, loaded, true);
                    });
                } else {
                    emit draftsLoaded(revision, {}, false);
                }
            });
    }

    Q_INVOKABLE void loadMailboxCounts(int revision)
    {
        requestDocument("GET", "/v1/mailboxes/counts", {}, [this, revision](const QJsonDocument &document, bool ok) {
            emit mailboxLoaded(revision, document.array().toVariantList(), ok && document.isArray());
        });
    }

    Q_INVOKABLE void loadMailboxView(const QString &account, const QString &mailbox,
                                      const QString &filter, const QString &sort, int revision, const QString &selectedId = {}, const QString &gmailCategory = {})
    {
        latestMailboxRevision = revision;
        const auto route = QStringLiteral("/v1/messages?view=1&account_id=") + encode(account)
            + "&mailbox=" + encode(mailbox) + "&filter=" + encode(filter) + "&sort=" + encode(sort)
            + "&locale=" + encode(QLocale().bcp47Name()) + "&selected_id=" + encode(selectedId)
            + "&gmail_category=" + encode(gmailCategory);
        loadPages(route, {}, [this, revision](const QVariantList &messages, bool ok) {
            emit mailboxLoaded(revision, messages, ok);
        }, [this, revision](const QVariantList &messages) {
            emit mailboxFirstPage(revision, messages);
        }, [this, revision] { return revision == latestMailboxRevision; });
    }

    Q_INVOKABLE void loadThread(const QString &account, const QString &conversation, int revision)
    {
        latestThreadRevision = revision;
        requestThread(account, conversation, [this, revision](const QVariantList &messages, bool ok) {
            if (revision != latestThreadRevision)
                return;
            emit threadLoaded(revision, messages, ok);
            if (ok)
                loadThreadImages(messages, revision);
        });
    }

    Q_INVOKABLE void prefetchThread(const QString &account, const QString &conversation, int ticket)
    {
        requestThread(account, conversation, [this, ticket](const QVariantList &messages, bool ok) {
            emit threadPrefetched(ticket, messages, ok);
            if (ok) {
                loadInlineImages(messages, 0, 0, [this, ticket](const QVariantList &loaded) {
                    emit threadPrefetchImagesLoaded(ticket, loaded);
                });
            }
        });
    }

    Q_INVOKABLE void loadThreadImages(const QVariantList &messages, int revision)
    {
        latestThreadRevision = revision;
        auto pending = std::make_shared<QVariantList>();
        for (const auto &entry : messages) {
            const auto message = entry.toMap();
            if (message.value("body_html").toString().contains("cid:")
                && !message.value("attachments").toList().isEmpty())
                pending->append(entry);
        }
        const auto workers = qMin<qsizetype>(4, pending->size());
        for (qsizetype worker = 0; worker < workers; ++worker)
            loadNextThreadImageMessage(pending, revision);
    }

    Q_INVOKABLE void search(const QString &query, int revision, const QString &filter = QStringLiteral("All mail"))
    {
        latestSearchRevision = revision;
        const auto route = "/v1/messages?view=1&search=1&q=" + encode(query) + "&filter=" + encode(filter) + "&sort=Newest%20first";
        loadPages(route, {}, [this, revision](const QVariantList &messages, bool ok) {
            emit searched(revision, messages, ok);
        }, [this, revision](const QVariantList &messages) {
            emit searchFirstPage(revision, messages);
        }, [this, revision] { return revision == latestSearchRevision; });
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
            [this, id, ids](const QJsonObject &, bool ok) {
                if (ok) emit messagesDeleted(ids);
                emit messageUpdated(id, ok);
            });
    }

    Q_INVOKABLE void deleteTrashedMessage(const QString &id)
    {
        requestJson("DELETE", "/v1/messages/" + encode(id), {},
            [this, id](const QJsonObject &, bool ok) {
                if (ok) emit messagesDeleted(QVariantList{id});
                emit messageUpdated(id, ok);
            });
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
                         const std::function<void(const QJsonDocument &, bool)> &complete,
                         const QString &timeout = QStringLiteral("10"),
                         const std::function<void(const QJsonObject &)> &progress = {})
    {
        auto *reply = localRequest(method, route, changes, timeout.toInt() * 1000);
        const auto lastEvent = std::make_shared<QJsonDocument>();
        const auto readEvents = [reply, lastEvent, progress] {
            while (reply->canReadLine()) {
                const auto event = QJsonDocument::fromJson(reply->readLine());
                if (event.isObject()) {
                    *lastEvent = event;
                    progress(event.object());
                }
            }
        };
        if (progress)
            connect(reply, &QNetworkReply::readyRead, this, readEvents);
        connect(reply, &QNetworkReply::finished, this, [this, reply, complete, progress, readEvents, lastEvent] {
            const bool ok = localReplyOK(reply);
            if (progress) {
                readEvents();
                reply->deleteLater();
                complete(*lastEvent, ok && !lastEvent->isNull());
                return;
            }
            auto body = ok ? reply->readAll() : QByteArray{};
            reply->deleteLater();
            parseDocument(std::move(body), complete);
        });
    }

    QNetworkReply *localRequest(const QString &method, const QString &route,
                                const QVariantMap &changes, int timeoutMs)
    {
        QNetworkRequest request(QUrl(QStringLiteral("unix+http://localhost") + route));
        request.setAttribute(QNetworkRequest::FullLocalServerNameAttribute, socket);
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
        QNetworkReply *reply;
        if (method == "GET") {
            reply = network.get(request);
        } else {
            request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
            reply = network.sendCustomRequest(request, method.toLatin1(),
                QJsonDocument::fromVariant(changes).toJson(QJsonDocument::Compact));
        }
        // Keep an absolute deadline, including for slowly streaming responses.
        if (timeoutMs > 0) {
            QTimer::singleShot(timeoutMs, reply, [reply] {
                if (reply->isRunning())
                    reply->abort();
            });
        }
        return reply;
    }

    static bool localReplyOK(QNetworkReply *reply)
    {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        return reply->error() == QNetworkReply::NoError && status >= 200 && status < 300;
    }

    void parseDocument(QByteArray body, const std::function<void(const QJsonDocument &, bool)> &complete)
    {
        constexpr qsizetype backgroundParseThreshold = 256 * 1024;
        if (body.size() < backgroundParseThreshold) {
            const auto document = QJsonDocument::fromJson(body);
            complete(document, !document.isNull());
            return;
        }
        auto *watcher = new QFutureWatcher<QJsonDocument>(this);
        connect(watcher, &QFutureWatcher<QJsonDocument>::finished, this, [watcher, complete] {
            const auto document = watcher->result();
            watcher->deleteLater();
            complete(document, !document.isNull());
        });
        watcher->setFuture(QtConcurrent::run([body = std::move(body)] {
            return QJsonDocument::fromJson(body);
        }));
    }

    int nextImageStateTicket = 0;
    int latestSearchRevision = 0;
    int latestMailboxRevision = 0;

    void loadPages(const QString &route, QVariantList messages,
                   const std::function<void(const QVariantList &, bool)> &complete,
                   const std::function<void(const QVariantList &)> &firstPage = {},
                   const std::function<bool()> &current = {},
                   const QString &generation = {}, int retries = 2)
    {
        const auto version = generation.isEmpty() ? QString() : "&generation=" + encode(generation);
        requestJson("GET", route + "&limit=100&offset=" + QString::number(messages.size()) + version, {},
            [this, route, messages, complete, firstPage, current, generation, retries](const QJsonObject &page, bool ok) mutable {
                if (current && !current()) return;
                if (!ok || !page.value("messages").isArray()) {
                    if (!generation.isEmpty() && retries > 0) {
                        // A local mutation invalidated the remaining pages. Retry as
                        // one version; never append a new version to an old prefix.
                        loadPages(route, {}, complete, {}, current, {}, retries - 1);
                        return;
                    }
                    complete({}, false);
                    return;
                }
                // Older daemons ignore unknown query parameters. Do not mistake
                // their ungrouped message page for an ordered list-view response.
                if (route.contains("?view=1") && !page.value("generation").isString()) {
                    complete({}, false);
                    return;
                }
                const auto missingId = page.value("missing_id").toString();
                if (!missingId.isEmpty() && messages.isEmpty()) emit messagesDeleted({missingId});
                const auto rows = page.value("messages").toArray().toVariantList();
                messages.append(rows);
                if (!rows.isEmpty() && messages.size() < page.value("total").toInt()) {
                    if (firstPage)
                        firstPage(rows);
                    loadPages(route, std::move(messages), complete, {}, current,
                        page.value("generation").toString(), retries);
                } else {
                    complete(messages, true);
                }
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
    void internetAccountReconnected(const QString &account, bool ok, const QString &error);
    void draftSuggestionReady(const QString &draft, const QString &error);
    void accountSyncStatus(const QString &account, const QVariantMap &result, bool ok);
    void accountFoldersLoaded(const QString &account, const QVariantMap &settings, bool ok);
    void accountFoldersSaved(const QString &account, const QVariantMap &settings, bool ok);
    void internetAccountConnected(bool connected, const QString &error, const QString &account);
    void disconnectSummaryLoaded(const QString &account, const QVariantMap &summary, bool ok);
    void internetAccountDisconnected(const QString &account, bool removed, bool ok);
    void internetAccountRemovalProgress(const QString &account, int removed, int total);
    void conversationTrashed(const QString &token);
    void conversationTrashUndone(bool ok);
    void accountsLoaded(const QVariantList &accounts, bool ok);
    void draftsLoaded(int revision, const QVariantList &messages, bool ok);
    void mailboxFirstPage(int revision, const QVariantList &messages);
    void mailboxLoaded(int revision, const QVariantList &messages, bool ok);
    void threadLoaded(int revision, const QVariantList &messages, bool ok);
    void threadPrefetched(int ticket, const QVariantList &messages, bool ok);
    void threadPrefetchImagesLoaded(int ticket, const QVariantList &messages);
    void threadMessageLoaded(int revision, const QVariantMap &message);
    void demoMailReceived(bool ok);
    void searchFirstPage(int revision, const QVariantList &messages);
    void searched(int revision, const QVariantList &messages, bool ok);
    void failed();
    void outboxChanged(const QVariantMap &job);
    void sendRejected(const QString &draftId);
    void messageImagesAllowed(const QString &messageId, bool ok);
    void imagePolicyLoaded(const QString &messageId, int revision, const QVariantMap &result, bool ok);
    void imagePoliciesChanged();
    void imageStateLoaded(const QString &messageId, int ticket, const QVariantMap &result, bool ok);
    void mailboxInvalidated();
    void inboxSyncFinished(const QString &account, bool ok);
    void inboxImportProgress(const QString &account, int downloaded, int total);
    void newMailArrived(int unread, int likelyPersonal);
    void messagesDeleted(const QVariantList &ids);
    void messageUpdated(const QString &id, bool ok);
    void attachmentFetched(const QString &messageId, const QString &attachmentId, const QUrl &localUrl);
    void attachmentSaved(const QString &messageId, const QString &attachmentId, bool ok);
    void draftSaved(const QString &localId, const QString &remoteId);

private:
    int googleLoginRevision = 0;
    QString googleLoginID;

    void cancelGoogleRequest(const QString &id)
    {
        if (!id.isEmpty())
            requestJson("DELETE", "/v1/oauth/google/" + encode(id), {}, [](const QJsonObject &, bool) {});
    }

    void pollGoogleAccount(int revision, const QString &id)
    {
        if (revision != googleLoginRevision)
            return;
        requestJson("GET", "/v1/oauth/google/" + encode(id), {},
            [this, revision, id](const QJsonObject &result, bool ok) {
                if (revision != googleLoginRevision)
                    return;
                if (ok && result.value("status").toString() == "pending") {
                    QTimer::singleShot(750, this, [this, revision, id] { pollGoogleAccount(revision, id); });
                    return;
                }
                googleLoginID.clear();
                const auto account = result.value("account").toObject();
                const bool connected = ok && !account.isEmpty();
                emit internetAccountConnected(connected, result.value("error").toString(),
                    account.value("import_pending").toBool() ? account.value("id").toString() : QString{});
                if (connected) {
                    loadAccounts();
                    emit mailboxInvalidated();
                }
            });
    }

    void requestThread(const QString &account, const QString &conversation,
                       const std::function<void(const QVariantList &, bool)> &complete)
    {
        const auto route = QStringLiteral("/v1/conversations/") + encode(conversation)
            + "?account_id=" + encode(account);
        requestDocument("GET", route, {}, [this, complete](const QJsonDocument &document, bool ok) {
            if (!ok || !document.isArray()) { complete({}, false); return; }
            loadInlineImages(document.array().toVariantList(), 0, 0,
                [complete](const QVariantList &messages) { complete(messages, true); });
        }, "5");
    }

    int latestThreadRevision = 0;

    void loadNextThreadImageMessage(const std::shared_ptr<QVariantList> &pending, int revision)
    {
        if (revision != latestThreadRevision || pending->isEmpty())
            return;
        const auto entry = pending->takeLast();
        loadInlineImages({entry}, 0, 0, [this, pending, revision, entry](const QVariantList &loaded) {
            if (revision != latestThreadRevision)
                return;
            if (loaded.first() != entry)
                emit threadMessageLoaded(revision, loaded.first().toMap());
            QTimer::singleShot(0, this, [this, pending, revision] {
                loadNextThreadImageMessage(pending, revision);
            });
        });
    }

    void loadInlineImages(QVariantList messages, qsizetype row, qsizetype firstFile,
                          const std::function<void(const QVariantList &)> &complete)
    {
        Q_UNUSED(firstFile);
        for (; row < messages.size(); ++row) {
            auto message = messages[row].toMap();
            const auto html = message.value("body_html").toString();
            auto files = message.value("attachments").toList();
            for (auto &entry : files) {
                auto file = entry.toMap();
                const auto id = file.value("id").toString();
                if (!file.value("media_type").toString().startsWith("image/") || !html.contains("cid:" + id))
                    continue;
                file.insert("inline", true);
                file.insert("inlineSource", QStringLiteral("tacit-image://mail/v1/messages/%1/attachments/%2")
                    .arg(encode(message.value("id").toString()), encode(id)));
                entry = file;
            }
            message.insert("attachments", files);
            messages[row] = message;
        }
        complete(messages);
    }

    void loadDraftInlineImages(QVariantList messages, qsizetype row, qsizetype firstFile,
                          const std::function<void(const QVariantList &)> &complete)
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
                const auto path = QStringLiteral("/v1/messages/%1/attachments/%2")
                    .arg(encode(message.value("id").toString()), encode(id));
                auto *reply = localRequest(QStringLiteral("GET"), path, {}, 5000);
                constexpr qint64 maxBytes = 20 * 1024 * 1024;
                connect(reply, &QNetworkReply::readyRead, this, [reply] {
                    const auto contentLength = reply->header(QNetworkRequest::ContentLengthHeader).toLongLong();
                    if (contentLength > maxBytes || reply->bytesAvailable() > maxBytes)
                        reply->abort();
                });
                connect(reply, &QNetworkReply::finished, this,
                    [this, reply, messages, row, index, message, html, reference, type, complete]() mutable {
                        if (localReplyOK(reply) && reply->bytesAvailable() <= maxBytes) {
                            const auto uri = QStringLiteral("data:") + type + ";base64,"
                                + QString::fromLatin1(reply->readAll().toBase64());
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
                        reply->deleteLater();
                        loadDraftInlineImages(std::move(messages), row, index + 1, complete);
                    });
                return;
            }
        }
        complete(messages);
    }

    QNetworkAccessManager network;
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

