#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>

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
 * @brief qMain
 * @param argc
 * @param argv
 * @return
 */
int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    app.setWindowIcon(QIcon(":/res/media/logo.png"));

    registerAllMetaTypes();

    qmlRegisterType<GeoLookup>("Geo", 1, 0, "GeoLookup");

    bool local = false;
    QString ownerUrl;
    QString ownerAuth;
    QString foreignUrl;
    QString foreignAuth;

    // local
    if (local) {
        ownerUrl = "http://192.168.178.72:13413/v2/owner";
        ownerAuth = "Basic Z3JpbjptVUtqbEpBdmJuR0VVeWZYdFF3Sw==";
        foreignUrl = "http://192.168.178.72:13413/v2/foreign";
        foreignAuth = "Basic Z3JpbjpkN2lxbXBDa1NLWWpzY1RDZU9rcw==";
    } else {
        ownerUrl = "https://grincoin.org/v2/owner";
        ownerAuth = QString();
        foreignUrl = "https://grincoin.org/v2/foreign";
        foreignAuth = QString();
    }

    // Node Owner Api Instance
    NodeOwnerApi *nodeOwnerApi = new NodeOwnerApi(ownerUrl, ownerAuth);

    // Node Foreign Api Instance
    NodeForeignApi *nodeForeignApi = new NodeForeignApi(foreignUrl, foreignAuth);

    QQmlApplicationEngine engine;
    // NodeApi als Kontextobjekt für QML zugänglich machen
    engine.rootContext()->setContextProperty("nodeForeignApi", nodeForeignApi);
    engine.rootContext()->setContextProperty("nodeOwnerApi", nodeOwnerApi);

    engine.load(QUrl(QStringLiteral("qrc:/qml/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    nodeOwnerApi->startStatusPolling(10000);
    nodeOwnerApi->startConnectedPeersPolling(5000);

    return app.exec();
}
