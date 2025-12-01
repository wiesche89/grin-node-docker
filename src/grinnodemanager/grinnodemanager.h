#ifndef GRINNODEMANAGER_H
#define GRINNODEMANAGER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrl>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QTimer>
#include <QDebug>

class GrinNodeManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString lastResponse READ lastResponse NOTIFY lastResponseChanged)
    // Optional: direkt in QML setzbar
    Q_PROPERTY(QString username READ username WRITE setUsername NOTIFY optionsChanged)
    Q_PROPERTY(QString password READ password WRITE setPassword NOTIFY optionsChanged)
    Q_PROPERTY(int timeoutMs READ timeoutMs WRITE setTimeoutMs NOTIFY optionsChanged)
    Q_PROPERTY(QString userAgent READ userAgent WRITE setUserAgent NOTIFY optionsChanged)
public:
    enum class NodeKind {
        Rust, GrinPP
    };
    Q_ENUM(NodeKind)

    struct Options {
        QString username;
        QString password;
        int timeoutMs;
        QByteArray userAgent;
        Options()
            : timeoutMs(15000),
            userAgent("GrinNodeManager/1.0")
        {
        }
    };

    // parameterloser Ctor für QML
    explicit GrinNodeManager(QObject *parent = nullptr);

    // vorhandener Ctor bleibt
    explicit GrinNodeManager(const QUrl &baseUrl, const Options &opts = Options(), QObject *parent = nullptr);
    ~GrinNodeManager() override;

    // QML API
    Q_INVOKABLE void getStatus();

    Q_INVOKABLE void startRust(const QStringList &args = {});
    Q_INVOKABLE void stopRust();
    Q_INVOKABLE void restartRust(const QStringList &args = {});
    Q_INVOKABLE void getLogsRust(int n = 100);

    Q_INVOKABLE void startGrinPP(const QStringList &args = {});
    Q_INVOKABLE void stopGrinPP();
    Q_INVOKABLE void restartGrinPP(const QStringList &args = {});
    Q_INVOKABLE void getLogsGrinPP(int n = 100);

    // NEU: Chain-Delete-Endpunkte
    Q_INVOKABLE void deleteRustChain();
    Q_INVOKABLE void deleteGrinppChain();

    Q_INVOKABLE void startStatusPolling(int intervalMs);
    Q_INVOKABLE void stopStatusPolling();

    // Properties
    QUrl baseUrl() const { return m_baseUrl; }
    void setBaseUrl(const QUrl &u);

    QString lastResponse() const { return m_lastResponse; }

    // Options als Properties
    QString username() const { return m_opts.username; }
    void setUsername(const QString &u) { m_opts.username = u; emit optionsChanged(); }

    QString password() const { return m_opts.password; }
    void setPassword(const QString &p) { m_opts.password = p; emit optionsChanged(); }

    int timeoutMs() const { return m_opts.timeoutMs; }
    void setTimeoutMs(int t) { m_opts.timeoutMs = t; emit optionsChanged(); }

    QString userAgent() const { return QString::fromUtf8(m_opts.userAgent); }
    void setUserAgent(const QString &ua) { m_opts.userAgent = ua.toUtf8(); emit optionsChanged(); }

signals:
    void statusReceived(const QJsonObject &json);
    void logsReceived(const QString &logs);
    void nodeStarted(GrinNodeManager::NodeKind kind);
    void nodeStopped(GrinNodeManager::NodeKind kind);
    void nodeRestarted(GrinNodeManager::NodeKind kind);
    void lastResponseChanged();
    void baseUrlChanged();
    void optionsChanged();
    void errorOccurred(const QString &message);

    void chainDeleted(GrinNodeManager::NodeKind kind);

private slots:
    void onReplyFinished(QNetworkReply *reply);

private:
    // Hilfsinit, von beiden Ctors aufgerufen
    void initNetwork();

    void start(NodeKind kind, const QStringList &args);
    void stop(NodeKind kind);
    void restart(NodeKind kind, const QStringList &args);
    void getLogs(NodeKind kind, int n);

    void deleteChain(NodeKind kind);

    QNetworkRequest makeRequest(const QString &path) const;
    QByteArray basicAuthHeader() const;
    QString kindToPath(NodeKind kind) const;

    QUrl m_baseUrl;
    Options m_opts;
    QNetworkAccessManager *m_net{nullptr};
    QTimer m_statusTimer;
    QString m_lastResponse;
};

#endif // GRINNODEMANAGER_H
