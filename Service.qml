import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"
  readonly property string pluginDir: manifest && manifest.__sourceDir ? manifest.__sourceDir : (home + "/.config/omarchy/plugins/zamecki.antigravity")
  readonly property string collectorPath: pluginDir + "/bin/omarchy-agent-usage-antigravity"
  readonly property string historyFile: home + "/.gemini/antigravity-cli/history.jsonl"

  readonly property int refreshIntervalSec: 60

  // The menu row and the agents tab both name this family; loading it here keeps
  // it to the shell process instead of installing a system font.
  FontLoader {
    source: Qt.resolvedUrl("fonts/omarchy-antigravity.ttf")
  }

  Component.onCompleted: {
    installerProcess.command = ["bash", pluginDir + "/install.sh"]
    installerProcess.running = true
  }

  // Omarchy has no uninstall hook, so this stands in for one. The service is
  // destroyed both on shell shutdown and on disable/remove, and only the latter
  // has already flipped the plugin to disabled -- anything else, including not
  // being handed a registry, leaves the install alone.
  Component.onDestruction: {
    if (!pluginRegistry || pluginRegistry.isEnabled("zamecki.antigravity") !== false) return
    Quickshell.execDetached(["bash", pluginDir + "/uninstall.sh"])
  }

  Process {
    id: installerProcess
    running: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("zamecki.antigravity install: " + text.trim())
    }
    onExited: root.runCollector(true)
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

  // 1. React immediately when the Agents panel runs omarchy-agent-usage-update
  // (e.g. when opening the panel, pressing 'r', or clicking refresh).
  // Claude's file is updated by the upstream script, so watching it lets us
  // run the Antigravity collector in lockstep.
  FileView {
    id: claudeUsageWatch
    path: root.usageDir + "/claude.json"
    watchChanges: true
    printErrors: false
    onFileChanged: root.runCollector(true)
  }

  // 2. React immediately when the user interacts with agy (prompts, answers, auth)
  FileView {
    id: agyHistoryWatch
    path: root.historyFile
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