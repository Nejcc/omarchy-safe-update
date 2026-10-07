import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon for Safe Update. Reads the last post-update check from
// $XDG_STATE_HOME/omarchy-safe-update/last.json (written by bin/safe-update)
// through a file watcher, so it costs nothing between updates. Turns urgent
// when that check found something broken. Click opens the panel.
BarWidget {
  id: root
  moduleName: "nejcc.safe-update"

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy-safe-update"
  readonly property string hookFile: home + "/.config/omarchy/hooks/post-update.d/nejcc-safe-update"
  readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("bin/safe-update")).replace(/^file:\/\//, ""))

  property var report: null
  property bool hooksInstalled: false
  property bool busy: false
  // Snapper number of the snapshot this boot runs from, or -1 on the live
  // system. Matches limine-snapper-restore's own check of /proc/cmdline.
  property int bootedSnapshot: -1

  readonly property bool broken: report !== null && report.status === "broken"

  function parseReport(text) {
    try {
      var r = JSON.parse(text)
      report = r && r.version === 1 ? r : null
    } catch (e) {
      report = null
    }
  }

  function runScript(args) {
    if (actionProc.running) return
    busy = true
    actionProc.command = [root.script].concat(args)
    actionProc.running = true
  }

  function checkNow() { runScript(["check", "--no-notify"]) }
  function setHooks(install) { runScript(["hooks", install ? "install" : "remove"]) }

  // Privileged steps only ever run in a visible terminal the user opened.
  function runInTerminal(command) {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", command])
    close()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  FileView {
    id: lastFile
    path: root.stateDir + "/last.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.parseReport(text())
    onLoadFailed: root.report = null
    onFileChanged: reload()
  }

  // Installed or not is whether the hook file exists, watched the same way.
  FileView {
    id: hookView
    path: root.hookFile
    watchChanges: true
    printErrors: false
    onLoaded: root.hooksInstalled = true
    onLoadFailed: root.hooksInstalled = false
    onFileChanged: reload()
  }

  Process {
    id: actionProc
    // The watchers catch these writes too; reloading covers a file that did
    // not exist yet when its watcher started.
    onExited: function(exitCode) {
      root.busy = false
      lastFile.reload()
      hookView.reload()
    }
  }

  Process {
    running: true
    command: ["cat", "/proc/cmdline"]
    stdout: StdioCollector {
      onStreamFinished: {
        var m = String(text).match(/rootflags\S*subvol=\S*?\/(\d+)\/snapshot/)
        root.bootedSnapshot = m ? Number(m[1]) : -1
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "nejcc.safe-update"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function check(): void { root.checkNow() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Shield when fine or never checked, warning when the last check failed.
    text: root.broken ? "" : ""
    active: root.broken
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.broken ? "Safe Update: the last update broke something" : "Safe Update"
    onPressed: root.togglePanel()
  }
}
