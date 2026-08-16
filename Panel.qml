import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui

// Clippy: two states. Maximized -- top-center, large, the agent terminal
// underneath him -- or small: draggable, scroll-to-resize, wobbling and
// turning to face the cursor. Always visible (opened defaults true, and
// close() never fully hides him once summoned) on every connected monitor
// -- one instance per screen (Variants { model: Quickshell.screens }, the
// same pattern the shell's own bar uses), all sharing one maximize/session
// state but each with its own parked position/drag/gaze. Above all normal
// windows via the Overlay layer-shell layer. Clicking him or the bar icon
// flips maximize/minimize; see clippyClicked()/open()/close().
//
// The first maximize launches a real `claude` session (not a one-shot
// `claude -p` call) in ~/clippy, floating and centered via a paired
// Hyprland window rule (~/.config/hypr/hyprland.lua) -- see
// maximizeAndEnsureSession(). The session itself (a tmux session wrapping
// claude, see launchAgentSession()'s comment for why) is persistent across
// minimize/maximize toggling, but the *window* genuinely hides on minimize
// and reappears on maximize -- minimize() closes just the ghostty window,
// tmux keeps claude running underneath, and the next maximize reopens a
// window attached to that same tmux session. The paper is the "session
// exists" signal: appearPaper() when a session is first created, staying
// visible the whole time Clippy is minimized, and throwPaper() -- paper
// gone -- only when the session actually ends, i.e. the user closes the
// terminal themselves rather than going through Clippy (detected by
// polling, since we can't be told directly; see selfClosingTerminal for how
// that's told apart from Clippy's own minimize-close).
//
// True window focus/move-on-demand is not used anywhere in this file: all
// of it was tried and found broken on this machine -- see
// launchAgentSession()'s comment for the specifics. Everything here is
// built out of process spawn/kill instead, which is unaffected.
//
// blink()-while-thinking / triple-jump-when-done are driven by an
// IpcHandler (target "clippy") that Claude Code hooks call from inside that
// same session -- see thinking()/done() below and the README for the hook
// config (not installed by this plugin itself; it's a global
// ~/.claude/settings.json change, left for the user to opt into). Since
// there's one shared character-instances list, these broadcast to every
// monitor's Clippy at once.
//
// Bar icon (BarWidget.qml) reaches this via the shell's generic toggle:
//   omarchy-shell shell toggle dev.ebbo.omaclippy
// which alternately calls open()/close() -- redefined below to mean
// maximize/minimize, rather than show/hide, so the bar icon and clicking
// Clippy himself behave identically.
//
// Contract mirrors nosignal.quattrolitaire/Panel.qml: a plain `opened` bool,
// open(payloadJson)/close() functions, and self-restore against `shell` so a
// Loader rebuild while open doesn't silently drop him.
Item {
  id: root

  property bool opened: true
  property bool maximized: false
  readonly property string selfId: "dev.ebbo.omaclippy"
  property var settings: ({})

  property var shell: null
  onShellChanged: {
    if (!root.opened && root.shell && root.shell.openPanelIds
        && root.shell.openPanelIds[root.selfId] === true)
      root.open("{}")
  }

  // Deterministic, not a toggle: the shell tracks its own open/closed
  // belief and alternates these two calls on repeated bar-icon presses, so
  // each one just needs to reach a specific target state. (clippyClicked()
  // below, for clicking Clippy directly, is the real toggle -- it reads
  // current state since there's no separate shell-side tracking to stay in
  // sync with.) First-ever call also starts the session. close() never
  // hides him -- he's meant to always be visible -- it only means minimize.
  function open(payloadJson) {
    opened = true
    if (!root.maximized) root.maximizeAndEnsureSession()
  }

  function close() {
    root.minimize()
  }

  // Real, interactive `claude` session -- distinct from the old one-shot
  // `claude -p` quip flow. Runs in ~/clippy (created if missing) with
  // --dangerously-skip-permissions, since this is meant to run
  // autonomously as Clippy's own sandbox, not gate on approvals.
  //
  // claude runs inside a detached tmux session (not directly under
  // ghostty) specifically so the window can genuinely hide: minimize()
  // closes just the ghostty process, which only detaches the tmux client --
  // tmux itself (and claude within it) keeps running in the background,
  // invisible, exactly like a real minimize should behave. Maximizing again
  // reopens a ghostty window attached to that same tmux session via
  // `new-session -A` (attach-if-exists, else create) -- one call handles
  // both "first ever launch" and "every later reattach", no branching
  // needed in launchAgentSession() itself.
  //
  // Launched directly via `ghostty`, not the portable `omarchy launch
  // terminal` wrapper, specifically for `--title="Clippy Agent"`: the
  // paired Hyprland window rule (~/.config/hypr/hyprland.lua) that makes
  // this float and center needs a title to match *at window creation*
  // (float/size/move rules apply once, not on later title changes -- found
  // by testing that matching ghostty's later title "✳ Claude Code" never
  // worked, since that only appears after claude's TUI starts). Hardcodes
  // ghostty since that's what's actually installed here; `--class=`
  // would be the portable equivalent but silently no-ops on this GTK
  // ghostty build. That same fixed title is also what pkill -f targets in
  // minimize() to close only this window, and what the poll below matches
  // on to notice it's gone.
  //
  // True window focus/move-on-demand is not used anywhere in this file:
  // every dispatch call is broken on this machine (verified three ways
  // this session: `hyprctl dispatch`, a raw write to Hyprland's IPC socket,
  // and Quickshell's native Hyprland.dispatch, which failed to even load
  // as a QML type -- all hit the same Lua config bridge parse error, even
  // for something as simple as `movecursor`). Only spawning/killing a
  // process doesn't go through that path, so that's the one lever
  // available -- which is exactly why hiding the window is done by killing
  // the ghostty process outright (reopening a fresh one on maximize) rather
  // than any kind of true hide/show.
  readonly property string clippyHome: Quickshell.env("HOME") + "/clippy"
  readonly property string tmuxSessionName: "clippy"
  property bool hasSession: false
  // Set right before minimize() closes the window on purpose, so the poll
  // below -- which otherwise can't tell "Clippy closed this to hide it"
  // from "the user closed it themselves" -- knows to leave the session
  // alone instead of treating a self-inflicted close as the real end.
  property bool selfClosingTerminal: false

  function launchAgentSession() {
    Quickshell.execDetached(["mkdir", "-p", root.clippyHome])
    Quickshell.execDetached(["ghostty", "--title=Clippy Agent",
      "-e", "tmux", "new-session", "-A", "-s", root.tmuxSessionName,
      "-c", root.clippyHome,
      "env", "CLIPPY_AGENT=1", "claude", "--dangerously-skip-permissions"])
  }

  function maximizeAndEnsureSession() {
    root.selfClosingTerminal = false // any pending self-close is moot now that we're reopening
    var isFirstLaunch = !root.hasSession
    root.hasSession = true
    root.launchAgentSession() // idempotent: attaches if the tmux session already exists
    if (isFirstLaunch) root.forEachCharacter(function(c) { c.appearPaper() })
    root.maximized = true
  }

  // Closes just the ghostty window -- tmux (and claude within it) lives on
  // in the background, so the paper stays and the very next maximize just
  // reattaches to it. This is the "hide" half of hide/show; see the big
  // comment above launchAgentSession() for why a window kill+relaunch is
  // what stands in for a real hide here.
  function minimize() {
    root.selfClosingTerminal = true
    Quickshell.execDetached(["pkill", "-f", "title=Clippy Agent"])
    root.maximized = false
    // A settling hop: the reposition from the top-center dock back to the
    // parked spot is an instant margin flip, so give it a beat before the
    // single "I'm in place" jump reads right.
    minimizeJumpTimer.restart()
  }

  Timer {
    id: minimizeJumpTimer
    interval: 300
    onTriggered: root.forEachCharacter(function(c) { c.jump() })
  }

  // The real toggle (clicking Clippy himself, as opposed to the bar icon --
  // see open()/close() above for why those are deterministic instead).
  function clippyClicked() {
    if (root.maximized) root.minimize()
    else root.maximizeAndEnsureSession()
  }

  // Only polls while maximized -- i.e. while the window is *supposed* to be
  // open. Gating on hasSession alone (an earlier version of this) kept
  // polling through the entire minimized period too, where the window is
  // *always* closed on purpose; the very next tick after minimize() would
  // find it closed, find selfClosingTerminal already consumed by the first
  // tick, and wrongly fire the real-end path a few seconds into every
  // minimize -- killing the session it was supposed to be preserving.
  // Nothing needs watching while minimized: Clippy already knows the window
  // is closed, because he's the one who closed it.
  Timer {
    // 300ms: this poll is also the "user closed the terminal themselves"
    // detector that triggers the paper-throw, and a 2s interval made that
    // reaction feel laggy. hyprctl -j clients costs ~10ms, so polling fast
    // is cheap.
    interval: 300
    repeat: true
    running: root.hasSession && root.maximized
    onTriggered: if (!sessionCheckProcess.running) sessionCheckProcess.running = true
  }

  Process {
    id: sessionCheckProcess
    command: ["hyprctl", "-j", "clients"]
    running: false
    stdout: StdioCollector { id: sessionCheckStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0 || !root.hasSession) return
      var stillOpen = false
      try {
        var clients = JSON.parse(String(sessionCheckStdout.text || "[]"))
        for (var i = 0; i < clients.length; i++) {
          if (clients[i].title === "Clippy Agent") { stillOpen = true; break }
        }
      } catch (e) { return }
      if (stillOpen) return
      if (root.selfClosingTerminal) {
        // Clippy closed this window himself (minimize) -- tmux still has
        // the session alive, nothing more to do here.
        root.selfClosingTerminal = false
        return
      }
      // The user closed the terminal directly (Cmd+W, or it crashed) --
      // the one real end of the session. Tear the tmux session down too
      // (it would otherwise sit there detached forever) and this is the
      // one moment the paper visibly goes away.
      Quickshell.execDetached(["tmux", "kill-session", "-t", root.tmuxSessionName])
      root.hasSession = false
      root.maximized = false
      root.forEachCharacter(function(c) { c.throwPaper() })
    }
  }

  // --- Multi-monitor: one Clippy per screen ------------------------------
  //
  // windowInstances holds each per-screen delegate (see the Variants block
  // at the bottom), so shared root-level logic (hook reactions, gaze,
  // drag) can reach every instance without each of them needing a
  // globally-unique id, which Variants-created delegates can't have.
  property var windowInstances: []

  function forEachCharacter(fn) {
    for (var i = 0; i < root.windowInstances.length; i++) fn(root.windowInstances[i].character)
  }

  // --- Hook-driven reactions: real agent activity, not a toy timer -------
  //
  // omarchy-shell clippy thinking / omarchy-shell clippy done, called from
  // Claude Code hooks (UserPromptSubmit / Stop) inside the launched
  // session. Blinks at random while thinking, re-randomizing its own
  // interval each time so it doesn't read as a metronome; three jumps the
  // moment it's done. Broadcasts to every monitor's instance.
  property bool agentThinking: false
  property int jumpsRemaining: 0

  IpcHandler {
    target: "clippy"
    function thinking(): string {
      root.agentThinking = true
      return "ok"
    }
    // TEMP debug hook for visually inspecting maximize/minimize framing --
    // remove before calling this done.
    function debugClick(): string {
      root.clippyClicked()
      return "hasSession=" + root.hasSession + " maximized=" + root.maximized
    }
    function debugGaze(): string {
      if (root.windowInstances.length === 0) return "no instances"
      var w = root.windowInstances[0]
      return "w.x=" + w.x + " w.width=" + w.width +
        " screen.x=" + (w.screen ? w.screen.x : "null") +
        " screen.width=" + (w.screen ? w.screen.width : "null") +
        " floatX=" + w.floatX + " floatY=" + w.floatY +
        " terminalDockLeftMargin=" + w.terminalDockLeftMargin +
        " maximized=" + root.maximized + " floatSize=" + root.floatSize +
        " targetYaw=" + w.character.targetYaw +
        " gazeYaw=" + w.character.gazeYaw +
        " gazeYawSafe=" + w.character.gazeYawSafe +
        " targetPitch=" + w.character.targetPitch +
        " gazePitch=" + w.character.gazePitch
    }
    function done(): string {
      root.agentThinking = false
      root.forEachCharacter(function(c) { c.jump() })
      root.jumpsRemaining = 2
      return "ok"
    }
  }

  Timer {
    id: thinkingBlinkTimer
    running: root.agentThinking
    interval: 900
    repeat: true
    onTriggered: {
      root.forEachCharacter(function(c) { c.blink() })
      interval = 700 + Math.random() * 1300
    }
  }
  Timer {
    interval: 380
    repeat: true
    running: root.jumpsRemaining > 0
    onTriggered: {
      root.forEachCharacter(function(c) { c.jump() })
      root.jumpsRemaining -= 1
    }
  }

  // --- Cursor tracking, for "always tend to face the user" -------------
  //
  // No Wayland-native live cursor-position stream is wired up here, so this
  // polls `hyprctl cursorpos` (logical/scaled coordinates, matching Qt's own
  // coordinate space on this compositor) at a modest rate -- fast enough to
  // read as attentive, slow enough not to matter for one `hyprctl` call.
  // One shared poll drives every screen's instance (each computes its own
  // yaw from the same global position against its own geometry), rather
  // than duplicating the same poll per monitor.
  Timer {
    interval: 150
    repeat: true
    running: root.opened
    onTriggered: if (!cursorProcess.running) cursorProcess.running = true
  }

  Process {
    id: cursorProcess
    command: ["hyprctl", "cursorpos"]
    running: false
    stdout: StdioCollector { id: cursorStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var parts = String(cursorStdout.text || "").trim().split(",")
      if (parts.length !== 2) return
      var cx = parseFloat(parts[0])
      var cy = parseFloat(parts[1])
      if (!isFinite(cx) || !isFinite(cy)) return
      root.updateGaze(cx, cy)
    }
  }

  readonly property real maxYawDegrees: 40
  readonly property real maxPitchDegrees: 20

  function updateGaze(cursorX, cursorY) {
    for (var i = 0; i < root.windowInstances.length; i++) {
      var w = root.windowInstances[i]
      // w's geometry is mid-resize/reanchor for a frame or two right as
      // maximized flips (parked position <-> top-center dock), during
      // which x/width can read as 0 or otherwise not-yet-resolved. A yaw
      // computed from that is garbage (found this by testing: the eyes
      // vanished entirely -- a NaN rotation quaternion, not a
      // framing/clipping issue as it first looked like). Skip that
      // instance's update rather than feed it a bad value.
      if (!(w.width > 0)) continue
      var screenW = w.screen ? w.screen.width : Screen.width
      if (!(screenW > 0)) continue
      var centerX = w.x + w.width / 2
      var dx = cursorX - centerX
      var yaw = (dx / (screenW / 2)) * root.maxYawDegrees
      if (!isFinite(yaw)) continue
      w.character.targetYaw = Math.max(-root.maxYawDegrees, Math.min(root.maxYawDegrees, yaw))
      // Vertical counterpart, same shape as the yaw above: cursor below
      // Clippy's center looks down (positive pitch -- see quatFromXAxisAngle).
      if (!(w.height > 0)) continue
      var screenH = w.screen ? w.screen.height : Screen.height
      if (!(screenH > 0)) continue
      var centerY = w.y + w.height / 2
      var dy = cursorY - centerY
      var pitch = (dy / (screenH / 2)) * root.maxPitchDegrees
      if (!isFinite(pitch)) continue
      w.character.targetPitch = Math.max(-root.maxPitchDegrees, Math.min(root.maxPitchDegrees, pitch))
    }
  }

  // --- Dragging, driven by the same global-cursor-poll approach as gaze
  // tracking above, but much faster and only while a drag is in progress.
  // Only one screen's instance can be dragged at a time (draggingWindow).
  //
  // A first version computed deltas from the MouseArea's own *local*
  // mouse.x/y and relied on the window "catching up" to keep them stable --
  // the standard trick for dragging a plain QML Item. It doesn't hold for
  // an actual Wayland layer-shell surface: repositioning one is a real
  // compositor round-trip, not an instant same-frame property change, so
  // several more pointer-motion events land before the surface visually
  // moves. Those get read as extra delta on top of the real movement, and
  // the loop compounds into visible jitter. Global cursor position has no
  // such feedback: it's completely independent of where our own window
  // currently is.
  property var draggingWindow: null
  property bool dragHaveLast: false
  property real dragLastGlobalX: 0
  property real dragLastGlobalY: 0

  Timer {
    interval: 20
    repeat: true
    running: root.draggingWindow !== null
    onTriggered: if (!dragCursorProcess.running) dragCursorProcess.running = true
  }

  Process {
    id: dragCursorProcess
    command: ["hyprctl", "cursorpos"]
    running: false
    stdout: StdioCollector { id: dragCursorStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0 || root.draggingWindow === null) return
      var parts = String(dragCursorStdout.text || "").trim().split(",")
      if (parts.length !== 2) return
      var gx = parseFloat(parts[0])
      var gy = parseFloat(parts[1])
      if (!isFinite(gx) || !isFinite(gy)) return
      var w = root.draggingWindow
      if (root.dragHaveLast) {
        var sw = w.screen ? w.screen.width : 1920
        var sh = w.screen ? w.screen.height : 1080
        w.floatX = Math.max(0, Math.min(sw - root.floatSize, w.floatX + (gx - root.dragLastGlobalX)))
        w.floatY = Math.max(0, Math.min(sh - root.floatSize, w.floatY + (gy - root.dragLastGlobalY)))
      }
      root.dragLastGlobalX = gx
      root.dragLastGlobalY = gy
      root.dragHaveLast = true
    }
  }

  // --- Sizing shared across every monitor's instance ---------------------
  readonly property int floatMargin: Style.gapsOut
  readonly property real minFloatSize: Style.space(160)
  readonly property real maxFloatSize: Style.space(560)
  property real floatSize: Style.space(250)
  readonly property int terminalDockSize: Style.space(264)
  // Geometry of the agent terminal, matching the paired Hyprland window
  // rule in ~/.config/hypr/hyprland.lua (900x650, centered) -- Clippy's
  // maximized dock is framed relative to that window: horizontally
  // centered over it, sitting just above its top edge.
  readonly property int agentTermWidth: 900
  readonly property int agentTermHeight: 650
  readonly property real terminalDockGap: Style.space(20)

  // One Clippy per connected monitor. Each carries its own parked
  // position/drag state; maximize/session state above is shared.
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: floatWindow
        required property var modelData
        screen: modelData

        property real floatX: -1 // sentinel: not yet initialized from screen size
        property real floatY: -1
        readonly property real terminalDockLeftMargin: Math.max(0, (screen.width - root.terminalDockSize) / 2)
        readonly property real terminalDockTopMargin: Math.max(0,
          (screen.height - root.agentTermHeight) / 2 - root.terminalDockGap - root.terminalDockSize)
        property alias character: characterItem

        visible: root.opened
        implicitWidth: root.maximized ? root.terminalDockSize : root.floatSize
        implicitHeight: root.maximized ? root.terminalDockSize : root.floatSize
        anchors { top: true; left: true }
        margins {
          left: root.maximized ? floatWindow.terminalDockLeftMargin : floatWindow.floatX
          top: root.maximized ? floatWindow.terminalDockTopMargin : floatWindow.floatY
        }
        color: "transparent"
        WlrLayershell.namespace: "io-rode-clippy"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        Component.onCompleted: {
          floatX = screen.width - root.floatSize - root.floatMargin
          floatY = screen.height - root.floatSize - root.floatMargin
          root.windowInstances.push(floatWindow)
        }
        Component.onDestruction: {
          var idx = root.windowInstances.indexOf(floatWindow)
          if (idx >= 0) root.windowInstances.splice(idx, 1)
        }

        ClippyCharacter {
          id: characterItem
          anchors.fill: parent
          zoomed: root.maximized

          MouseArea {
            id: dragArea
            anchors.fill: parent
            property real pressFloatX: 0
            property real pressFloatY: 0

            onPressed: function(mouse) {
              if (root.maximized) return
              pressFloatX = floatWindow.floatX
              pressFloatY = floatWindow.floatY
              root.dragHaveLast = false
              root.draggingWindow = floatWindow
            }
            onReleased: {
              root.draggingWindow = null
              var moved = Math.abs(floatWindow.floatX - pressFloatX) + Math.abs(floatWindow.floatY - pressFloatY)
              if (moved < 6) root.clippyClicked()
            }

            // Scroll to resize, only while parked (not flown-in over the
            // terminal, where his size is fixed to frame the zoomed
            // close-up). Grows/shrinks around his current visual center
            // rather than his top-left corner, by absorbing half the size
            // delta into floatX/Y. floatSize is shared across monitors, so
            // resizing on one screen resizes him everywhere.
            onWheel: function(wheel) {
              if (root.maximized) return
              var delta = wheel.angleDelta.y > 0 ? 12 : -12
              var newSize = Math.max(root.minFloatSize, Math.min(root.maxFloatSize, root.floatSize + delta))
              var actualDelta = newSize - root.floatSize
              floatWindow.floatX -= actualDelta / 2
              floatWindow.floatY -= actualDelta / 2
              root.floatSize = newSize
            }
          }
        }
      }
    }
  }
}
