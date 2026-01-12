#include "priceanalysismanager.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrl>
#include <QDateTime>
#include <QtGlobal>
#include <limits>

namespace {
static const int kHistoryTailCount = 7;
static const char kCoinGeckoUrl[] =
    "https://api.coingecko.com/api/v3/coins/grin/market_chart?vs_currency=usd&days=7";
}

PriceAnalysisManager::PriceAnalysisManager(QObject *parent)
    : QObject(parent)
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

    const QUrl url = QUrl(QLatin1String(kCoinGeckoUrl));
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("GrinNodeDashboard/1.0"));

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
