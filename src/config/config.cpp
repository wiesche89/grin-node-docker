#include "config.h"
#include <QDir>
#include <QFile>
#include <QTextStream>

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

bool Config::loadFromNetwork(const QString &network)
{
    const QString p = QString("%1/.grin/%2/grin-server.toml")
                      .arg(QDir::homePath(), network);
    setPath(p);
    return load();
}
