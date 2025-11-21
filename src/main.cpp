#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>

#include "grinnodemanager.h"
#include "nodeforeignapi.h"
#include "nodeownerapi.h"
#include "config.h"

#include "blindingfactor.h"
#include "blockheaderprintable.h"
#include "blocklisting.h"
#include "blockprintable.h"
#include "capabilities.h"
#include "direction.h"
#include "difficulty.h"
#include "input.h"
#include "locatedtxkernel.h"
#include "merkleproof.h"
#include "nodeversion.h"
#include "outputidentifier.h"
#include "outputlisting.h"
#include "outputprintable.h"
#include "peeraddr.h"
#include "peerdata.h"
#include "peerinfodisplay.h"
#include "poolentry.h"
#include "protocolversion.h"
#include "rangeproof.h"
#include "status.h"
#include "syncinfo.h"
#include "tip.h"
#include "transaction.h"
#include "transactionbody.h"
#include "txkernel.h"
#include "txkernelprintable.h"
#include "txsource.h"
#include "commitment.h"
#include "output.h"
#include "geolookup.h"
#include "result.h"

/**
 * @brief registerAllMetaTypes
 */
void registerAllMetaTypes()
{
    // Block-Types
    qRegisterMetaType<BlockPrintable>("BlockPrintable");
    qRegisterMetaType<BlockHeaderPrintable>("BlockHeaderPrintable");
    qRegisterMetaType<BlockListing>("BlockListing");

#ifndef Q_OS_WASM
    // Ergebnis-Wrapper (werden in C++-Callbacks genutzt)
    qRegisterMetaType<Result<BlockPrintable> >("Result<BlockPrintable>");
    qRegisterMetaType<Result<BlockHeaderPrintable> >("Result<BlockHeaderPrintable>");
    qRegisterMetaType<Result<BlockListing> >("Result<BlockListing>");
    qRegisterMetaType<Result<LocatedTxKernel> >("Result<LocatedTxKernel>");
#endif

    qRegisterMetaType<Capabilities>("Capabilities");
    qRegisterMetaType<Direction>("Direction");
    qRegisterMetaType<Difficulty>("Difficulty");
    qRegisterMetaType<Input>("Input");
    qRegisterMetaType<LocatedTxKernel>("LocatedTxKernel");
    qRegisterMetaType<MerkleProof>("MerkleProof");
    qRegisterMetaType<NodeVersion>("NodeVersion");
    qRegisterMetaType<OutputIdentifier>("OutputIdentifier");
    qRegisterMetaType<OutputListing>("OutputListing");
    qRegisterMetaType<OutputPrintable>("OutputPrintable");
    qRegisterMetaType<PeerAddr>("PeerAddr");
    qRegisterMetaType<PeerData>("PeerData");
    qRegisterMetaType<PeerInfoDisplay>("PeerInfoDisplay");
    qRegisterMetaType<PoolEntry>("PoolEntry");
    qRegisterMetaType<ProtocolVersion>("ProtocolVersion");
    qRegisterMetaType<RangeProof>("RangeProof");
    qRegisterMetaType<Status>("Status");
    qRegisterMetaType<SyncInfo>("SyncInfo");
    qRegisterMetaType<Tip>("Tip");
    qRegisterMetaType<Transaction>("Transaction");
    qRegisterMetaType<TransactionBody>("TransactionBody");
    qRegisterMetaType<TxKernel>("TxKernel");
    qRegisterMetaType<TxKernelPrintable>("TxKernelPrintable");
    qRegisterMetaType<TxSourceWrapper>("TxSourceWrapper");
    qRegisterMetaType<Commitment>("Commitment");
    qRegisterMetaType<Output>("Output");

    qRegisterMetaType<GeoLookup *>("GeoLookup*");

    qmlRegisterType<GrinNodeManager>("Grin", 1, 0, "GrinNodeManager");

    qRegisterMetaType<QList<PoolEntry> >("QList<PoolEntry>");
    qRegisterMetaType<QList<PeerData> >("QList<PeerData>");
}

/**
 * @brief main
 */
int main(int argc, char *argv[])
{
    // ------------------------------------------------------------------------------------
    // Qt-App
    // ------------------------------------------------------------------------------------
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle("Fusion");
    app.setWindowIcon(QIcon(":/res/media/grin-node/logo.png"));

    // ------------------------------------------------------------------------------------
    // Meta-Typen & QML-Typen
    // ------------------------------------------------------------------------------------
    registerAllMetaTypes();
    qmlRegisterType<GeoLookup>("Geo", 1, 0, "GeoLookup");

    // ------------------------------------------------------------------------------------
    // Controller-Basis-URL bestimmen
    // ------------------------------------------------------------------------------------
    QString controllerBase = QString::fromUtf8(qgetenv("CONTROLLER_URL"));
    if (controllerBase.isEmpty()) {
        controllerBase = QString::fromUtf8(qgetenv("GRIN_NODE_CONTROLLER_URL"));
    }

#ifdef Q_OS_WASM
    // Im Browser immer über den Reverse Proxy (/api/) gehen
    if (controllerBase.isEmpty()) {
        controllerBase = QStringLiteral("/api/");
    }
#else
    // Desktop-Default: lokaler Controller
    if (controllerBase.isEmpty()) {
        controllerBase = QStringLiteral("http://umbrel.local:3416/");
    }
#endif

    if (!controllerBase.endsWith(QLatin1Char('/'))) {
        controllerBase.append(QLatin1Char('/'));
    }

    QUrl controllerBaseUrl(controllerBase);

    // v2/owner & v2/foreign darauf aufbauen
    const QString ownerUrl = controllerBaseUrl.resolved(QUrl(QStringLiteral("v2/owner"))).toString();
    const QString foreignUrl = controllerBaseUrl.resolved(QUrl(QStringLiteral("v2/foreign"))).toString();

    // ------------------------------------------------------------------------------------
    // API-Instanzen
    // ------------------------------------------------------------------------------------
    NodeOwnerApi *nodeOwnerApi = new NodeOwnerApi(ownerUrl, QString(), &app);
    NodeForeignApi *nodeForeignApi = new NodeForeignApi(foreignUrl, QString());

    // ------------------------------------------------------------------------------------
    // QML-Engine
    // ------------------------------------------------------------------------------------
    QQmlApplicationEngine engine;

    // Kontext-Properties
    engine.rootContext()->setContextProperty("nodeForeignApi", nodeForeignApi);
    engine.rootContext()->setContextProperty("nodeOwnerApi", nodeOwnerApi);

    Config config;
    engine.rootContext()->setContextProperty("config", &config);
    engine.rootContext()->setContextProperty("controllerBaseUrl", controllerBaseUrl);

    engine.load(QUrl(QStringLiteral("qrc:/qml/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    return app.exec();
}
