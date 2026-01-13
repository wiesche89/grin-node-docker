#include "priceanalysismanager.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrl>
#include <QUrlQuery>
#include <QDateTime>
#include <QtGlobal>
#include <limits>

namespace {
static const int kHistoryTailCount = 7;

QVariantMap defaultApiConfig()
{
    QVariantMap map;
    map.insert("baseUrl", QStringLiteral("https://api.coingecko.com/api/v3"));
    map.insert("endpoint", QStringLiteral("market_chart"));
    map.insert("coinId", QStringLiteral("grin"));
    map.insert("vsCurrency", QStringLiteral("usd"));
    map.insert("days", QStringLiteral("20"));
    return map;
}
}

PriceAnalysisManager::PriceAnalysisManager(QObject *parent)
    : QObject(parent)
    , m_apiConfig(defaultApiConfig())
{
    refresh();
}

void PriceAnalysisManager::refresh()
{
    if (m_loading)
        return;

    m_loading = true;
    emit loadingChanged();
    setError(QString());

    const QUrl url = buildRequestUrl();
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("GrinNodeDashboard/1.0"));
    QString apiKey = m_apiConfig.value("apiKey").toString();
    if (!apiKey.isEmpty()) {
        request.setRawHeader("x-cg-pro-api-key", apiKey.toUtf8());
    }

    QNetworkReply *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();

        m_loading = false;
        emit loadingChanged();

        if (reply->error() != QNetworkReply::NoError) {
            setError(reply->errorString());
            return;
        }

        parseResponse(reply->readAll());
    });
}

void PriceAnalysisManager::parseResponse(const QByteArray &data)
{
    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        setError(tr("price_err_invalid_response", "Invalid price data from CoinGecko."));
        return;
    }

    QJsonObject root = doc.object();
    QJsonArray prices = root.value("prices").toArray();
    if (prices.isEmpty()) {
        setError(tr("price_err_no_data", "No price data available."));
        return;
    }

    m_history.clear();
    m_recentHistory.clear();
    m_highestPriceUsd = 0.0;
    m_lowestPriceUsd = std::numeric_limits<double>::max();
    m_latestPriceUsd = 0.0;
    m_latestTimestamp.clear();
    m_latestVolumeUsd = 0.0;

    for (const QJsonValue &entry : prices) {
        if (!entry.isArray())
            continue;

        QJsonArray pair = entry.toArray();
        if (pair.size() < 2)
            continue;

        qint64 timestamp = static_cast<qint64>(pair.at(0).toDouble());
        double price = pair.at(1).toDouble();

        QVariantMap row;
        row["price"] = price;
        QDateTime dt = QDateTime::fromMSecsSinceEpoch(timestamp).toUTC();
        row["timestamp"] = dt.toString(Qt::ISODate);

        m_history.append(row);

        m_highestPriceUsd = qMax(m_highestPriceUsd, price);
        if (price < m_lowestPriceUsd)
            m_lowestPriceUsd = price;
    }

    if (!m_history.isEmpty()) {
        QVariantMap latest = m_history.last().toMap();
        m_latestPriceUsd = latest.value("price").toDouble();
        m_latestTimestamp = latest.value("timestamp").toString();

        QJsonArray volumes = root.value("total_volumes").toArray();
        if (!volumes.isEmpty()) {
            QJsonArray latestVolumePair = volumes.last().toArray();
            if (latestVolumePair.size() >= 2)
                m_latestVolumeUsd = latestVolumePair.at(1).toDouble();
        }
    } else {
        m_lowestPriceUsd = 0.0;
        setError(tr("price_err_no_data", "No price data available."));
        return;
    }

    rebuildRecentHistory();
    emit historyChanged();
}

void PriceAnalysisManager::rebuildRecentHistory()
{
    m_recentHistory.clear();
    int start = qMax(0, m_history.count() - kHistoryTailCount);
    for (int i = start; i < m_history.count(); ++i) {
        m_recentHistory.append(m_history.at(i));
    }
}

void PriceAnalysisManager::setError(const QString &message)
{
    if (m_errorString == message)
        return;

    m_errorString = message;
    emit errorStringChanged();
}

QVariantMap PriceAnalysisManager::apiConfig() const
{
    return m_apiConfig;
}

void PriceAnalysisManager::setApiConfig(const QVariantMap &config)
{
    QVariantMap next = m_apiConfig;
    bool changed = false;
    for (auto it = config.constBegin(); it != config.constEnd(); ++it) {
        if (!next.contains(it.key()) || next.value(it.key()) != it.value()) {
            next.insert(it.key(), it.value());
            changed = true;
        }
    }

    if (!changed)
        return;

    m_apiConfig = next;
    emit apiConfigChanged();
}

QUrl PriceAnalysisManager::buildRequestUrl() const
{
    QVariantMap cfg = m_apiConfig;
    QString baseUrl = cfg.value("baseUrl", QStringLiteral("https://api.coingecko.com/api/v3")).toString();
    QString coinId = cfg.value("coinId", QStringLiteral("grin")).toString();
    QString endpoint = cfg.value("endpoint", QStringLiteral("market_chart")).toString();

    QUrl url(QUrl::fromUserInput(baseUrl));
    QString path = url.path();
    if (!path.endsWith('/'))
        path += '/';
    path += QStringLiteral("coins/%1/%2").arg(coinId, endpoint);
    url.setPath(path);

    QUrlQuery query;
    QString vsCurrency = cfg.value("vsCurrency", QStringLiteral("usd")).toString();
    if (!vsCurrency.isEmpty())
        query.addQueryItem(QStringLiteral("vs_currency"), vsCurrency);
    QString days = cfg.value("days", QStringLiteral("7")).toString();
    if (!days.isEmpty())
        query.addQueryItem(QStringLiteral("days"), days);
    QString interval = cfg.value("interval").toString();
    if (!interval.isEmpty())
        query.addQueryItem(QStringLiteral("interval"), interval);
    QString precision = cfg.value("precision").toString();
    if (!precision.isEmpty())
        query.addQueryItem(QStringLiteral("precision"), precision);

    url.setQuery(query);
    return url;
}
