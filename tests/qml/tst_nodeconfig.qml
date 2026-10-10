import QtQuick
import QtTest
import "../../qml" as App
TestCase {
    name: "NodeConfig"
    QtObject {
        id: nodeOwnerApi
        property int calls: 0
        signal apiUrlChanged()
        signal apiKeyChanged()
        signal getConfigFinished(var config, string error)
        function getConfigAsync() { calls++ }
    }
    property string walletBaseUrl: "https://umbrel.local:13410/wallet"
    QtObject { id: settings; property string controllerPassword: "review-only" }
    App.Wallet { id: wallet; width: 640; height: 480; settingsStore: settings }
    function test_wallet() {
        compare(wallet.defaultIpPort, walletBaseUrl)
        compare(JSON.parse(wallet.walletJson()).secret, settings.controllerPassword)
        settings.controllerPassword = "updated-review-password"
        compare(JSON.parse(wallet.walletJson()).secret, settings.controllerPassword)
    }
    App.NodeConfig { id: page; width: 640; height: 480 }
    function test_states() {
        page.nodeState = "rust"
        page.pageActive = true
        page.refresh()
        compare(nodeOwnerApi.calls, 0)
        page.nodeState = "grinpp"
        compare(nodeOwnerApi.calls, 1)
        nodeOwnerApi.getConfigFinished({port: 3413}, "")
        verify(page.configText.indexOf("3413") >= 0)
        page.refresh()
        compare(nodeOwnerApi.calls, 2)
        page.nodeState = "rust"
        compare(page.configText, "")
        nodeOwnerApi.getConfigFinished({port: 9999}, "")
        compare(page.configText, "")
        compare(nodeOwnerApi.calls, 2)
        page.nodeState = "grinpp"
        compare(nodeOwnerApi.calls, 3)
        nodeOwnerApi.apiUrlChanged()
        nodeOwnerApi.getConfigFinished({port: 9999}, "")
        compare(page.configText, "")
        compare(nodeOwnerApi.calls, 4)
        nodeOwnerApi.getConfigFinished({port: 3413}, "")
        verify(page.configText.indexOf("3413") >= 0)
    }
}
