import QtQuick
import qs.Commons
import qs.Ui

// Bar icon that toggles the Clippy popup, mirroring
// nosignal.quattrolitaire/BarWidget.qml's IPC-toggle pattern exactly.
BarWidget {
  id: root
  moduleName: "dev.ebbo.omaclippy"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "" // nf-fa-paperclip -- vertical by design, and (unlike the 📎 emoji) a font glyph, so it inherits `foreground` for proper monochrome bar theming
    tooltipText: "Clippy"
    foreground: Color.accent
    fixedWidth: root.bar && root.bar.vertical ? -1 : Style.space(27)
    fixedHeight: root.bar && root.bar.vertical ? Style.space(26) : -1
    onPressed: function(b) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle dev.ebbo.omaclippy")
    }
  }
}
