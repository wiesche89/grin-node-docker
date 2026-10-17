#include "grinnodemanager.h"
#include <QJsonDocument>
#include <QJsonParseError>

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

    m_statusTimer.setSingleShot(false);
    connect(&m_statusTimer, &QTimer::timeout, this, &GrinNodeManager::getStatus);
}

// Default-Ctor für QML
GrinNodeManager::GrinNodeManager(QObject *parent) :
    QObject(parent)
{
    initNetwork();
}

// Ctor mit Base-URL
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

// NEU: Delete-Wrapper für QML
void GrinNodeManager::deleteRustChain()
{
    deleteChain(NodeKind::Rust);
}

void GrinNodeManager::deleteGrinppChain()
{
    deleteChain(NodeKind::GrinPP);
}

// ---------- Public API ----------
void GrinNodeManager::getStatus()
{
    if (m_statusPending)
        return;
    m_statusPending = true;
    QNetworkRequest req = makeRequest("status");
    watchReply(m_net->get(req), "status");
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
    const QString path = "start/" + kindToPath(kind);
    QNetworkRequest req = makeRequest(path);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject json;
    if (!args.isEmpty()) {
        json["args"] = QJsonArray::fromStringList(args);
    }

    watchReply(m_net->post(req, QJsonDocument(json).toJson()), path);
}

void GrinNodeManager::stop(NodeKind kind)
{
    const QString path = "stop/" + kindToPath(kind);
    QNetworkRequest req = makeRequest(path);
    watchReply(m_net->post(req, QByteArray()), path);
}

void GrinNodeManager::restart(NodeKind kind, const QStringList &args)
{
    const QString path = "restart/" + kindToPath(kind);
    QNetworkRequest req = makeRequest(path);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject json;
    if (!args.isEmpty()) {
        json["args"] = QJsonArray::fromStringList(args);
    }

    watchReply(m_net->post(req, QJsonDocument(json).toJson()), path);
}

void GrinNodeManager::getLogs(NodeKind kind, int n)
{
    // Query-String direkt an den relativen Pfad hängen
    QNetworkRequest req = makeRequest(QString("logs/%1?n=%2")
                                          .arg(kindToPath(kind))
                                          .arg(n));
    watchReply(m_net->get(req), "logs/" + kindToPath(kind));
}

// NEU: /delete/<kind>
void GrinNodeManager::deleteChain(NodeKind kind)
{
    const QString path = "delete/" + kindToPath(kind);
    QNetworkRequest req = makeRequest(path);

    // analog zu start/stop/restart als POST
    watchReply(m_net->post(req, QByteArray()), path);
}

// ---------- Utils ----------

// kleine Hilfsfunktion, um aus m_baseUrl + relativem Pfad
// eine echte URL zu bauen (ohne den Basis-Pfad zu überschreiben)
QNetworkRequest GrinNodeManager::makeRequest(const QString &path) const
{
    QString rel = path;
    if (rel.startsWith('/'))
        rel.remove(0, 1);

    QUrl relUrl;
    relUrl.setPath(rel);

    QUrl base = m_baseUrl;
    if (!base.isValid() || base.isEmpty()) {
        base = QUrl("/");
    }

    QUrl url = base.resolved(relUrl);

    QNetworkRequest req(url);

    req.setRawHeader("User-Agent", m_opts.userAgent);
    if (!m_opts.username.isEmpty())
        req.setRawHeader("Authorization", basicAuthHeader());

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

void GrinNodeManager::watchReply(QNetworkReply *reply, const QString &apiPath)
{
    // Qt WASM replies do not retain the original request.
    connect(reply, &QNetworkReply::finished, this, [this, reply, apiPath] {
        onReplyFinished(reply, apiPath);
    });
    QTimer::singleShot(qMax(1000, m_opts.timeoutMs), reply, [reply] {
        if (!reply->isFinished())
            reply->abort();
    });
}

// ---------- Reply dispatch ----------
void GrinNodeManager::onReplyFinished(QNetworkReply *reply, const QString &apiPath)
{
    int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

    if (apiPath == "status")
        m_statusPending = false;

    const QByteArray payload = reply->readAll();

    auto finish = [&] {
        const QString pretty = safePretty(payload);
        if (pretty != m_lastResponse) {
            m_lastResponse = pretty;
            emit lastResponseChanged();
        }
    };

    if (statusCode != 200 || reply->error() != QNetworkReply::NoError) {
        emit errorOccurred(QString("[%1] %2")
                               .arg(reply->url().toString(), reply->errorString()));
        finish();
        reply->deleteLater();
        return;
    }

    // Routing nur noch über apiPath
    if (apiPath == "status") {
        const auto doc = QJsonDocument::fromJson(payload);
        emit statusReceived(doc.object());
    } else if (apiPath.startsWith("logs/")) {
        emit logsReceived(QString::fromUtf8(payload));
    } else if (apiPath.startsWith("start/")) {
        emit nodeStarted(apiPath.contains("rust") ? NodeKind::Rust : NodeKind::GrinPP);
    } else if (apiPath.startsWith("stop/")) {
        emit nodeStopped(apiPath.contains("rust") ? NodeKind::Rust : NodeKind::GrinPP);
    } else if (apiPath.startsWith("restart/")) {
        emit nodeRestarted(apiPath.contains("rust") ? NodeKind::Rust : NodeKind::GrinPP);
    } else if (apiPath.startsWith("delete/")) {
        emit chainDeleted(apiPath.contains("rust") ? NodeKind::Rust : NodeKind::GrinPP);
    }

    finish();
    reply->deleteLater();
}
