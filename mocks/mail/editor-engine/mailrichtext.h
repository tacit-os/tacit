#pragma once

#include <QAbstractTextDocumentLayout>
#include <QBuffer>
#include <QClipboard>
#include <QFile>
#include <QImage>
#include <QImageReader>
#include <QMimeData>
#include <QMovie>
#include <QHash>
#include <QSet>
#include <QTimer>
#include <QGuiApplication>
#include <QQuickTextDocument>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>
#include <QTextList>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class MailRichText : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickTextDocument *document MEMBER m_document REQUIRED)

public:
    Q_INVOKABLE void setAnimationsPaused(bool paused)
    {
        m_animationsPaused = paused;
        for (auto *movie : m_movies) {
            if (paused && movie->state() == QMovie::Running)
                movie->setPaused(true);
            else if (!paused && movie->state() == QMovie::Paused)
                movie->setPaused(false);
        }
    }

    Q_INVOKABLE void trackAnimations()
    {
        connect(doc(), &QTextDocument::contentsChanged, this, [this] {
            if (!m_refreshPending) {
                m_refreshPending = true;
                QTimer::singleShot(0, this, [this] {
                    m_refreshPending = false;
                    refreshAnimations();
                });
            }
        });
        refreshAnimations();
    }

    Q_INVOKABLE void load(const QString &plain, const QString &html)
    {
        if (html.isEmpty())
            doc()->setPlainText(plain);
        else
            doc()->setHtml(html);
    }

    Q_INVOKABLE QString plainText() const { return doc()->toPlainText(); }

    Q_INVOKABLE QString html() const
    {
        QString result;
        bool rich = false;
        QString listTag;
        for (auto block = doc()->begin(); block.isValid(); block = block.next()) {
            const auto *list = block.textList();
            const QString tag = !list ? QString() : list->format().style() == QTextListFormat::ListDecimal
                ? QStringLiteral("ol") : QStringLiteral("ul");
            if (tag != listTag) {
                if (!listTag.isEmpty()) result += "</" + listTag + ">";
                if (!tag.isEmpty()) result += "<" + tag + ">";
                listTag = tag;
            }
            const auto blockFormat = block.blockFormat();
            QString style = "white-space:pre-wrap;";
            if (blockFormat.alignment() & Qt::AlignHCenter) style += "text-align:center;";
            if (blockFormat.alignment() & Qt::AlignRight) style += "text-align:right;";
            if (blockFormat.indent()) style += "margin-left:" + QString::number(24 * blockFormat.indent()) + "px;";
            else if (blockFormat.leftMargin()) style += "margin-left:" + QString::number(blockFormat.leftMargin()) + "px;";
            const bool quote = blockFormat.hasProperty(QTextFormat::BlockQuoteLevel);
            rich |= list || quote || style != "white-space:pre-wrap;";
            const QString blockTag = list ? "li" : quote ? "blockquote" : "p";
            result += "<" + blockTag + " style=\"" + style + "\">";
            for (auto fragment = block.begin(); !fragment.atEnd(); ++fragment) {
                const auto part = fragment.fragment();
                const auto format = part.charFormat();
                const auto attachment = format.anchorHref();
                const bool inlineAttachment = attachment.startsWith("tacit-attachment:");
                if (inlineAttachment)
                    result += "<a href=\"" + attachment.toHtmlEscaped() + "\">";
                if (format.isImageFormat()) {
                    const auto image = format.toImageFormat();
                    result += "<img src=\"" + image.name().toHtmlEscaped() + "\"";
                    if (image.width() > 0)
                        result += " width=\"" + QString::number(image.width()) + "\"";
                    if (image.height() > 0)
                        result += " height=\"" + QString::number(image.height()) + "\"";
                    result += " alt=\"Embedded image\">";
                    if (inlineAttachment)
                        result += "</a>";
                    auto trailingText = part.text();
                    trailingText.remove(QChar::ObjectReplacementCharacter);
                    result += trailingText.toHtmlEscaped().replace(QChar::LineSeparator, QStringLiteral("<br>"));
                    rich = true;
                    continue;
                }
                auto text = part.text().toHtmlEscaped().replace(QChar::LineSeparator, QStringLiteral("<br>"));
                if (inlineAttachment) {
                    result += "<span style=\"background-color:#51443d;color:#f3e8df\">" + text + "</span></a>";
                    rich = true;
                    continue;
                }
                QString inlineStyle;
                if (format.hasProperty(QTextFormat::FontFamilies))
                    inlineStyle += "font-family:" + format.fontFamilies().toStringList().join(",").toHtmlEscaped() + ";";
                if (format.fontPointSize() > 0)
                    inlineStyle += "font-size:" + QString::number(format.fontPointSize()) + "pt;";
                if (format.foreground().style() != Qt::NoBrush)
                    inlineStyle += "color:" + format.foreground().color().name() + ";";
                if (format.background().style() != Qt::NoBrush)
                    inlineStyle += "background-color:" + format.background().color().name() + ";";
                if (!inlineStyle.isEmpty()) {
                    text = "<span style=\"" + inlineStyle + "\">" + text + "</span>";
                    rich = true;
                }
                if (format.fontUnderline() && !format.isAnchor()) {
                    text = "<u>" + text + "</u>";
                    rich = true;
                }
                if (format.fontStrikeOut()) {
                    text = "<s>" + text + "</s>";
                    rich = true;
                }
                if (format.fontWeight() >= QFont::DemiBold) {
                    text = QStringLiteral("<strong>") + text + QStringLiteral("</strong>");
                    rich = true;
                }
                if (format.fontItalic()) {
                    text = QStringLiteral("<em>") + text + QStringLiteral("</em>");
                    rich = true;
                }
                if (format.isAnchor() && validLink(format.anchorHref())) {
                    text = QStringLiteral("<a href=\"") + format.anchorHref().toHtmlEscaped()
                        + QStringLiteral("\">") + text + QStringLiteral("</a>");
                    rich = true;
                }
                result += text;
            }
            result += "</" + blockTag + ">";
        }
        if (!listTag.isEmpty())
            result += "</" + listTag + ">";
        return rich ? result : QString();
    }

    Q_INVOKABLE bool validLink(const QString &value) const
    {
        const QUrl url(value.trimmed(), QUrl::StrictMode);
        return url.isValid() && !url.host().isEmpty()
            && (url.scheme() == QStringLiteral("https") || url.scheme() == QStringLiteral("http"));
    }

    Q_INVOKABLE QVariantMap linkRange(int start, int end) const
    {
        QString href;
        int linkStart = -1;
        int linkEnd = -1;
        const auto block = doc()->findBlock(start);
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto fragment = it.fragment();
            const auto url = fragment.charFormat().anchorHref();
            const int position = fragment.position();
            if (url != href || position != linkEnd)
                linkStart = position;
            linkEnd = position + fragment.length();
            href = url;
            auto next = it;
            ++next;
            const bool continues = !next.atEnd() && next.fragment().charFormat().anchorHref() == href;
            if (!href.isEmpty() && !continues && start >= linkStart && end <= linkEnd) {
                return {{QStringLiteral("start"), start == end ? linkStart : start},
                        {QStringLiteral("end"), start == end ? linkEnd : end},
                        {QStringLiteral("url"), href}};
            }
        }
        return {{QStringLiteral("start"), start}, {QStringLiteral("end"), end},
                {QStringLiteral("url"), QString()}};
    }

    Q_INVOKABLE int setLink(int start, int end, const QString &value)
    {
        if (!value.isEmpty() && !validLink(value))
            return end;
        auto selected = cursor(start, end);
        QTextCharFormat format;
        format.setAnchor(!value.isEmpty());
        format.setAnchorHref(value.trimmed());
        format.setFontUnderline(!value.isEmpty());
        if (selected.hasSelection())
            selected.mergeCharFormat(format);
        else if (!value.isEmpty())
            selected.insertText(value.trimmed(), format);
        return selected.position();
    }

    Q_INVOKABLE bool isList(int position) const { return cursor(position, position).currentList() != nullptr; }

    Q_INVOKABLE QVariantMap activeFormats(int start, int end) const
    {
        auto selected = cursor(start, end);
        selected.setPosition(start);
        if (start < end)
            selected.movePosition(QTextCursor::NextCharacter);
        const auto format = selected.charFormat();
        const auto block = selected.blockFormat();
        const auto *list = selected.currentList();
        return {{"font", format.hasProperty(QTextFormat::FontFamilies) ? format.fontFamilies().toStringList().value(0) : QString()},
                {"size", format.fontPointSize()},
                {"underline", format.fontUnderline() && !format.isAnchor()},
                {"strike", format.fontStrikeOut()},
                {"color", format.foreground().style() == Qt::NoBrush ? QString() : format.foreground().color().name()},
                {"highlight", format.background().style() == Qt::NoBrush ? QString() : format.background().color().name()},
                {"align", block.alignment() & Qt::AlignRight ? "right" : block.alignment() & Qt::AlignHCenter ? "center" : ""},
                {"numbered", list && list->format().style() == QTextListFormat::ListDecimal},
                {"quote", block.hasProperty(QTextFormat::BlockQuoteLevel)},
                {"indent", block.leftMargin() > 0 || block.indent() > 0}};
    }

    Q_INVOKABLE void formatRange(int start, int end, const QString &action, const QString &value)
    {
        auto selected = cursor(start, end);
        selected.beginEditBlock();
        if (action == "numbered") {
            selected.createList(QTextListFormat::ListDecimal);
        } else if (action == "align" || action == "indent" || action == "quote" || action == "clear") {
            if (action == "clear" && selected.hasSelection())
                selected.setCharFormat(QTextCharFormat());
            const int last = qMax(start, end - 1);
            for (auto block = doc()->findBlock(start); block.isValid() && block.position() <= last; block = block.next()) {
                QTextCursor line(block);
                auto format = block.blockFormat();
                if (action == "align")
                    format.setAlignment(value == "center" ? Qt::AlignHCenter : value == "right" ? Qt::AlignRight : Qt::AlignLeft);
                else if (action == "indent")
                    format.setLeftMargin(qMax(0.0, format.leftMargin() + 24 * value.toInt()));
                else if (action == "quote") {
                    const bool quoted = format.hasProperty(QTextFormat::BlockQuoteLevel);
                    if (quoted) format.clearProperty(QTextFormat::BlockQuoteLevel);
                    else format.setProperty(QTextFormat::BlockQuoteLevel, 1);
                    format.setLeftMargin(quoted ? 0 : 24);
                } else {
                    if (auto *list = block.textList()) list->remove(block);
                    format = QTextBlockFormat();
                }
                line.setBlockFormat(format);
            }
        } else if (selected.hasSelection()) {
            QTextCharFormat format;
            if (action == "underline") format.setFontUnderline(!selected.charFormat().fontUnderline());
            else if (action == "strike") format.setFontStrikeOut(!selected.charFormat().fontStrikeOut());
            else if (action == "font") format.setFontFamilies({value});
            else if (action == "size") format.setFontPointSize(value.toDouble());
            else if (action == "color") format.setForeground(QColor(value));
            else if (action == "highlight") format.setBackground(QColor(value));
            selected.mergeCharFormat(format);
        }
        selected.endEditBlock();
    }

    Q_INVOKABLE void setEmphasis(int start, int end, bool bold, bool enabled)
    {
        auto selected = cursor(start, end);
        if (!selected.hasSelection())
            return;
        QTextCharFormat format;
        if (bold)
            format.setFontWeight(enabled ? QFont::Bold : QFont::Normal);
        else
            format.setFontItalic(enabled);
        selected.mergeCharFormat(format);
    }

    Q_INVOKABLE void toggleList(int start, int end)
    {
        auto selected = cursor(start, end);
        if (selected.hasSelection() && selected.block().position() == end)
            selected.movePosition(QTextCursor::PreviousCharacter, QTextCursor::KeepAnchor);

        selected.beginEditBlock();
        if (cursor(start, start).currentList()) {
            const auto last = selected.block();
            for (auto block = doc()->findBlock(start); block.isValid(); block = block.next()) {
                if (auto *list = block.textList())
                    list->remove(block);
                if (block == last)
                    break;
            }
        } else {
            selected.createList(QTextListFormat::ListDisc);
        }
        selected.endEditBlock();
    }

    Q_INVOKABLE int pasteClipboard(int start, int end, int availableWidth, int availableHeight)
    {
        const auto *clipboard = QGuiApplication::clipboard()->mimeData();
        if (!clipboard)
            return -1;
        QByteArray bytes = clipboard->data("image/gif");
        if (bytes.isEmpty())
            bytes = clipboard->data("application/x-qt-mime-type-name=com.compuserve.gif");
        const auto urls = clipboard->urls();
        if (bytes.isEmpty() && urls.size() == 1 && urls.first().isLocalFile()) {
            const auto path = urls.first().toLocalFile();
            QFile file(path);
            if (path.endsWith(".gif", Qt::CaseInsensitive) && file.size() <= 20 * 1024 * 1024
                && file.open(QIODevice::ReadOnly))
                bytes = file.readAll();
        }
        QString mimeType = QStringLiteral("image/gif");
        QBuffer source(&bytes);
        source.open(QIODevice::ReadOnly);
        QImageReader gif(&source, "gif");
        QSize size = bytes.isEmpty() ? QSize() : gif.size();
        if (!size.isValid() && clipboard->hasImage()) {
            const auto image = qvariant_cast<QImage>(clipboard->imageData());
            bytes.clear();
            QBuffer png(&bytes);
            if (!image.isNull() && png.open(QIODevice::WriteOnly) && image.save(&png, "PNG")) {
                mimeType = QStringLiteral("image/png");
                size = image.size();
            }
        }
        if (size.isValid() && !bytes.isEmpty())
            return insertImage(start, end, availableWidth, availableHeight, mimeType, bytes);
        const auto plain = clipboard->text();
        if (plain.isEmpty())
            return -1;
        auto selected = cursor(start, end);
        selected.insertText(plain);
        return selected.position();
    }

    Q_INVOKABLE int insertAttachment(const QUrl &url, const QString &id, const QString &name,
                                     int position, int availableWidth, int availableHeight)
    {
        auto selected = cursor(position, position);
        const int end = dropImage(url, position, availableWidth, availableHeight);
        if (end >= 0) {
            selected = cursor(end - 2, end - 1);
            auto format = selected.charFormat();
            format.setAnchor(true);
            format.setAnchorHref("tacit-attachment:" + id);
            selected.setCharFormat(format);
            return end;
        }
        QTextCharFormat format;
        format.setAnchor(true);
        format.setAnchorHref("tacit-attachment:" + id);
        format.setBackground(QColor("#51443d"));
        format.setForeground(QColor("#f3e8df"));
        selected.insertText(QStringLiteral(" ") + name + QStringLiteral(" "), format);
        return selected.position();
    }

    Q_INVOKABLE int dropImage(const QUrl &url, int position, int availableWidth, int availableHeight)
    {
        if (!url.isLocalFile())
            return -1;
        QFile file(url.toLocalFile());
        if (!file.open(QIODevice::ReadOnly) || file.size() > 20 * 1024 * 1024)
            return -1;
        const auto bytes = file.read(20 * 1024 * 1024 + 1);
        if (bytes.size() > 20 * 1024 * 1024)
            return -1;
        if (bytes.startsWith("GIF87a") || bytes.startsWith("GIF89a"))
            return insertImage(position, position, availableWidth, availableHeight, "image/gif", bytes);
        const auto image = QImage::fromData(bytes);
        QByteArray pngBytes;
        QBuffer png(&pngBytes);
        if (image.isNull() || !png.open(QIODevice::WriteOnly) || !image.save(&png, "PNG"))
            return -1;
        return insertImage(position, position, availableWidth, availableHeight, "image/png", pngBytes);
    }

    Q_INVOKABLE int insertFormatted(int position, const QString &text, bool bold, bool italic)
    {
        auto selected = cursor(position, position);
        auto format = selected.charFormat();
        format.setFontWeight(bold ? QFont::Bold : QFont::Normal);
        format.setFontItalic(italic);
        selected.insertText(text, format);
        return selected.position();
    }

private:
    int insertImage(int start, int end, int availableWidth, int availableHeight, const QString &mimeType, const QByteArray &bytes)
    {
        const auto frame = QImage::fromData(bytes);
        if (frame.isNull())
            return -1;
        QTextImageFormat image;
        image.setName(QStringLiteral("data:%1;base64,%2").arg(mimeType, QString::fromLatin1(bytes.toBase64())));
        const auto bounds = QSize(qMax(1, availableWidth), qMax(1, availableHeight));
        const qreal scale = qMin(1.0, qMin(qreal(bounds.width()) / frame.width(),
                                          qreal(bounds.height()) / frame.height()));
        image.setWidth(frame.width() * scale);
        image.setHeight(image.width() * frame.height() / frame.width());
        doc()->addResource(QTextDocument::ImageResource, QUrl(image.name()), frame);
        auto selected = cursor(start, end);
        selected.beginEditBlock();
        selected.removeSelectedText();
        if (!selected.atBlockStart())
            selected.insertBlock();
        selected.insertImage(image);
        selected.insertBlock(selected.blockFormat(), QTextCharFormat());
        selected.endEditBlock();
        return selected.position();
    }

    void refreshAnimations()
    {
        const QString prefix = QStringLiteral("data:image/gif;base64,");
        QSet<QString> images;
        for (auto block = doc()->begin(); block.isValid(); block = block.next()) {
            for (auto it = block.begin(); !it.atEnd(); ++it) {
                const auto format = it.fragment().charFormat();
                if (format.isImageFormat() && format.toImageFormat().name().startsWith(prefix))
                    images.insert(format.toImageFormat().name());
            }
        }

        for (const auto &name : m_movies.keys()) {
            if (!images.contains(name))
                delete m_movies.take(name);
        }
        for (const auto &name : images) {
            if (m_movies.contains(name))
                continue;
            auto *movie = new QMovie(this);
            auto *buffer = new QBuffer(movie);
            buffer->setData(QByteArray::fromBase64(name.mid(prefix.size()).toLatin1()));
            buffer->open(QIODevice::ReadOnly);
            movie->setDevice(buffer);
            movie->setFormat("gif");
            if (!movie->isValid()) {
                delete movie;
                continue;
            }
            m_movies.insert(name, movie);
            connect(movie, &QMovie::frameChanged, this, [this, movie, name] {
                doc()->addResource(QTextDocument::ImageResource, QUrl(name), movie->currentImage());
                for (auto block = doc()->begin(); block.isValid(); block = block.next()) {
                    for (auto it = block.begin(); !it.atEnd(); ++it) {
                        const auto fragment = it.fragment();
                        const auto format = fragment.charFormat();
                        if (format.isImageFormat() && format.toImageFormat().name() == name) {
                            auto *layout = doc()->documentLayout();
                            emit layout->updateBlock(block);
                            emit layout->update(layout->blockBoundingRect(block));
                            break;
                        }
                    }
                }
            });
            movie->start();
            if (m_animationsPaused)
                movie->setPaused(true);
        }
    }

    QTextDocument *doc() const { return m_document->textDocument(); }

    QTextCursor cursor(int start, int end) const
    {
        QTextCursor selected(doc());
        const int last = doc()->characterCount() - 1;
        selected.setPosition(qBound(0, start, last));
        selected.setPosition(qBound(0, end, last), QTextCursor::KeepAnchor);
        return selected;
    }

    QHash<QString, QMovie *> m_movies;
    bool m_animationsPaused = false;
    bool m_refreshPending = false;
    QQuickTextDocument *m_document = nullptr;
};
