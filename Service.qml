import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"
  readonly property string collectorPath: home + "/.local/bin/omarchy-agent-usage-antigravity"
  readonly property string historyFile: home + "/.gemini/antigravity-cli/history.jsonl"

  readonly property int refreshIntervalSec: 60

  Component.onCompleted: runCollector(true)

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