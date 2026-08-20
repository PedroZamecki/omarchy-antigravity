import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null
  property var manifest: null

  readonly property int refreshIntervalSec: 120

  // The collector resolves via PATH: install.sh copies it to ~/.local/bin,
  // mirroring how packaged collectors (omarchy-agent-usage-fireworks, ...)
  // are invoked by bare name from their services.
  readonly property string collectorCommand: "omarchy-agent-usage-antigravity"

  Component.onCompleted: runCollector()

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.runCollector()
  }

  function runCollector() {
    if (collectorProcess.running) return
    collectorProcess.command = [collectorCommand]
    collectorProcess.running = true
  }

  Process {
    id: collectorProcess
    onExited: function(exitCode) {
      console.log("zamecki.antigravity: usage record updated (exit " + exitCode + ")")
    }
  }
}