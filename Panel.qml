import QtQuick
import qs.Commons
import qs.Ui

// Safe Update details: the last post-update check, the snapshot Omarchy took
// before that update, and the per-plugin report. BarWidget.qml owns the data
// and the actions; this file only lays them out.
Panel {
  id: root
  moduleName: "nejcc.safe-update"
  ipcTarget: "nejcc.safe-update"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var report: hostWidget ? hostWidget.report : null
  readonly property var snapshot: report && report.snapshot ? report.snapshot : null
  readonly property int booted: hostWidget ? hostWidget.bootedSnapshot : -1
  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color bad: bar ? bar.urgent : Color.urgent

  function when(seconds) {
    return seconds ? Qt.formatDateTime(new Date(seconds * 1000), "d MMM yyyy, HH:mm") : "unknown"
  }

  function statusText() {
    if (!report) return "No check yet. It runs after the next omarchy update once the hooks are installed."
    var what = report.manual ? "Manual check " : "Checked after the update, "
    var head = what + when(report.checkedAt)
    if (report.versionBefore && report.versionBefore !== report.versionAfter)
      head += "\nOmarchy " + report.versionBefore + " → " + report.versionAfter
    if (report.status === "ok") return head + "\nShell and plugins are fine."
    var issues = []
    if (!report.shell.ok) issues.push("the shell does not answer")
    if (report.shell.restarts > 0) issues.push("the shell crashed " + report.shell.restarts + "x")
    if (report.broken > 0) issues.push(report.broken + (report.broken === 1 ? " plugin" : " plugins") + " broken")
    return head + "\nProblems: " + issues.join(", ") + "."
  }

  // Rollback is never automatic. Omarchy's own path is: boot the snapshot from
  // the Limine menu, then make it permanent with omarchy-snapshot restore.
  function rollbackText() {
    if (booted >= 0)
      return "You are booted into snapshot #" + booted + ". Restore makes it the live system; reboot without restoring to go back."
    if (!snapshot) return "No update recorded yet. Omarchy snapshots before every update when Snapper is set up."
    if (snapshot.state === "unavailable") return "Snapper is not installed, so updates are not snapshotted."
    if (snapshot.state === "failed") return "The last update ran without a snapshot. Omarchy printed why in the update log."
    var which = snapshot.number !== null && snapshot.number !== undefined
      ? "snapshot #" + snapshot.number + " (\"" + snapshot.label + "\")"
      : "the snapshot described \"" + snapshot.label + "\""
    var taken = snapshot.state === "taken" ? "Omarchy took " : "Look for "
    return taken + which + " right before the update of " + when(report.since) + ".\n"
      + "To roll back: reboot, open Snapshots in the Limine boot menu, pick that entry, "
      + "then open this panel and choose Restore (or run omarchy-snapshot restore)."
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if ((t === "c" || t === "C") && root.hostWidget) root.hostWidget.checkNow()
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroll.width
          spacing: Style.spacing.lg

          Text {
            text: "Safe Update"
            color: root.report && root.report.status === "broken" ? root.bad : root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            width: parent.width
            text: root.statusText()
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          PanelSeparator { width: parent.width; foreground: root.fg }
          PanelSectionHeader { text: "ROLLBACK"; foreground: root.fg }

          Text {
            width: parent.width
            text: root.rollbackText()
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Row {
            spacing: Style.spacing.controlGap

            Button {
              visible: root.booted >= 0
              text: "Restore snapshot #" + root.booted
              bordered: true
              foreground: root.fg
              tooltipText: "Opens a terminal running omarchy-snapshot restore"
              onClicked: root.hostWidget.runInTerminal("omarchy-snapshot restore")
            }

            Button {
              visible: root.booted < 0
              text: "List snapshots"
              bordered: true
              foreground: root.fg
              tooltipText: "Opens a terminal running sudo snapper -c root list"
              onClicked: root.hostWidget.runInTerminal("sudo snapper -c root list")
            }
          }

          PanelSeparator { width: parent.width; foreground: root.fg; visible: plugins.count > 0 }
          PanelSectionHeader { text: "PLUGINS"; foreground: root.fg; visible: plugins.count > 0 }

          Repeater {
            id: plugins
            model: root.report ? root.report.plugins : []

            Column {
              required property var modelData
              width: content.width
              spacing: Style.spacing.xxs

              Row {
                spacing: Style.spacing.md

                Text {
                  text: modelData.ok ? "" : ""
                  color: modelData.ok ? root.dim : root.bad
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                Text {
                  text: modelData.name + (modelData.enabled === false ? "  (disabled)" : "")
                  textFormat: Text.PlainText
                  color: modelData.ok ? root.fg : root.bad
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }

              Repeater {
                model: modelData.ok ? [] : (modelData.valid ? [] : [modelData.validateError]).concat(modelData.errors)

                Text {
                  required property string modelData
                  width: content.width
                  leftPadding: Style.space(18)
                  text: modelData
                  textFormat: Text.PlainText
                  wrapMode: Text.WrapAnywhere
                  maximumLineCount: 3
                  elide: Text.ElideRight
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.fg }

          Row {
            spacing: Style.spacing.controlGap

            Button {
              text: root.hostWidget && root.hostWidget.busy ? "Checking…" : "Check now"
              enabled: !(root.hostWidget && root.hostWidget.busy)
              bordered: true
              foreground: root.fg
              tooltipText: "Validate plugins, ping the shell and scan its log since boot (c)"
              onClicked: root.hostWidget.checkNow()
            }

            Button {
              readonly property bool installed: root.hostWidget ? root.hostWidget.hooksInstalled : false
              text: installed ? "Remove hooks" : "Install hooks"
              bordered: true
              foreground: root.fg
              tooltipText: installed
                ? "Remove the post-update and post-boot hooks from ~/.config/omarchy/hooks"
                : "Copy the post-update and post-boot hooks into ~/.config/omarchy/hooks"
              onClicked: root.hostWidget.setHooks(!installed)
            }
          }
        }
      }
    }
  }
}
