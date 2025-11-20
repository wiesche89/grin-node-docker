#include "grinnodemanager.h"
#include <QJsonDocument>
#include <QJsonParseError>
#include <QDebug>

static inline QString safePretty(const QByteArray &data)
{
    QJsonParseError err{};
    const auto doc = QJsonDocument::fromJson(data, &err);
    if (err.error == QJsonParseError::NoError) {
        return QString::fromUtf8(doc.toJson(QJsonDocument::Indented));
    }
    return QString::fromUtf8(data);
}

// Gemeinsames Init
void GrinNodeManager::initNetwork()
{
    if (!m_net) {
        m_net = new QNetworkAccessManager(this);
    }
    connect(m_net, &QNetworkAccessManager::finished,
            this, &GrinNodeManager::onReplyFinished);

    m_statusTimer.setSingleShot(false);
    connect(&m_statusTimer, &QTimer::timeout, this, &GrinNodeManager::getStatus);
}

// NEU: Default-Ctor für QML
GrinNodeManager::GrinNodeManager(QObject *parent) :
    QObject(parent)
{
    initNetwork();
}

// Bisheriger Ctor bleibt
GrinNodeManager::GrinNodeManager(const QUrl &baseUrl, const Options &opts, QObject *parent) :
    QObject(parent),
    m_baseUrl(baseUrl),
    m_opts(opts)
{
    initNetwork();
}

GrinNodeManager::~GrinNodeManager() = default;

// ---------- QML wrappers ----------
void GrinNodeManager::startRust(const QStringList &args)
{
    start(NodeKind::Rust, args);
}

void GrinNodeManager::stopRust()
{
    stop(NodeKind::Rust);
}

void GrinNodeManager::restartRust(const QStringList &args)
{
    restart(NodeKind::Rust, args);
}

void GrinNodeManager::getLogsRust(int n)
{
    getLogs(NodeKind::Rust, n);
}

void GrinNodeManager::startGrinPP(const QStringList &args)
{
    start(NodeKind::GrinPP, args);
}

void GrinNodeManager::stopGrinPP()
{
    stop(NodeKind::GrinPP);
}

void GrinNodeManager::restartGrinPP(const QStringList &args)
{
    restart(NodeKind::GrinPP, args);
}

void GrinNodeManager::getLogsGrinPP(int n)
{
    getLogs(NodeKind::GrinPP, n);
}

// ---------- Public API ----------
void GrinNodeManager::getStatus()
{
    qDebug() << Q_FUNC_INFO;
    QNetworkRequest req = makeRequest("status");
    m_net->get(req);
}

// Polling
void GrinNodeManager::startStatusPolling(int intervalMs)
{
    if (intervalMs < 1000) {
        intervalMs = 1000;
    }
    m_statusTimer.start(intervalMs);
}

void GrinNodeManager::stopStatusPolling()
{
    m_statusTimer.stop();
}

// ---------- Core helpers ----------
void GrinNodeManager::start(NodeKind kind, const QStringList &args)
{
    qDebug() << Q_FUNC_INFO;
    QNetworkRequest req = makeRequest("start/" + kindToPath(kind));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject json;
    if (!args.isEmpty()) {
        json["args"] = QJsonArray::fromStringList(args);
    }

    m_net->post(req, QJsonDocument(json).toJson());
}

void GrinNodeManager::stop(NodeKind kind)
{
    qDebug() << Q_FUNC_INFO;
    QNetworkRequest req = makeRequest("stop/" + kindToPath(kind));
    m_net->post(req, QByteArray());
}

void GrinNodeManager::restart(NodeKind kind, const QStringList &args)
{
    qDebug() << Q_FUNC_INFO;
    QNetworkRequest req = makeRequest("restart/" + kindToPath(kind));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject json;
    if (!args.isEmpty()) {
        json["args"] = QJsonArray::fromStringList(args);
    }

    m_net->post(req, QJsonDocument(json).toJson());
}

void GrinNodeManager::getLogs(NodeKind kind, int n)
{
    qDebug() << Q_FUNC_INFO;
    // Query-String direkt an den relativen Pfad hängen
    QNetworkRequest req = makeRequest(QString("logs/%1?n=%2")
                                      .arg(kindToPath(kind))
                                      .arg(n));
    m_net->get(req);
}

// ---------- Utils ----------

// kleine Hilfsfunktion, um aus m_baseUrl + relativem Pfad
// eine echte URL zu bauen (ohne den Basis-Pfad zu überschreiben)
QNetworkRequest GrinNodeManager::makeRequest(const QString &path) const
{
    QString rel = path;

    // WICHTIG: führenden Slash entfernen, sonst überschreibt
    // QUrl::resolved() den Pfad der baseUrl statt anzuhängen.
    if (rel.startsWith('/')) {
        rel.remove(0, 1);
    }

    QUrl relUrl;
    relUrl.setPath(rel);

    QUrl base = m_baseUrl;
    if (!base.isValid() || base.isEmpty()) {
        // Fallback: relative URL
        base = QUrl(QStringLiteral("/"));
    }

    QUrl url = base.resolved(relUrl);

    // Debug zum Überprüfen im Log
    // qDebug() << "[GrinNodeManager] makeRequest base=" << base
    // << "rel=" << rel << "->" << url;

    QNetworkRequest req(url);
    req.setRawHeader("User-Agent", m_opts.userAgent);
    if (!m_opts.username.isEmpty()) {
        req.setRawHeader("Authorization", basicAuthHeader());
    }
    return req;
}

QByteArray GrinNodeManager::basicAuthHeader() const
{
    const QByteArray token = QString("%1:%2").arg(m_opts.username, m_opts.password).toUtf8().toBase64();
    return "Basic " + token;
}

QString GrinNodeManager::kindToPath(NodeKind kind) const
{
    return (kind == NodeKind::Rust) ? "rust" : "grinpp";
}

void GrinNodeManager::setBaseUrl(const QUrl &u)
{
    QUrl fixed = u;

    // Wenn Pfad leer ist, "/" setzen
    if (fixed.path().isEmpty()) {
        fixed.setPath("/");
    }

    // Pfad immer mit "/" enden lassen, damit resolved() sauber arbeitet
    QString p = fixed.path();
    if (!p.endsWith('/')) {
        p.append('/');
        fixed.setPath(p);
    }

    if (fixed == m_baseUrl) {
        return;
    }

    m_baseUrl = fixed;
    emit baseUrlChanged();
}

// ---------- Reply dispatch ----------
void GrinNodeManager::onReplyFinished(QNetworkReply *reply)
{
    int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QUrl url = reply->request().url();
    const QString path = url.path();
    const QByteArray payload = reply->readAll();

    auto finish = [&] {
                      const QString pretty = safePretty(payload);
                      if (pretty != m_lastResponse) {
                          m_lastResponse = pretty;
                          emit lastResponseChanged();
                      }
                  };

    if (statusCode != 200) {
        qDebug() << "[GrinNodeManager] Network error: " << statusCode << "    " << path << "    " << payload;

        emit errorOccurred(QString("[%1] %2").arg(url.toString(), reply->errorString()));

        finish();
        reply->deleteLater();
        return;
    }

    // Route by endpoint
    if (path.endsWith("/status")) {
        const auto doc = QJsonDocument::fromJson(payload);
        emit statusReceived(doc.object());
    } else if (path.contains("/logs/")) {
        emit logsReceived(QString::fromUtf8(payload));
    } else if (path.contains("/start/")) {
        qDebug() << "[GrinNodeManager] start reply path=" << path;
        emit nodeStarted(path.contains("rust") ? NodeKind::Rust : NodeKind::GrinPP);
    } else if (path.contains("/stop/")) {
        emit nodeStopped(path.contains("rust") ? NodeKind::Rust : NodeKind::GrinPP);
    } else if (path.contains("/restart/")) {
        emit nodeRestarted(path.contains("rust") ? NodeKind::Rust : NodeKind::GrinPP);
    }

    finish();
    reply->deleteLater();
}
