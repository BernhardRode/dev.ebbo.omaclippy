import QtQuick
import QtQuick3D
import "assets/model"

// Live 3D viewport for Clippy, built from assets/model/Clippy.qml -- the
// glTF export run through Qt's `balsam` asset conditioner, which turns it
// into a native QML scene with addressable nodes instead of an opaque
// RuntimeLoader blob. That's what makes everything below possible:
//
// - `clippyModel.characterNode` (aliased to the armature root) carries the
//   idle wobble/gaze-yaw/jump motion. `clippyModel.paperNode` (a separate,
//   unskinned top-level mesh -- the sheet of paper, not part of the
//   armature at all) is left alone, so jumping doesn't move the paper.
// - `clippyModel.eyelidUpperR` / `eyelidLowerR` are real bones. blink()
//   animates them from their authored rest quaternion to the closed-eye
//   quaternion the artist baked into the model's own "ArmatureAction"
//   keyframes (read out of assets/model/Clippy.qml's Timeline and reused
//   here) -- a real one-eye wink, not a whole-body stand-in.
Item {
  id: root

  property real targetYaw: 0 // degrees, set by the owner from cursor position
  property real targetPitch: 0 // degrees, set by the owner from cursor position
  property bool zoomed: false // true while the talk dialog is open
  readonly property bool modelReady: loadTimer.fired

  function jump() { jumpAnim.restart() }
  function blink() { blinkAnim.restart() }
  function kickPaper() { kickPaperAnim.restart() } // crush+throw+reappear, all in one
  function throwPaper() { throwPaperAnim.restart() } // crush+throw only, ends empty
  function appearPaper() { appearPaperAnim.restart() } // pop-in from empty

  Timer { id: loadTimer; interval: 0; running: true; property bool fired: false; onTriggered: fired = true }

  // Distance 7 clipped the maximized framing at the bottom (the paper's
  // decoded world bbox bottoms out at y=-2.76; distance 7 only showed down
  // to y=-2.44). Backing off to 10 drops the viewport bottom to ~-4.2 so
  // nothing is ever cut off -- deliberately solving this with camera
  // distance alone rather than shifting the model up, which made him
  // intersect the paper.
  readonly property real cameraDistance: root.zoomed ? 10 : 15
  readonly property real cameraY: 1.6

  readonly property real wobbleRange: 0.35
  SequentialAnimation on wobbleX {
    loops: Animation.Infinite
    running: root.modelReady
    NumberAnimation { to: root.wobbleRange; duration: 2600; easing.type: Easing.InOutSine }
    NumberAnimation { to: -root.wobbleRange; duration: 2600; easing.type: Easing.InOutSine }
  }
  SequentialAnimation on wobbleY {
    loops: Animation.Infinite
    running: root.modelReady
    NumberAnimation { to: root.wobbleRange * 0.7; duration: 3300; easing.type: Easing.InOutSine }
    NumberAnimation { to: -root.wobbleRange * 0.7; duration: 3300; easing.type: Easing.InOutSine }
  }
  SequentialAnimation on wobbleTilt {
    loops: Animation.Infinite
    running: root.modelReady
    NumberAnimation { to: 1.5; duration: 4100; easing.type: Easing.InOutSine }
    NumberAnimation { to: -1.5; duration: 4100; easing.type: Easing.InOutSine }
  }
  property real wobbleX: 0
  property real wobbleY: 0
  property real wobbleTilt: 0

  // Smoothed turn toward targetYaw instead of snapping every cursor tick.
  // Drives only the eyes (see the eyeL/eyeR Bindings below) -- the body's
  // own motion is wobble/jump only, decoupled from where the cursor is.
  property real gazeYaw: 0
  Behavior on gazeYaw { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
  onTargetYawChanged: gazeYaw = targetYaw

  // Vertical counterpart of the smoothed yaw above: same easing, applied
  // around the eyes' local X axis so they tilt up/down toward the cursor.
  property real gazePitch: 0
  Behavior on gazePitch { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
  onTargetPitchChanged: gazePitch = targetPitch

  property real jumpOffset: 0
  SequentialAnimation {
    id: jumpAnim
    NumberAnimation { target: root; property: "jumpOffset"; to: 1.3; duration: 180; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "jumpOffset"; to: 0; duration: 260; easing.type: Easing.OutBounce }
  }

  // Rest/closed quaternions lifted from this exact model's own baked
  // "ArmatureAction" Timeline (assets/model/Clippy.qml) -- the artist's own
  // closed-eyelid pose for the right eye, not a guessed rotation.
  readonly property quaternion upperRRest: Qt.quaternion(-0.180566, -0.182417, 0.683664, 0.683172)
  readonly property quaternion upperRClosed: Qt.quaternion(0.192441, 0.0835987, -0.895793, -0.391832)
  readonly property quaternion lowerRRest: Qt.quaternion(-0.180839, 0.182141, 0.684695, -0.68214)
  readonly property quaternion lowerRClosed: Qt.quaternion(0.180839, -0.182141, -0.684695, 0.68214)

  property real blinkProgress: 0 // 0 = open, 1 = fully closed
  SequentialAnimation {
    id: blinkAnim
    NumberAnimation { target: root; property: "blinkProgress"; to: 1; duration: 90; easing.type: Easing.OutQuad }
    PauseAnimation { duration: 90 }
    NumberAnimation { target: root; property: "blinkProgress"; to: 0; duration: 150; easing.type: Easing.OutQuad }
  }

  // Kick the paper away, then a fresh one pops in. paperNode has no morph
  // targets any more than anything else here does (same RuntimeLoader-era
  // limitation noted at the top of the file, just via balsam's Model now
  // instead), so "crushed" is a fast squash rather than real crumpling --
  // reads fine at this speed and size.
  readonly property vector3d paperOffset0: Qt.vector3d(0, 0, 0)
  property vector3d paperOffset: paperOffset0
  property real paperScaleFactor: 1
  property real paperSpin: 0
  SequentialAnimation {
    id: kickPaperAnim
    ParallelAnimation {
      // Crush.
      NumberAnimation { target: root; property: "paperScaleFactor"; to: 0.3; duration: 140; easing.type: Easing.InQuad }
      NumberAnimation { target: root; property: "paperSpin"; to: 40; duration: 140; easing.type: Easing.InQuad }
    }
    ParallelAnimation {
      // Kicked away: flies off to the side, tumbling.
      NumberAnimation {
        target: root; property: "paperOffset"; duration: 380; easing.type: Easing.OutQuad
        to: Qt.vector3d(root.paperOffset0.x + 7, root.paperOffset0.y + 3.5, root.paperOffset0.z + 1.5)
      }
      NumberAnimation { target: root; property: "paperSpin"; to: 640; duration: 380; easing.type: Easing.OutQuad }
    }
    PauseAnimation { duration: 180 } // beat of "gone" before the new one appears
    PropertyAction { target: root; property: "paperOffset"; value: root.paperOffset0 }
    PropertyAction { target: root; property: "paperSpin"; value: 0 }
    PropertyAction { target: root; property: "paperScaleFactor"; value: 0 }
    // Magically appears.
    NumberAnimation { target: root; property: "paperScaleFactor"; to: 1; duration: 320; easing.type: Easing.OutBack }
  }

  // Split versions of the same two halves, for callers that want the throw
  // and the reappearance as two separate, independently-timed events (e.g.
  // "throw on minimize, new one only once maximized again") rather than
  // back-to-back.
  SequentialAnimation {
    id: throwPaperAnim
    ParallelAnimation {
      NumberAnimation { target: root; property: "paperScaleFactor"; to: 0.3; duration: 140; easing.type: Easing.InQuad }
      NumberAnimation { target: root; property: "paperSpin"; to: 40; duration: 140; easing.type: Easing.InQuad }
    }
    ParallelAnimation {
      NumberAnimation {
        target: root; property: "paperOffset"; duration: 380; easing.type: Easing.OutQuad
        to: Qt.vector3d(root.paperOffset0.x + 7, root.paperOffset0.y + 3.5, root.paperOffset0.z + 1.5)
      }
      NumberAnimation { target: root; property: "paperSpin"; to: 640; duration: 380; easing.type: Easing.OutQuad }
    }
    PropertyAction { target: root; property: "paperOffset"; value: root.paperOffset0 }
    PropertyAction { target: root; property: "paperSpin"; value: 0 }
    PropertyAction { target: root; property: "paperScaleFactor"; value: 0 }
  }
  SequentialAnimation {
    id: appearPaperAnim
    PropertyAction { target: root; property: "paperScaleFactor"; value: 0 }
    NumberAnimation { target: root; property: "paperScaleFactor"; to: 1; duration: 320; easing.type: Easing.OutBack }
  }

  View3D {
    anchors.fill: parent
    visible: root.modelReady
    environment: SceneEnvironment {
      backgroundMode: SceneEnvironment.Transparent
      antialiasingMode: SceneEnvironment.MSAA
      antialiasingQuality: SceneEnvironment.High
    }

    PerspectiveCamera {
      z: root.cameraDistance
      y: root.cameraY
      // Default clipNear (~10) exceeds the zoomed-in cameraDistance, which
      // culls the whole scene as "behind the near plane" -- found by
      // testing the zoomed camera and getting a blank render. Default
      // clipFar (~10000) is wildly oversized for a model this small, which
      // leaves almost no depth-buffer precision for the tightly-packed
      // eyeball/eyelid/eyebrow geometry -- that's what read as flicker when
      // zoomed in. Tightening both fixes it.
      // The eyes protrude further toward the camera than anything else on
      // the head, so a clipNear that's fine for the rest of the geometry
      // can still slice the eyes off specifically at close zoom -- found by
      // testing dialog mode: eyebrows/loop/paper rendered, eyes vanished
      // entirely. Cut much closer in.
      clipNear: 0.1
      clipFar: 60
    }
    DirectionalLight { eulerRotation.x: -30; eulerRotation.y: -30 }
    DirectionalLight { eulerRotation.x: 30; eulerRotation.y: 150; brightness: 0.35 }

    Clippy {
      id: clippyModel
    }
  }

  Binding {
    target: clippyModel.characterNode
    property: "position"
    value: Qt.vector3d(root.wobbleX, root.wobbleY + root.jumpOffset, 0)
  }
  Binding {
    target: clippyModel.characterNode
    property: "eulerRotation"
    value: Qt.vector3d(0, 0, root.wobbleTilt)
  }

  // Eye tracking: only the eyeballs (which carry the pupils) turn toward
  // the cursor, layered on top of each eye's own authored rest orientation
  // -- not the whole body, and not tied to the wobble idle motion.
  readonly property quaternion eyeLRest: Qt.quaternion(0.0984822, -0.182417, 0.700215, 0.683172)
  readonly property quaternion eyeRRest: Qt.quaternion(0.14823, 0.182417, 0.691396, -0.683172)
  readonly property real maxGazeEyeDegrees: 20
  readonly property real maxGazeEyePitchDegrees: 15
  // Root cause of the vanishing-eyes bug was upstream (Panel.qml's
  // updateGaze could feed a NaN yaw in while floatWindow was mid-resize),
  // fixed there -- gazeYawSafe/gazePitchSafe are a second layer so a
  // degenerate rotation can never make it onto the eyes again regardless.
  readonly property real gazeYawSafe: isFinite(root.gazeYaw) ? root.gazeYaw : 0
  readonly property real gazePitchSafe: isFinite(root.gazePitch) ? root.gazePitch : 0
  Binding {
    target: clippyModel.eyeL
    property: "rotation"
    value: root.quatMultiply(
      root.quatMultiply(root.eyeLRest, root.quatFromYAxisAngle(root.gazeYawSafe / root.maxYawDegrees * root.maxGazeEyeDegrees)),
      root.quatFromXAxisAngle(root.gazePitchSafe / root.maxPitchDegrees * root.maxGazeEyePitchDegrees))
  }
  Binding {
    target: clippyModel.eyeR
    property: "rotation"
    value: root.quatMultiply(
      root.quatMultiply(root.eyeRRest, root.quatFromYAxisAngle(root.gazeYawSafe / root.maxYawDegrees * root.maxGazeEyeDegrees)),
      root.quatFromXAxisAngle(root.gazePitchSafe / root.maxPitchDegrees * root.maxGazeEyePitchDegrees))
  }
  readonly property real maxYawDegrees: 40 // matches Panel.qml's maxYawDegrees; gazeYaw arrives already clamped to this range
  readonly property real maxPitchDegrees: 20 // matches Panel.qml's maxPitchDegrees; gazePitch arrives already clamped to this range

  // Paper: rest pose lifted verbatim from assets/model/Clippy.qml's `plane`
  // node. kickPaper()'s offset/scale/spin above are deltas layered on top
  // of these, the same pattern as the eyes.
  readonly property vector3d paperRestPosition: Qt.vector3d(-0.44973, -2.09428, -1.1451)
  readonly property vector3d paperRestScale: Qt.vector3d(1.93433, 1.39443, 1.50199)
  readonly property quaternion paperRestRotation: Qt.quaternion(0.92629, 0.264144, -0.267765, 0.0227203)
  Binding {
    target: clippyModel.paperNode
    property: "position"
    value: Qt.vector3d(
      root.paperRestPosition.x + root.paperOffset.x,
      root.paperRestPosition.y + root.paperOffset.y,
      root.paperRestPosition.z + root.paperOffset.z)
  }
  Binding {
    target: clippyModel.paperNode
    property: "scale"
    value: Qt.vector3d(
      root.paperRestScale.x * root.paperScaleFactor,
      root.paperRestScale.y * root.paperScaleFactor,
      root.paperRestScale.z * root.paperScaleFactor)
  }
  Binding {
    target: clippyModel.paperNode
    property: "rotation"
    value: root.quatMultiply(root.paperRestRotation, root.quatFromYAxisAngle(root.paperSpin))
  }
  Binding {
    target: clippyModel.eyelidUpperR
    property: "rotation"
    value: slerpQuat(root.upperRRest, root.upperRClosed, root.blinkProgress)
  }
  Binding {
    target: clippyModel.eyelidLowerR
    property: "rotation"
    value: slerpQuat(root.lowerRRest, root.lowerRClosed, root.blinkProgress)
  }

  // Qt.quaternion has no built-in slerp exposed to QML/JS; a plain
  // component-wise lerp-then-normalize is a fine stand-in over this small,
  // fast eyelid motion (the visible difference from true slerp only shows
  // up over large rotations or slow interpolation).
  function slerpQuat(a, b, t) {
    var x = a.x + (b.x - a.x) * t
    var y = a.y + (b.y - a.y) * t
    var z = a.z + (b.z - a.z) * t
    var w = a.scalar + (b.scalar - a.scalar) * t
    var len = Math.sqrt(x * x + y * y + z * z + w * w)
    if (len < 0.0001) return a
    return Qt.quaternion(w / len, x / len, y / len, z / len)
  }

  // Qt.quaternion has no fromAxisAndAngle/operator* exposed to QML/JS
  // either, so these three are the plain-math equivalents used by the eye
  // tracking above: small rotations around local Y (yaw) and local X
  // (pitch), applied on top of each eye's authored rest orientation via a
  // Hamilton product. Positive pitch looks down: rotating +Z (the direction
  // the eyes face, toward the camera) around +X tips it toward -Y.
  function quatFromYAxisAngle(degrees) {
    var half = (degrees * Math.PI / 180) / 2
    return Qt.quaternion(Math.cos(half), 0, Math.sin(half), 0)
  }
  function quatFromXAxisAngle(degrees) {
    var half = (degrees * Math.PI / 180) / 2
    return Qt.quaternion(Math.cos(half), Math.sin(half), 0, 0)
  }
  function quatMultiply(a, b) {
    return Qt.quaternion(
      a.scalar * b.scalar - a.x * b.x - a.y * b.y - a.z * b.z,
      a.scalar * b.x + a.x * b.scalar + a.y * b.z - a.z * b.y,
      a.scalar * b.y - a.x * b.z + a.y * b.scalar + a.z * b.x,
      a.scalar * b.z + a.x * b.y - a.y * b.x + a.z * b.scalar)
  }
}
