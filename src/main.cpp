#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <QFile>
#include <QDir>

// #include "grinnodemanager/grinnodemanager.h"

#include "nodeforeignapi.h"
#include "nodeownerapi.h"

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

#include "config/config.h"

/**
 * @brief registerAllMetaTypes
 */
void registerAllMetaTypes()
{
    qRegisterMetaType<BlindingFactor>("BlindingFactor");
    qRegisterMetaType<BlockHeaderPrintable>("BlockHeaderPrintable");
    qRegisterMetaType<BlockListing>("BlockListing");
    qRegisterMetaType<BlockPrintable>("BlockPrintable");
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

    qRegisterMetaType<GeoLookup>("GeoLookup");
}

/**
 * @brief readFileToString
 * @param filePath
 * @return
 */
QString readFileToString(const QString &filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "Could not open file:" << file.errorString();
        return {};
    }

    QTextStream in(&file);
    return in.readAll();
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
    QString ownerAuth;
    QString foreignUrl;
    QString foreignAuth;
    QString network;

    network = "test"; // main or test

    // -----------------------------------------------------------------------------------------------------------------------
    // App configuration
    // -----------------------------------------------------------------------------------------------------------------------
    QGuiApplication app(argc, argv);
    app.setWindowIcon(QIcon(":/res/media/logo.png"));

    // -----------------------------------------------------------------------------------------------------------------------
    // Registration
    // -----------------------------------------------------------------------------------------------------------------------
    registerAllMetaTypes();
    qmlRegisterType<GeoLookup>("Geo", 1, 0, "GeoLookup");

    // -----------------------------------------------------------------------------------------------------------------------
    // Instance NodeManager
    // -----------------------------------------------------------------------------------------------------------------------
    // GrinNodeManager manager;
    // if (!manager.startNode(network)) {
    // return -10;
    // }

    // -----------------------------------------------------------------------------------------------------------------------
    // API configuration
    // -----------------------------------------------------------------------------------------------------------------------
    ownerUrl = "http://127.0.0.1:13413/v2/owner";
    foreignUrl = "http://127.0.0.1:13413/v2/foreign";

    // Username & Passwort
    QString username = "grin";
    QString passwordOwner;
    QString passwordForeign;

    passwordOwner = readFileToString(QString(QDir::homePath() + "/.grin/%1/.api_secret").arg(network));
    passwordForeign = readFileToString(QString(QDir::homePath() + "/.grin/%1/.foreign_api_secret").arg(network));

    QString concatenatedOwner = username + ":" + passwordOwner;
    ownerAuth = "Basic " + concatenatedOwner.toUtf8().toBase64();

    QString concatenatedForeign = username + ":" + passwordForeign;
    foreignAuth = "Basic " + concatenatedForeign.toUtf8().toBase64();

    // Node Owner Api Instance
    NodeOwnerApi *nodeOwnerApi = new NodeOwnerApi(ownerUrl, ownerAuth);

    // Node Foreign Api Instance
    NodeForeignApi *nodeForeignApi = new NodeForeignApi(foreignUrl, foreignAuth);

    // -----------------------------------------------------------------------------------------------------------------------
    // Start qml engine
    // -----------------------------------------------------------------------------------------------------------------------
    QQmlApplicationEngine engine;
    // qml context objects
    engine.rootContext()->setContextProperty("nodeForeignApi", nodeForeignApi);
    engine.rootContext()->setContextProperty("nodeOwnerApi", nodeOwnerApi);

    Config config;
    config.loadFromNetwork(network);     // lädt ~/.grin/main/grin-server.toml

    QString dbroot = config.value("server.db_root", "/default/path").toString();
    qDebug() << "db_root =" << dbroot;

    engine.rootContext()->setContextProperty("config", &config);

    engine.load(QUrl(QStringLiteral("qrc:/qml/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    nodeOwnerApi->startStatusPolling(10000);
    nodeOwnerApi->startConnectedPeersPolling(5000);

    return app.exec();
}
