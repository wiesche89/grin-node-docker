#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include <QFile>
#include <QDir>

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
#include "tip.h"
#include "transaction.h"
#include "transactionbody.h"
#include "txkernel.h"
#include "txkernelprintable.h"
#include "txsource.h"
#include "commitment.h"
#include "output.h"
#include "geolookup.h"

/**
 * @brief registerAllMetaTypes
 */
void registerAllMetaTypes()
{
    // Block-Types
    qRegisterMetaType<BlockPrintable>("BlockPrintable");
    qRegisterMetaType<BlockHeaderPrintable>("BlockHeaderPrintable");
    qRegisterMetaType<BlockListing>("BlockListing");

    // Ergebnis-Wrapper (ganz wichtig!)
    qRegisterMetaType<Result<BlockPrintable> >("Result<BlockPrintable>");
    qRegisterMetaType<Result<BlockHeaderPrintable> >("Result<BlockHeaderPrintable>");
    qRegisterMetaType<Result<BlockListing> >("Result<BlockListing>");

    qRegisterMetaType<Capabilities>("Capabilities");
    qRegisterMetaType<Direction>("Direction");
    qRegisterMetaType<Difficulty>("Difficulty");
    qRegisterMetaType<Input>("Input");

    qRegisterMetaType<Result<LocatedTxKernel> >("Result<LocatedTxKernel>");
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

    qRegisterMetaType<GeoLookup*>("GeoLookup*");

    qmlRegisterType<GrinNodeManager>("Grin", 1, 0, "GrinNodeManager");

    qRegisterMetaType<QList<PoolEntry> >("QList<PoolEntry>");
    qRegisterMetaType<QList<PeerData> >("QList<PeerData>");
    qRegisterMetaType<PeerAddr>("PeerAddr");
}

/**
 * @brief qMain
 * @param argc
 * @param argv
 * @return
 */
int main(int argc, char *argv[])
{
    // -----------------------------------------------------------------------------------------------------------------------
    // Variables
    // -----------------------------------------------------------------------------------------------------------------------
    QString ownerUrl;
    QString foreignUrl;
    QString network;
    QString port;

    network = "main"; // main or test
    port = "8080"; // main = 3413 or test = 13413

    // -----------------------------------------------------------------------------------------------------------------------
    // App configuration
    // -----------------------------------------------------------------------------------------------------------------------
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle("Fusion");   // oder "Basic", "Material", "Imagine"
    app.setWindowIcon(QIcon(":/res/media/grin-node/logo.png"));

    // -----------------------------------------------------------------------------------------------------------------------
    // Registration
    // -----------------------------------------------------------------------------------------------------------------------
    registerAllMetaTypes();
    qmlRegisterType<GeoLookup>("Geo", 1, 0, "GeoLookup");

    // -----------------------------------------------------------------------------------------------------------------------
    // API configuration
    // -----------------------------------------------------------------------------------------------------------------------
    ownerUrl = QString("http://localhost:%1/v2/owner").arg(port);
    foreignUrl = QString("http://localhost:%1/v2/foreign").arg(port);

    // Node Owner Api Instance
    NodeOwnerApi *nodeOwnerApi = new NodeOwnerApi(ownerUrl, QString());

    // Node Foreign Api Instance
    NodeForeignApi *nodeForeignApi = new NodeForeignApi(foreignUrl, QString());

    // -----------------------------------------------------------------------------------------------------------------------
    // Start qml engine
    // -----------------------------------------------------------------------------------------------------------------------
    QQmlApplicationEngine engine;
    // qml context objects
    engine.rootContext()->setContextProperty("nodeForeignApi", nodeForeignApi);
    engine.rootContext()->setContextProperty("nodeOwnerApi", nodeOwnerApi);

    Config config;
    config.loadFromNetwork(network);     // lädt ~/.grin/main/grin-server.toml

    engine.rootContext()->setContextProperty("config", &config);

    engine.load(QUrl(QStringLiteral("qrc:/qml/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    return app.exec();
}
