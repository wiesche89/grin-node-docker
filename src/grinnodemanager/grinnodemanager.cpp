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

// NEU: /delete/<kind>
void GrinNodeManager::deleteChain(NodeKind kind)
{
    qDebug() << Q_FUNC_INFO;
    QNetworkRequest req = makeRequest("delete/" + kindToPath(kind));

    // analog zu start/stop/restart als POST
    m_net->post(req, QByteArray());
}

// ---------- Utils ----------

// kleine Hilfsfunktion, um aus m_baseUrl + relativem Pfad
// eine echte URL zu bauen (ohne den Basis-Pfad zu überschreiben)
QNetworkRequest GrinNodeManager::makeRequest(const QString &path) const
{
    // <-- Speichere den ORIGINAL-Pfad, unverändert
    QString apiPath = path;

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

    // EXAKT diesen relativen Pfad speichern – das ist unser Routing-Key
    req.setAttribute(QNetworkRequest::User, apiPath);

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

// ---------- Reply dispatch ----------
void GrinNodeManager::onReplyFinished(QNetworkReply *reply)
{
    int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

    // Unser eigener „API-Pfad“
    QString apiPath = reply->request().attribute(QNetworkRequest::User).toString();


    // Fallback (nur für Debug), falls aus irgendeinem Grund leer:
    if (apiPath.isEmpty()) {
        apiPath = reply->url().path();
    }

    const QByteArray payload = reply->readAll();

    qDebug() << "[GrinNodeManager] Network:" << statusCode << apiPath << payload;

    auto finish = [&] {
        const QString pretty = safePretty(payload);
        if (pretty != m_lastResponse) {
            m_lastResponse = pretty;
            emit lastResponseChanged();
        }
    };

    if (statusCode != 200) {
        qDebug() << "[GrinNodeManager] Network error:" << statusCode << apiPath << payload;
        emit errorOccurred(QString("[%1] %2")
                               .arg(reply->url().toString(), reply->errorString()));
        finish();
        reply->deleteLater();
        return;
    }

    // Routing nur noch über apiPath
    if (apiPath.startsWith("status")) {
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
