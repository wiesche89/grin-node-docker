#include "config.h"
#include <QFile>
#include <QTextStream>

Config::Config(QObject *parent) : QObject(parent) {}

bool Config::load(const QString &path) {
    lines.clear();
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return false;

    QTextStream in(&f);
    QString currentSection;

    qDebug()<<"path: "<<path;

    while (!in.atEnd()) {
        QString line = in.readLine();

        if (line.trimmed().isEmpty()) {
            lines.append({ConfigLine::Empty, "", "", "", line});
            continue;
        }
        if (line.trimmed().startsWith("#")) {
            lines.append({ConfigLine::Comment, "", "", "", line});
            continue;
        }
        if (line.trimmed().startsWith("[")) {
            QString sec = line;
            sec.remove('[').remove(']');
            currentSection = sec.trimmed();
            lines.append({ConfigLine::Section, currentSection, "", "", line});
            continue;
        }

        int eq = line.indexOf('=');
        if (eq > 0) {
            QString key = line.left(eq).trimmed();
            QString val = line.mid(eq + 1).trimmed();

            if (val.startsWith("\"") && val.endsWith("\""))
                val = val.mid(1, val.length() - 2);

            qDebug()<<key<< " = "<<val;
            lines.append({ConfigLine::KeyValue, currentSection, key, val, line});
        } else {
            lines.append({ConfigLine::Comment, "", "", "", line});
        }
    }
    return true;
}

bool Config::save(const QString &path) const {
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) return false;
    QTextStream out(&f);

    for (const auto &l : lines) {
        switch (l.type) {
        case ConfigLine::Comment:
        case ConfigLine::Empty:
        case ConfigLine::Section:
            out << l.raw << "\n";
            break;
        case ConfigLine::KeyValue:
            out << l.key << " = \"" << l.value << "\"\n";
            break;
        }
    }
    return true;
}

QVariant Config::getValue(const QString &section, const QString &key) const {
    for (const auto &l : lines) {
        if (l.type == ConfigLine::KeyValue &&
            l.section == section &&
            l.key == key) {
            return l.value;
        }
    }
    return {};
}

void Config::setValue(const QString &section, const QString &key, const QVariant &value) {
    for (auto &l : lines) {
        if (l.type == ConfigLine::KeyValue &&
            l.section == section &&
            l.key == key) {
            l.value = value.toString();
            return;
        }
    }
    lines.append({ConfigLine::KeyValue, section, key, value.toString(), ""});
}

QVariantList Config::allEntries() const {
    QVariantList list;
    for (const auto &l : lines) {
        QVariantMap m;
        m["type"] = l.type;
        m["section"] = l.section;
        m["key"] = l.key;
        m["value"] = l.value;
        list.append(m);


    }
    return list;
}
