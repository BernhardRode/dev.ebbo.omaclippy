import QtQuick
import Quickshell.Io
import "Quips.js" as Quips

// Owns exactly one thing: `currentQuip`. Getting a new one either shells out
// to the local `claude` CLI (Process + StdioCollector, same idiom as
// vstoms.netbird/Service.qml's statusProcess) or, when that's disabled,
// slow, missing, or fails, falls back to Quips.pickQuip(). The caller never
// has to know which path produced the line on screen.
//
// Two entry points share one agent-run implementation: requestQuip() for an
// unsolicited tip, ask(text) for a reply to something the user typed.
Item {
  id: root

  property var settings: ({})
  property string currentQuip: ""
  property bool loading: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property bool useAgentQuips: setting("useAgentQuips", true) === true
  readonly property string agentModel: String(setting("agentModel", "claude-haiku-4-5-20251001"))
  readonly property int agentTimeoutSec: (function() {
    var value = parseInt(String(root.setting("agentTimeoutSec", 12)), 10)
    if (!isFinite(value)) value = 12
    return Math.max(2, Math.min(30, value))
  })()

  function requestQuip() {
    runAgent(Quips.buildPrompt())
  }

  function ask(userText) {
    runAgent(Quips.buildAskPrompt(userText))
  }

  function runAgent(prompt) {
    if (!useAgentQuips) {
      useBankQuip()
      return
    }
    if (agentProcess.running) return // a request is already in flight

    loading = true
    agentProcess.command = ["claude", "-p", prompt, "--model", agentModel]
    agentProcess.running = true
    watchdog.interval = agentTimeoutSec * 1000
    watchdog.stop()
    watchdog.start()
  }

  function useBankQuip() {
    currentQuip = Quips.pickQuip(currentQuip)
    loading = false
  }

  Timer {
    id: watchdog
    repeat: false
    onTriggered: if (agentProcess.running) {
      // The CLI is either slow or hanging (e.g. no network, waiting on
      // auth). Kill it and fall back rather than leaving Clippy staring
      // into space indefinitely.
      agentProcess.running = false
      root.useBankQuip()
    }
  }

  Process {
    id: agentProcess
    running: false
    stdout: StdioCollector { id: agentStdout; waitForEnd: true }
    onExited: function(exitCode) {
      watchdog.stop()
      var clean = exitCode === 0 ? Quips.sanitizeAgentOutput(agentStdout.text) : ""
      if (clean.length > 0) {
        root.currentQuip = clean
        root.loading = false
      } else {
        root.useBankQuip()
      }
    }
  }
}
