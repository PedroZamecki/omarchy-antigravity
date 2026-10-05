import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: manifest && manifest.__sourceDir ? manifest.__sourceDir : (home + "/.config/omarchy/plugins/zamecki.antigravity")
  readonly property string collectorPath: pluginDir + "/bin/omarchy-agent-usage-antigravity"
  readonly property string historyFile: home + "/.gemini/antigravity-cli/history.jsonl"
  readonly property string cliConversationsDir: home + "/.gemini/antigravity-cli/conversations"
  readonly property string acpConversationsDir: home + "/.gemini/antigravity-acp/conversations"

  // Local stats are cheap and also refresh on every agy write below; live limits
  // are cached by the collector, so a slow tick costs nothing between agy runs.
  readonly property int refreshIntervalSec: 300

  // The menu row and the agents tab both name this family; loading it here keeps
  // it to the shell process instead of installing a system font.
  FontLoader {
    source: Qt.resolvedUrl("fonts/omarchy-antigravity.ttf")
  }

  Component.onCompleted: {
    installerProcess.command = ["bash", pluginDir + "/install.sh"]
    installerProcess.running = true
  }

  Process {
    id: installerProcess
    running: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("zamecki.antigravity install: " + text.trim())
    }
    onExited: root.runCollector(false)
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.runCollector(false)
  }

  Timer {
    id: debounceTimer
    interval: 1000
    repeat: false
    onTriggered: root.runCollector(false)
  }

  // Panel refreshes reach the collector through the omarchy-agent-usage-update
  // shim; this covers the user working in agy or ACP between them.
  FileView {
    id: agyHistoryWatch
    path: root.historyFile
    watchChanges: true
    printErrors: false
    onFileChanged: debounceTimer.restart()
  }

  FileView {
    id: cliConversationsWatch
    path: root.cliConversationsDir
    watchChanges: true
    printErrors: false
    onFileChanged: debounceTimer.restart()
  }

  FileView {
    id: acpConversationsWatch
    path: root.acpConversationsDir
    watchChanges: true
    printErrors: false
    onFileChanged: debounceTimer.restart()
  }

  function runCollector(force) {
    if (collectorProcess.running) return
    var cmd = ["python3", collectorPath, "--write"]
    if (force === true) cmd.push("--force")
    collectorProcess.command = cmd
    collectorProcess.running = true
  }

  Process {
    id: collectorProcess
    running: false

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("zamecki.antigravity", text.trim())
    }

    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("zamecki.antigravity: collector failed with exit " + exitCode)
      }
    }
  }
}