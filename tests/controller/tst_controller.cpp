#include "grinnodemanager.h"
#include <QtTest>

// Run against an isolated controller: this test starts and stops its Rust node.
class ControllerTest : public QObject
{
    Q_OBJECT
private slots:
    void lifecycle()
    {
        const auto url = qEnvironmentVariable("CONTROLLER_TEST_URL");
        if (url.isEmpty())
            QSKIP("Set CONTROLLER_TEST_URL to an isolated controller or UI proxy");

        GrinNodeManager manager;
        manager.setBaseUrl(QUrl(url));
        manager.setUsername("grin");
        manager.setPassword(qEnvironmentVariable("CONTROLLER_TEST_PASSWORD"));
        QSignalSpy status(&manager, &GrinNodeManager::statusReceived);
        QSignalSpy started(&manager, &GrinNodeManager::nodeStarted);
        QSignalSpy stopped(&manager, &GrinNodeManager::nodeStopped);
        QSignalSpy restarted(&manager, &GrinNodeManager::nodeRestarted);
        QSignalSpy errors(&manager, &GrinNodeManager::errorOccurred);

        manager.startStatusPolling(1000);
        manager.getStatus();
        QTRY_VERIFY_WITH_TIMEOUT(status.count() >= 2, 5000);
        for (int cycle = 1; cycle <= 2; ++cycle) {
            manager.startRust();
            QTRY_COMPARE_WITH_TIMEOUT(started.count(), cycle, 15000);
            QTest::qWait(2000);
            manager.stopRust();
            QTRY_COMPARE_WITH_TIMEOUT(stopped.count(), cycle, 15000);
            manager.getStatus();
            const int count = status.count();
            QTRY_VERIFY_WITH_TIMEOUT(status.count() > count, 5000);
            const auto state = qvariant_cast<QJsonObject>(status.last().at(0));
            const auto running = state["nodes"].toObject()["rust"].toObject()["running"];
            QVERIFY(running.isBool());
            QVERIFY(!running.toBool());
        }
        manager.restartRust();
        QTRY_COMPARE_WITH_TIMEOUT(restarted.count(), 1, 15000);
        QCOMPARE(started.count(), 2);
        manager.stopRust();
        QTRY_COMPARE_WITH_TIMEOUT(stopped.count(), 3, 15000);
        QCOMPARE(errors.count(), 0);
    }
};

QTEST_GUILESS_MAIN(ControllerTest)
#include "tst_controller.moc"
