import QtQuick
import QtTest
import Grin 1.0
import "../../qml" as App

TestCase {
    name: "Home"
    QtObject {
        id: nodeOwnerApi
        signal statusUpdated(var status)
        function startStatusPolling(interval) {}
        function stopStatusPolling() {}
        function startConnectedPeersPolling(interval) {}
        function stopConnectedPeersPolling() {}
    }
    QtObject {
        id: manager
        property string lastResponse: ""
        signal nodeStarted(int kind)
        signal nodeStopped(int kind)
        signal nodeRestarted(int kind)
        signal statusReceived(var status)
        signal errorOccurred(string message)
        function startStatusPolling(interval) {}
    }
    App.Home { id: page; width: 900; height: 700; nodeManager: manager }

    function test_stop_data() {
        return [{tag: "rust", kind: GrinNodeManager.Rust, id: "rust"},
                {tag: "grinpp", kind: GrinNodeManager.GrinPP, id: "grinpp"}]
    }

    function test_stop(data) {
        var nodes = {rust: {running: false}, grinpp: {running: false}}
        nodes[data.id].running = true
        manager.statusReceived({nodes: nodes})
        nodeOwnerApi.statusUpdated({height: 123})
        verify(page.directNodeApiReachable)
        page.requestInFlight = true
        manager.nodeStopped(data.kind)
        compare(page.nodeState, "none")
        verify(!page.requestInFlight)
        verify(page.controllerActionsAvailable)

        // An outstanding node reply must not revive a stopped node.
        nodeOwnerApi.statusUpdated({height: 123})
        compare(page.nodeState, "none")
        nodes[data.id].running = false
        manager.statusReceived({nodes: nodes})
        compare(page.nodeState, "none")
        verify(!page.directNodeApiReachable)
        manager.nodeStarted(data.kind)
        compare(page.nodeState, data.id)
    }

    function test_external_node() {
        page.controllerReachable = false
        page.nodeState = "none"
        nodeOwnerApi.statusUpdated({height: 123})
        compare(page.nodeState, "external")
        verify(page.directNodeApiReachable)
        manager.statusReceived({nodes: {rust: {running: false}, grinpp: {running: false}}})
        compare(page.nodeState, "none")
    }

    function test_stop_error_after_node_reply() {
        manager.statusReceived({nodes: {rust: {running: true}}})
        nodeOwnerApi.statusUpdated({height: 123})
        for (var attempt = 0; attempt < 2; ++attempt) {
            page.requestInFlight = true
            manager.errorOccurred("Request timed out")
            verify(!page.requestInFlight)
            verify(page.controllerError)
            verify(!page.controllerActionsAvailable)
        }
        manager.statusReceived({nodes: {rust: {running: false}}})
        verify(page.controllerActionsAvailable)
        compare(page.nodeState, "none")
    }

    function test_unrelated_reply_during_stop() {
        manager.statusReceived({nodes: {rust: {running: true}}})
        page.requestInFlight = true
        manager.lastResponse = "unrelated log response"
        verify(page.requestInFlight)
        manager.nodeStopped(GrinNodeManager.Rust)
        verify(!page.requestInFlight)
    }
}
