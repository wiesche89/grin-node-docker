#include "geolookup.h"
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonDocument>
#include <QDebug>

GeoLookup::GeoLookup(QObject *parent) :
    QObject(parent),
    m_manager(new QNetworkAccessManager(this))
{
}

void GeoLookup::lookupIPs(const QVariantList &ips)
{
    QList<LatLon> known;
    QStringList toFetch;

    // durch alle IPs gehen
    for (const QVariant &v : ips) {
        QString ip = v.toString();
        if (m_cache.contains(ip)) {
            known.append(m_cache.value(ip));
        } else {
            toFetch.append(ip);
        }
    }

    // Wenn nichts nachzuholen ist, direkt Ergebnis aus Cache senden
    if (toFetch.isEmpty()) {
        QVariantList coords;
        for (const LatLon &p : known) {
            QVariantMap m;
            m["lat"] = p.first;
            m["lon"] = p.second;
            coords.append(m);
        }
        emit lookupFinished(coords);
        return;
    }

    // Anfrage bauen
    QJsonArray arr;
    for (const QString &ip : toFetch) {
        arr.append(QJsonObject{{"query", ip}});
    }

    QNetworkRequest req(QUrl("http://ip-api.com/batch"));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QNetworkReply *reply = m_manager->post(req, QJsonDocument(arr).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply, known]() mutable {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QList<LatLon> all = known; // starte mit Cache-Ergebnissen

        QJsonParseError err;
        QJsonDocument doc = QJsonDocument::fromJson(data, &err);
        if (err.error != QJsonParseError::NoError || !doc.isArray()) {
            qWarning() << "GeoLookup JSON Fehler:" << err.errorString();
        } else {
            QJsonArray arr = doc.array();
            for (const QJsonValue &v : std::as_const(arr)) {
                QJsonObject obj = v.toObject();
                if (obj.value("status").toString() == "success") {
                    QString ip = obj.value("query").toString();
                    double lat = obj.value("lat").toDouble();
                    double lon = obj.value("lon").toDouble();
                    LatLon p(lat, lon);
                    m_cache.insert(ip, p);
                    all.append(p);
                }
            }
        }

        // Ergebnis in QVariantList für QML umwandeln
        QVariantList coords;
        for (const LatLon &p : all) {
            QVariantMap m;
            m["lat"] = p.first;
            m["lon"] = p.second;
            coords.append(m);
        }

        emit lookupFinished(coords);
    });
}
