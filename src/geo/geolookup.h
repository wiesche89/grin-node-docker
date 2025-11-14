#ifndef GEOLOOKUP_H
#define GEOLOOKUP_H

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QHash>
#include <QPair>

class GeoLookup : public QObject
{
    Q_OBJECT
public:
    explicit GeoLookup(QObject *parent = nullptr);

    typedef QPair<double, double> LatLon;

    // QML soll diese Methode aufrufen können
    Q_INVOKABLE void lookupIPs(const QVariantList &ips);

signals:
    // Signal für QML mit einer Liste von Koordinaten-Objekten
    void lookupFinished(QVariantList coords);

private:
    class QNetworkAccessManager *m_manager;
    QHash<QString, LatLon> m_cache; // ip -> lat/lon
};

Q_DECLARE_METATYPE(GeoLookup*)

#endif // GEOLOOKUP_H
