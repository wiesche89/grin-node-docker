#ifndef CONFIG_H
#define CONFIG_H

#include <QObject>
#include <QString>
#include <QRegularExpression>
#include <QRegularExpressionMatch>
#include <QDir>
#include <QFile>
#include <QTextStream>

class Config : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(QString text READ text WRITE setText NOTIFY textChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)
public:
    explicit Config(QObject *parent = nullptr) : QObject(parent)
    {
    }

    QString path() const
    {
        return m_path;
    }

    void setPath(const QString &p)
    {
        if (m_path == p) {
            return;
        }
        m_path = p;
        emit pathChanged();
    }

    QString text() const
    {
        return m_text;
    }

    void setText(const QString &t)
    {
        if (m_text == t) {
            return;
        }
        m_text = t;
        emit textChanged();
    }

    QString errorString() const
    {
        return m_error;
    }

    Q_INVOKABLE bool load();                   // lädt Datei -> text
    Q_INVOKABLE bool save();                   // speichert text -> Datei
    Q_INVOKABLE bool loadFromNetwork(const QString &network, bool local = false); // ~/.grin/<network>/grin-server.toml
    Q_INVOKABLE QVariant value(const QString &key, const QVariant &defaultValue) const;
signals:
    void pathChanged();
    void textChanged();
    void errorStringChanged();

private:
    QString m_path;
    QString m_text;
    QString m_error;

    void setError(const QString &e)
    {
        m_error = e;
        emit errorStringChanged();
    }

    static QVariant coerceToType(const QString &raw, const QVariant &defaultValue);
    static QHash<QString, QString> parseTomlFlatKeys(const QString &text);
    static QString unescapeTomlString(QString s);
    static int findEqualOutsideQuotes(const QString &line);
    static QString stripTomlComment(const QString &line);
    static QString trimOutside(const QString &s);
    static bool isQuoted(const QString &v);
    static QString dequote(QString v);
};

#endif // CONFIG_H
