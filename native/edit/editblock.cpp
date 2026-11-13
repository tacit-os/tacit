#include "editblock.h"
#include <QQuickTextDocument>
#include <QTextCursor>
#include <QTextDocument>
#include <KSyntaxHighlighting/Definition>
#include <KSyntaxHighlighting/Repository>
#include <algorithm>

void EditBlock::apply(QQuickTextDocument *doc, const QVariantList &edits)
{
    if (!doc || !doc->textDocument() || edits.isEmpty())
        return;
    struct Piece { int start, end; QString text; };
    QList<Piece> pieces;
    for (const QVariant &e : edits) {
        const QVariantList l = e.toList();
        if (l.size() < 3)
            continue;
        const int a = l[0].toInt(), b = l[1].toInt();
        pieces.append({ std::min(a, b), std::max(a, b), l[2].toString() });
    }
    // Last first, and of two at one offset the later first: each insert lands in front of what is already there, so an
    // empty line's comment marks, [[at, at, "/* "], [at, at, " */"]], read "/*  */" and not " *//* ".
    std::reverse(pieces.begin(), pieces.end());
    std::stable_sort(pieces.begin(), pieces.end(), [](const Piece &x, const Piece &y) { return x.start > y.start; });
    QTextDocument *d = doc->textDocument();
    const int last = d->characterCount() - 1;   // the document's own closing separator is not text
    QTextCursor c(d);
    c.beginEditBlock();
    for (const Piece &p : pieces) {
        c.setPosition(std::clamp(p.start, 0, last));
        c.setPosition(std::clamp(p.end, 0, last), QTextCursor::KeepAnchor);
        c.insertText(p.text);                   // replaces the selection; an empty text only removes
    }
    c.endEditBlock();
}

QString EditBlock::text(QQuickTextDocument *doc) const
{
    if (!doc || !doc->textDocument())
        return QString();
    QString t = doc->textDocument()->toRawText();
    t.replace(QChar::ParagraphSeparator, u'\n');   // the document's own break between blocks
    return t;
}

QStringList EditBlock::commentMarkers(const QString &definitionName) const
{
    static KSyntaxHighlighting::Repository repository;   // loads every definition once, on the first ask
    const auto d = repository.definitionForName(definitionName);
    if (!d.isValid())
        return { QString(), QString(), QString() };
    const auto block = d.multiLineCommentMarker();
    return { d.singleLineCommentMarker(), block.first, block.second };
}
