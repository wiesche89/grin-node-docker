#include "config.h"

/**
 * @brief Config::load
 * @return
 */
bool Config::load()
{
    setError({});
    if (m_path.isEmpty()) {
        setError("Path is empty");
        return false;
    }

    QFile f(m_path);
    if (!f.exists()) {
        setError("File does not exist: " + m_path);
        return false;
    }
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        setError("Open failed: " + f.errorString());
        return false;
    }

    QTextStream in(&f);
    // in.setCodec("UTF-8");
    const QString content = in.readAll();
    f.close();

    setText(content);
    return true;
}

/**
 * @brief Config::save
 * @return
 */
bool Config::save()
{
    setError({});
    if (m_path.isEmpty()) {
        setError("Path is empty");
        return false;
    }

    QFile f(m_path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        setError("Save failed: " + f.errorString());
        return false;
    }

    QTextStream out(&f);
    // out.setCodec("UTF-8");
    out << m_text;
    out.flush();
    f.close();
    return true;
}

/**
 * @brief Config::loadFromNetwork
 * @param network
 * @return
 */
bool Config::loadFromNetwork(const QString &network, bool local)
{
    QString p;

    if(local)
    {
    p = QString("%1/.grin/%2/grin-server.toml")
                      .arg(QDir::homePath(), network);
    }
    else
    {
        p = QString("/data/grin-server.toml");
    }

    setPath(p);
    return load();
}

// --- kleine Helpers -------------------------------------------------

QString Config::trimOutside(const QString &s)
{
    QString r = s.trimmed();
    return r;
}

// Entfernt Kommentare (# ...) nur wenn sie NICHT in Anführungszeichen stehen
QString Config::stripTomlComment(const QString &line)
{
    bool inStr = false;
    bool escape = false;
    QString out;
    out.reserve(line.size());
    for (int i = 0; i < line.size(); ++i) {
        QChar c = line[i];
        if (escape) {
            out += c;
            escape = false;
            continue;
        }
        if (c == '\\') {
            out += c;
            escape = true;
            continue;
        }
        if (c == '\"') {
            inStr = !inStr;
            out += c;
            continue;
        }
        if (c == '#' && !inStr) {
            break;
        }
        out += c;
    }
    return out;
}

// Findet erstes '=' außerhalb von Strings
int Config::findEqualOutsideQuotes(const QString &line)
{
    bool inStr = false;
    bool escape = false;
    for (int i = 0; i < line.size(); ++i) {
        QChar c = line[i];
        if (escape) {
            escape = false;
            continue;
        }
        if (c == '\\') {
            escape = true;
            continue;
        }
        if (c == '\"') {
            inStr = !inStr;
            continue;
        }
        if (c == '=' && !inStr) {
            return i;
        }
    }
    return -1;
}

QString Config::unescapeTomlString(QString s)
{
    // TOML-Strings sind JSON-ähnlich. Wir dekodieren die häufigsten Sequenzen.
    s.replace("\\\"", "\"");
    s.replace("\\\\", "\\");
    s.replace("\\n", "\n");
    s.replace("\\r", "\r");
    s.replace("\\t", "\t");
    return s;
}

bool Config::isQuoted(const QString &v)
{
    return v.size() >= 2 && v.startsWith('\"') && v.endsWith('\"');
}

QString Config::dequote(QString v)
{
    if (isQuoted(v)) {
        v = v.mid(1, v.size() - 2);
    }
    return v;
}

// Parsed eine sehr große TOML-Untermenge ausreichend für grin-server.toml
// Erzeugt Map: "server.db_root" -> "C:\Users\..."
QHash<QString, QString> Config::parseTomlFlatKeys(const QString &text)
{
    QHash<QString, QString> map;
    QStringList curTable; // z.B. ["server","p2p_config"]

    const QStringList lines = text.split('\n');
    for (QString raw : lines) {
        QString line = stripTomlComment(raw).trimmed();
        if (line.isEmpty()) {
            continue;
        }

        // Table: [server] oder [server.p2p_config]
        if (line.startsWith('[') && line.endsWith(']')) {
            bool isArrayTable = (line.size() >= 4 && line.startsWith("[[") && line.endsWith("]]"));
            QString inside = isArrayTable ? line.mid(2, line.size() - 4)
                             : line.mid(1, line.size() - 2);
            inside = trimOutside(inside);
            // für unsere Zwecke ignorieren wir Array-of-Tables; wir übernehmen nur den Pfad
            curTable = inside.split('.', Qt::SkipEmptyParts);
            continue;
        }

        // Key-Value: key = value  ( '=' außerhalb von Strings )
        int eq = findEqualOutsideQuotes(line);
        if (eq < 0) {
            continue;
        }

        QString k = trimOutside(line.left(eq));
        QString v = trimOutside(line.mid(eq + 1));

        if (k.isEmpty()) {
            continue;
        }

        // Vollqualifizierten Key erzeugen: [server] + db_root  -> "server.db_root"
        QStringList parts = curTable;
        foreach(const QString &p, k.split('.', Qt::SkipEmptyParts))
        parts << p;
        QString fullKey = parts.join('.');

        // Wert normalisieren (Strings dequoten/ent-escapen)
        QString valNorm;
        if (isQuoted(v)) {
            valNorm = unescapeTomlString(dequote(v));
        } else {
            // unquoted literal (true/false/number/bare) -> roh zurückgeben
            valNorm = v;
        }

        map.insert(fullKey, valNorm);
    }

    return map;
}

// Wandelt String -> QVariant anhand des Typs des defaultValue
QVariant Config::coerceToType(const QString &raw, const QVariant &defaultValue)
{
    switch (defaultValue.type()) {
    case QMetaType::Bool:
    {
        QString s = raw.trimmed().toLower();
        if (s == "true") {
            return true;
        }
        if (s == "false") {
            return false;
        }
        bool ok = false;
        int n = s.toInt(&ok);
        if (ok) {
            return n != 0;
        }
        return defaultValue;
    }
    case QMetaType::Int:
    {
        bool ok = false;
        int v = raw.toInt(&ok);
        return ok ? QVariant(v) : defaultValue;
    }
    case QMetaType::LongLong:
    {
        bool ok = false;
        qlonglong v = raw.toLongLong(&ok);
        return ok ? QVariant(v) : defaultValue;
    }
    case QMetaType::Double:
    {
        bool ok = false;
        double v = raw.toDouble(&ok);
        return ok ? QVariant(v) : defaultValue;
    }
    default:
        return raw; // QString
    }
}

// --- deine Methode ---------------------------------------------------

QVariant Config::value(const QString &key, const QVariant &defaultValue) const
{
    if (m_text.isEmpty()) {
        return defaultValue;
    }

    // Einmalig parsen (oder bei jedem Aufruf – hier simpel gehalten)
    QHash<QString, QString> map = parseTomlFlatKeys(m_text);

    // Direktes Lookup
    if (map.contains(key)) {
        return coerceToType(map.value(key), defaultValue);
    }

    // Fallback: Versuche auch unquoted/bare Keys (selten nötig)
    // (z. B. wenn jemand "server.db_root " mit Space eingibt)
    QString trimmedKey = key.trimmed();
    if (map.contains(trimmedKey)) {
        return coerceToType(map.value(trimmedKey), defaultValue);
    }

    return defaultValue;
}
