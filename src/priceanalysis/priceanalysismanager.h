#ifndef PRICEANALYSISMANAGER_H
#define PRICEANALYSISMANAGER_H

#include <QObject>
#include <QVariant>
#include <QVariantMap>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QUrl>

class PriceAnalysisManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(QVariantList recentHistory READ recentHistory NOTIFY historyChanged)
    Q_PROPERTY(double latestPriceUsd READ latestPriceUsd NOTIFY historyChanged)
    Q_PROPERTY(QString latestTimestamp READ latestTimestamp NOTIFY historyChanged)
    Q_PROPERTY(double highestPriceUsd READ highestPriceUsd NOTIFY historyChanged)
    Q_PROPERTY(double lowestPriceUsd READ lowestPriceUsd NOTIFY historyChanged)
    Q_PROPERTY(double latestVolumeUsd READ latestVolumeUsd NOTIFY historyChanged)
    Q_PROPERTY(QVariantMap apiConfig READ apiConfig WRITE setApiConfig NOTIFY apiConfigChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)

public:
    explicit PriceAnalysisManager(QObject *parent = nullptr);

    QVariantList history() const { return m_history; }
    QVariantList recentHistory() const { return m_recentHistory; }
    double latestPriceUsd() const { return m_latestPriceUsd; }
    QString latestTimestamp() const { return m_latestTimestamp; }
    double highestPriceUsd() const { return m_highestPriceUsd; }
    double lowestPriceUsd() const { return m_lowestPriceUsd; }
    double latestVolumeUsd() const { return m_latestVolumeUsd; }
    QVariantMap apiConfig() const;
    void setApiConfig(const QVariantMap &config);
    bool loading() const { return m_loading; }
    QString errorString() const { return m_errorString; }

    Q_INVOKABLE void refresh();

signals:
    void apiConfigChanged();
    void historyChanged();
    void loadingChanged();
    void errorStringChanged();

private:
    void parseResponse(const QByteArray &data);
    void rebuildRecentHistory();
    void setError(const QString &message);
    QUrl buildRequestUrl() const;

    QVariantList m_history;
    QVariantList m_recentHistory;
    double m_latestPriceUsd = 0.0;
    QString m_latestTimestamp;
    double m_highestPriceUsd = 0.0;
    double m_lowestPriceUsd = 0.0;
    double m_latestVolumeUsd = 0.0;
    bool m_loading = false;
    QString m_errorString;
    QNetworkAccessManager m_network;
    QVariantMap m_apiConfig;
};

#endif // PRICEANALYSISMANAGER_H
