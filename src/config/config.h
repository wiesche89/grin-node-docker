#ifndef CONFIG_H
#define CONFIG_H

#include <QString>
#include <QVariant>
#include <QMap>
#include <QVector>

struct ConfigLine {
    enum Type { Comment, Section, KeyValue, Empty } type;
    QString section;
    QString key;
    QString value;
    QString raw;
};

class Config : public QObject {
    Q_OBJECT
public:
    explicit Config(QObject *parent = nullptr);

    Q_INVOKABLE bool load(const QString &path);
    Q_INVOKABLE bool save(const QString &path) const;

    Q_INVOKABLE QVariant getValue(const QString &section, const QString &key) const;
    Q_INVOKABLE void setValue(const QString &section, const QString &key, const QVariant &value);

    Q_INVOKABLE QVariantList allEntries() const;

private:
    QVector<ConfigLine> lines;
};


#endif // CONFIG_H
