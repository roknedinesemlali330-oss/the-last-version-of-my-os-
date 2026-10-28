// MyOS Settings (own Quickshell instance: a bug here cannot break the desktop shell).
// Saves everything to ~/.config/myos/settings.json; the main shell applies it live.

import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: app

    // ===== state =====
    property int page: 0
    property var conf: ({})
    property var networks: []
    property string selectedSsid: ""
    property string wifiStatus: ""
    property var btDevices: []
    property string btMode: ""
    property string btStatus: ""
    property var monitors: []
    property string aboutText: "Loading..."
    property real vol: 0.5
    property real bri: 0.7

    readonly property var pages: ["Wi-Fi", "Bluetooth", "Sound & Display", "Appearance", "Shelf",
                                  "Windows", "Screen", "Keyboard", "Wallpaper", "System", "About"]
    readonly property var wallpapers: ["wallpaper.png", "wallpaper-2.png", "wallpaper-3.png", "wallpaper-4.png"]
    readonly property var accents: ["#4C7BDE", "#8A6AD8", "#3FA77A", "#E8714F", "#D4537E", "#E0A53A"]
    readonly property bool isHypr: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ? true : false
    readonly property var defaultPinned: [
        { n: "Terminal",    id: "foot",       icons: ["utilities-terminal", "terminal"],        cmd: ["foot"] },
        { n: "Files",       id: "thunar",     icons: ["system-file-manager", "thunar"],         cmd: ["thunar"] },
        { n: "Browser",     id: "firefox",    icons: ["firefox-esr", "firefox", "web-browser"], cmd: ["firefox-esr"] },
        { n: "Text Editor", id: "mousepad",   icons: ["accessories-text-editor", "mousepad"],   cmd: ["mousepad"] },
        { n: "Settings",    id: "quickshell", icons: ["preferences-system"],                    cmd: ["qs", "-p", "/etc/myos/settings"] }
    ]

    // ===== colors (follow the dark mode setting) =====
    readonly property bool dark: get("dark", false)
    readonly property color cAccent: get("accent", "#4C7BDE")
    readonly property color cBg: dark ? "#232837" : "#F7F8FC"
    readonly property color cSide: dark ? "#2A2F40" : "#EEF1F8"
    readonly property color cCard: dark ? "#2F3548" : "#FFFFFF"
    readonly property color cText: dark ? "#EEF0F6" : "#1F2433"
    readonly property color cMuted: dark ? "#A6ADC2" : "#666677"
    readonly property color cChip: dark ? "#41485F" : "#E3E9F6"
    readonly property color cSel: dark ? "#3A4468" : "#D6E3FB"

    // ===== settings store =====
    function get(key, def) { return conf[key] !== undefined ? conf[key] : def }
    function load() {
        try { conf = JSON.parse(cfg.text()) } catch (e) { conf = {} }
    }
    function save(key, value) {
        var o = JSON.parse(JSON.stringify(conf))
        o[key] = value
        conf = o
        cfg.setText(JSON.stringify(o, null, 2))
    }
    FileView {
        id: cfg
        path: Quickshell.env("HOME") + "/.config/myos/settings.json"
        onLoaded: app.load()
    }
    // make sure the folder and file exist, then load
    Process {
        id: init
        command: ["sh", "-c", "mkdir -p \"$HOME/.config/myos\"; [ -f \"$HOME/.config/myos/settings.json\" ] || echo '{}' > \"$HOME/.config/myos/settings.json\"; echo ok"]
        running: true
        stdout: StdioCollector { onStreamFinished: cfg.reload() }
    }

    function launch(cmd) {
        var a = []
        for (var i = 0; i < cmd.length; i++) a.push(cmd[i])
        if (isHypr) Quickshell.execDetached(["hyprctl", "dispatch", "exec", a.join(" ")])
        else Quickshell.execDetached(a)
    }

    // ===== Wi-Fi =====
    function parseWifi(text) {
        var lines = text.split("\n")
        var seen = {}
        var out = []
        for (var i = 0; i < lines.length; i++) {
            var p = lines[i].split(":")
            if (p.length < 3) continue
            var sec = p[p.length - 1]
            var sig = parseInt(p[p.length - 2])
            var ssid = p.slice(0, p.length - 2).join(":").replace(/\\:/g, ":")
            if (ssid === "" || seen[ssid]) continue
            seen[ssid] = true
            out.push({ ssid: ssid, signal: sig, secure: sec !== "" && sec !== "--" })
        }
        out.sort(function (a, b) { return b.signal - a.signal })
        networks = out
    }
    function scanWifi() { scan.running = false; scan.running = true }
    function connectWifi(ssid, pw) {
        var cmd = ["nmcli", "dev", "wifi", "connect", ssid]
        if (pw.length > 0) cmd = cmd.concat(["password", pw])
        connect.command = cmd
        wifiStatus = "Connecting to " + ssid + "..."
        connect.running = false
        connect.running = true
    }
    Process {
        id: scan
        command: ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: StdioCollector { onStreamFinished: app.parseWifi(text) }
    }
    Process {
        id: connect
        stdout: StdioCollector { onStreamFinished: { if (text.trim().length) app.wifiStatus = text.trim() } }
        stderr: StdioCollector { onStreamFinished: { if (text.trim().length) app.wifiStatus = text.trim() } }
    }

    // ===== Bluetooth =====
    function runBt(mode, shellCmd) {
        btMode = mode
        btStatus = (mode === "scan") ? "Scanning for 8 seconds..." : "Working..."
        btProc.command = ["sh", "-c", shellCmd]
        btProc.running = false
        btProc.running = true
    }
    function scanBt() { runBt("scan", "rfkill unblock bluetooth; bluetoothctl power on; bluetoothctl --timeout 8 scan on >/dev/null 2>&1; bluetoothctl devices") }
    function connectBt(mac) {
        runBt("connect", "bluetoothctl pair " + mac + "; bluetoothctl trust " + mac + "; bluetoothctl connect " + mac + " 2>&1 | tail -2")
    }
    function handleBt(text) {
        if (btMode === "scan") {
            var out = []
            var lines = text.split("\n")
            for (var i = 0; i < lines.length; i++) {
                var m = lines[i].match(/^Device ([0-9A-Fa-f:]{17}) (.*)$/)
                if (m) out.push({ mac: m[1], name: m[2] })
            }
            btDevices = out
            btStatus = out.length > 0 ? "Found " + out.length + " device(s). Click one to connect." : "No devices found. Is Bluetooth available on this computer?"
        } else {
            btStatus = text.trim().length ? text.trim() : "Done."
        }
    }
    Process {
        id: btProc
        stdout: StdioCollector { onStreamFinished: app.handleBt(text) }
        stderr: StdioCollector { onStreamFinished: { if (text.trim().length) app.btStatus = text.trim() } }
    }

    // ===== Screen =====
    function applyMonitor(name, mode, scale) {
        if (!isHypr) return
        Quickshell.execDetached(["hyprctl", "keyword", "monitor", name + "," + mode + ",auto," + scale])
        save("monitor", { name: name, mode: mode, scale: scale })
        Qt.callLater(function () { monProc.running = false; monProc.running = true })
    }
    Process {
        id: monProc
        command: ["hyprctl", "monitors", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var m = JSON.parse(text)
                    var out = []
                    for (var i = 0; i < m.length; i++) {
                        var seen = {}
                        var modes = []
                        var am = m[i].availableModes || []
                        for (var j = 0; j < am.length; j++) {
                            var mm = am[j].replace("Hz", "")
                            if (!seen[mm]) { seen[mm] = true; modes.push(mm) }
                        }
                        out.push({
                            name: m[i].name,
                            current: m[i].width + "x" + m[i].height + "@" + m[i].refreshRate.toFixed(2),
                            scale: m[i].scale,
                            modes: modes.slice(0, 14)
                        })
                    }
                    app.monitors = out
                } catch (e) { }
            }
        }
    }

    // ===== apps / pins =====
    function pinsList() { return get("pinned", defaultPinned) }
    function cmdKey(cmd) {
        var a = []
        for (var i = 0; i < cmd.length; i++) a.push(cmd[i])
        return a.join(" ")
    }
    function isPinned(e) {
        var p = pinsList()
        var k = cmdKey(e.command)
        for (var i = 0; i < p.length; i++) { if (cmdKey(p[i].cmd) === k) return true }
        return false
    }
    function togglePin(e) {
        var p = JSON.parse(JSON.stringify(pinsList()))
        var k = cmdKey(e.command)
        var found = -1
        for (var i = 0; i < p.length; i++) { if (cmdKey(p[i].cmd) === k) found = i }
        if (found >= 0) {
            p.splice(found, 1)
        } else {
            var c = []
            for (var j = 0; j < e.command.length; j++) c.push(e.command[j])
            p.push({ n: e.name, id: String(e.id).toLowerCase(), icons: [e.icon, "application-x-executable"], cmd: c })
        }
        save("pinned", p)
    }
    ScriptModel {
        id: allApps
        values: DesktopEntries.applications.values
            .filter(function (e) { return !e.noDisplay })
            .sort(function (a, b) { return a.name.localeCompare(b.name) })
    }

    // ===== initial values =====
    Process {
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var m = text.match(/([0-9.]+)/)
                if (m) app.vol = Math.min(1, parseFloat(m[1]))
            }
        }
    }
    Process {
        command: ["brightnessctl", "-m"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim().split(",")
                if (p.length >= 4) app.bri = Math.max(0, Math.min(1, parseInt(p[3]) / 100))
            }
        }
    }
    Process {
        command: ["sh", "-c", "uname -r; hostname; awk '/MemTotal/ {printf \"%.1f GB\\n\", $2/1048576}' /proc/meminfo"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.trim().split("\n")
                app.aboutText = "System:  MyOS 0.2 (Debian 13 base)\nKernel:  " + l[0] + "\nHostname:  " + l[1] + "\nMemory:  " + l[2]
            }
        }
    }
    function setWallpaper(name) {
        var path = "/usr/share/backgrounds/myos/" + name
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.config/myos\"; echo '" + path + "' > \"$HOME/.config/myos/wallpaper\"; pkill swaybg; swaybg -i '" + path + "' -m fill"])
    }
    Component.onCompleted: scanWifi()

    // ===== reusable pieces =====
    component QSlider: Item {
        id: sl
        property real value: 0.5
        property color accent: "#4C7BDE"
        property color track: "#DCE3F2"
        signal moved(real v)
        height: 28
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6; radius: 3
            color: sl.track
            Rectangle { width: parent.width * sl.value; height: parent.height; radius: 3; color: sl.accent }
        }
        Rectangle {
            x: (sl.width - width) * sl.value
            anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20; radius: 10
            color: sl.accent
        }
        MouseArea {
            anchors.fill: parent
            function setFrom(mx) { sl.value = Math.max(0, Math.min(1, mx / sl.width)) }
            onPressed: (m) => setFrom(m.x)
            onPositionChanged: (m) => { if (pressed) setFrom(m.x) }
            onReleased: sl.moved(sl.value)
        }
    }
    component PBtn: Rectangle {
        id: pb
        property string label
        property color tint: "#4C7BDE"
        property color fg: "#FFFFFF"
        signal clicked()
        width: lbl.width + 36; height: 38; radius: 19
        color: pm.containsMouse ? Qt.darker(tint, 1.08) : tint
        Text { id: lbl; anchors.centerIn: parent; text: pb.label; color: pb.fg; font.pixelSize: 13 }
        MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; onClicked: pb.clicked() }
    }

    // ===================== WINDOW =====================
    FloatingWindow {
        id: win
        title: "Settings"
        implicitWidth: 900
        implicitHeight: 620
        color: app.cBg
        onVisibleChanged: if (!visible) Qt.quit()

        // ----- sidebar -----
        Rectangle {
            id: side
            width: 200
            height: parent.height
            color: app.cSide
            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 3
                Text { text: "Settings"; font.pixelSize: 20; font.bold: true; color: app.cText; bottomPadding: 8 }
                Repeater {
                    model: app.pages
                    delegate: Rectangle {
                        id: item
                        required property string modelData
                        required property int index
                        width: parent.width; height: 38; radius: 19
                        color: app.page === index ? app.cSel : (im.containsMouse ? app.cChip : "transparent")
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            text: item.modelData
                            font.pixelSize: 14
                            color: app.cText
                        }
                        MouseArea {
                            id: im
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                app.page = item.index
                                if (item.index === 6) { monProc.running = false; monProc.running = true }
                            }
                        }
                    }
                }
            }
        }

        // ----- content -----
        Item {
            x: side.width
            width: parent.width - side.width
            height: parent.height

            // 0: Wi-Fi
            Item {
                anchors.fill: parent; anchors.margins: 24
                visible: app.page === 0
                Column {
                    anchors.fill: parent; spacing: 12
                    Row {
                        spacing: 16
                        Text { text: "Wi-Fi"; font.pixelSize: 22; font.bold: true; color: app.cText; anchors.verticalCenter: parent.verticalCenter }
                        PBtn { label: "Rescan"; tint: app.cChip; fg: app.cText; onClicked: app.scanWifi() }
                    }
                    Rectangle {
                        width: parent.width; height: 270; radius: 16; color: app.cCard
                        ListView {
                            anchors.fill: parent; anchors.margins: 6; clip: true
                            model: app.networks
                            delegate: Rectangle {
                                id: nrow
                                required property var modelData
                                width: ListView.view.width; height: 40; radius: 12
                                color: app.selectedSsid === modelData.ssid ? app.cSel : (nm.containsMouse ? app.cChip : "transparent")
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left; anchors.leftMargin: 14
                                    text: nrow.modelData.ssid; font.pixelSize: 14; color: app.cText
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right; anchors.rightMargin: 14
                                    text: (nrow.modelData.secure ? "locked   " : "open   ") + nrow.modelData.signal + "%"
                                    font.pixelSize: 12; color: app.cMuted
                                }
                                MouseArea { id: nm; anchors.fill: parent; hoverEnabled: true; onClicked: app.selectedSsid = nrow.modelData.ssid }
                            }
                        }
                    }
                    Row {
                        spacing: 10
                        Rectangle {
                            width: 300; height: 38; radius: 19; color: app.cCard
                            TextInput {
                                id: pw
                                anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                font.pixelSize: 14; color: app.cText; clip: true
                                Text {
                                    visible: pw.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Password (empty if saved or open)"
                                    font.pixelSize: 12; color: app.cMuted
                                }
                            }
                        }
                        PBtn {
                            label: "Connect"; tint: app.cAccent
                            onClicked: { if (app.selectedSsid !== "") app.connectWifi(app.selectedSsid, pw.text) }
                        }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 13; color: app.cMuted
                        text: app.selectedSsid === "" ? "Select a network from the list." : ("Selected: " + app.selectedSsid)
                    }
                    Text { width: parent.width; wrapMode: Text.WordWrap; text: app.wifiStatus; font.pixelSize: 13; color: app.cText }
                }
            }

            // 1: Bluetooth
            Item {
                anchors.fill: parent; anchors.margins: 24
                visible: app.page === 1
                Column {
                    anchors.fill: parent; spacing: 12
                    Text { text: "Bluetooth"; font.pixelSize: 22; font.bold: true; color: app.cText }
                    Row {
                        spacing: 10
                        PBtn { label: "Turn on"; tint: app.cAccent; onClicked: app.runBt("power", "rfkill unblock bluetooth; bluetoothctl power on 2>&1 | tail -1") }
                        PBtn { label: "Turn off"; tint: app.cChip; fg: app.cText; onClicked: app.runBt("power", "bluetoothctl power off 2>&1 | tail -1") }
                        PBtn { label: "Scan for devices"; tint: app.cChip; fg: app.cText; onClicked: app.scanBt() }
                    }
                    Rectangle {
                        width: parent.width; height: 270; radius: 16; color: app.cCard
                        ListView {
                            anchors.fill: parent; anchors.margins: 6; clip: true
                            model: app.btDevices
                            delegate: Rectangle {
                                id: brow
                                required property var modelData
                                width: ListView.view.width; height: 40; radius: 12
                                color: bm.containsMouse ? app.cChip : "transparent"
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left; anchors.leftMargin: 14
                                    text: brow.modelData.name; font.pixelSize: 14; color: app.cText
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right; anchors.rightMargin: 14
                                    text: brow.modelData.mac; font.pixelSize: 11; color: app.cMuted
                                }
                                MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; onClicked: app.connectBt(brow.modelData.mac) }
                            }
                        }
                    }
                    Text { width: parent.width; wrapMode: Text.WordWrap; text: app.btStatus; font.pixelSize: 13; color: app.cText }
                }
            }

            // 2: Sound and display
            Item {
                anchors.fill: parent; anchors.margins: 24
                visible: app.page === 2
                Column {
                    anchors.fill: parent; spacing: 14
                    Text { text: "Sound & Display"; font.pixelSize: 22; font.bold: true; color: app.cText }
                    Text { text: "Volume"; font.pixelSize: 14; color: app.cMuted }
                    QSlider {
                        width: parent.width; value: app.vol; accent: app.cAccent; track: app.cChip
                        onMoved: (v) => Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v.toFixed(2)])
                    }
                    PBtn {
                        label: "Mute / unmute"; tint: app.cChip; fg: app.cText
                        onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
                    }
                    Text { text: "Brightness (laptops)"; font.pixelSize: 14; color: app.cMuted; topPadding: 12 }
                    QSlider {
                        width: parent.width; value: app.bri; accent: app.cAccent; track: app.cChip
                        onMoved: (v) => Quickshell.execDetached(["brightnessctl", "set", Math.max(5, Math.round(v * 100)) + "%"])
                    }
                }
            }

            // 3: Appearance
            Item {
                anchors.fill: parent; anchors.margins: 24
                visible: app.page === 3
                Column {
                    anchors.fill: parent; spacing: 14
                    Text { text: "Appearance"; font.pixelSize: 22; font.bold: true; color: app.cText }
                    Text { text: "Theme"; font.pixelSize: 14; color: app.cMuted }
                    Row {
                        spacing: 10
                        PBtn { label: "Light"; tint: app.dark ? app.cChip : app.cAccent; fg: app.dark ? app.cText : "#FFFFFF"; onClicked: app.save("dark", false) }
                        PBtn { label: "Dark"; tint: app.dark ? app.cAccent : app.cChip; fg: app.dark ? "#FFFFFF" : app.cText; onClicked: app.save("dark", true) }
                    }
                    Text { text: "Accent color"; font.pixelSize: 14; color: app.cMuted; topPadding: 10 }
                    Row {
                        spacing: 12
                        Repeater {
                            model: app.accents
                            delegate: Rectangle {
                                id: ac
                                required property string modelData
                                width: 40; height: 40; radius: 20
                                color: modelData
                                border.width: app.cAccent == modelData ? 4 : 0
                                border.color: app.cText
                                MouseArea { anchors.fill: parent; onClicked: app.save("accent", ac.modelData) }
                            }
                        }
                    }
                }
            }

            // 4: Shelf
            Item {
                anchors.fill: parent; anchors.margins: 24
                visible: app.page === 4
                Column {
                    anchors.fill: parent; spacing: 12
                    Text { text: "Shelf"; font.pixelSize: 22; font.bold: true; color: app.cText }
                    Row {
                        spacing: 10
                        PBtn { label: "Bottom"; tint: app.get("shelfPos", "bottom") === "top" ? app.cChip : app.cAccent; fg: app.get("shelfPos", "bottom") === "top" ? app.cText : "#FFFFFF"; onClicked: app.save("shelfPos", "bottom") }
                        PBtn { label: "Top"; tint: app.get("shelfPos", "bottom") === "top" ? app.cAccent : app.cChip; fg: app.get("shelfPos", "bottom") === "top" ? "#FFFFFF" : app.cText; onClicked: app.save("shelfPos", "top") }
                        PBtn { label: "Reset pinned apps"; tint: app.cChip; fg: app.cText; onClicked: app.save("pinned", app.defaultPinned) }
                    }
                    Text { text: "Icon size"; font.pixelSize: 13; color: app.cMuted }
                    QSlider {
                        width: 320; accent: app.cAccent; track: app.cChip
                        value: (app.get("iconSize", 30) - 24) / 20
                        onMoved: (v) => app.save("iconSize", Math.round(24 + v * 20))
                    }
                    Text { text: "Transparency"; font.pixelSize: 13; color: app.cMuted }
                    QSlider {
                        width: 320; accent: app.cAccent; track: app.cChip
                        value: (app.get("shelfOpacity", 1.0) - 0.4) / 0.6
                        onMoved: (v) => app.save("shelfOpacity", Math.round((0.4 + v * 0.6) * 100) / 100)
                    }
                    Text { text: "Pinned apps (click to pin or unpin)"; font.pixelSize: 13; color: app.cMuted }
                    Rectangle {
                        width: parent.width; height: 200; radius: 16; color: app.cCard
                        ListView {
                            anchors.fill: parent; anchors.margins: 6; clip: true
                            model: allApps
                            delegate: Rectangle {
                                id: arow
                                required property var modelData
                                width: ListView.view.width; height: 36; radius: 10
                                color: am.containsMouse ? app.cChip : "transparent"
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left; anchors.leftMargin: 14
                                    text: arow.modelData.name; font.pixelSize: 13; color: app.cText
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right; anchors.rightMargin: 14
                                    text: app.isPinned(arow.modelData) ? "Pinned" : "Pin"
                                    font.pixelSize: 12
                                    color: app.isPinned(arow.modelData) ? app.cAccent : app.cMuted
                                }
                                MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; onClicked: app.togglePin(arow.modelData) }
                            }
                        }
                    }
                }
            }

            // 5: Windows
            Item {
                anchors.fill: parent; anchors.margins: 24
                visible: app.page === 5
                Column {
                    anchors.fill: parent; spacing: 14
                    Text { text: "Windows"; font.pixelSize: 22; font.bold: true; color: app.cText }
                    Text { text: "Corner roundness"; font.pixelSize: 14; color: app.cMuted }
                    QSlider {
                        width: 360; accent: app.cAccent; track: app.cChip
                        value: app.get("rounding", 14) / 24
                        onMoved: (v) => app.save("rounding", Math.round(v * 24))
                    }
                    Text { text: "Gap between windows"; font.pixelSize: 14; color: app.cMuted }
                    QSlider {
                        width: 360; accent: app.cAccent; track: app.cChip
                        value: app.get("gaps", 10) / 24
                        onMoved: (v) => app.save("gaps", Math.round(v * 24))
                    }
                    Row {
                        spacing: 10
                        PBtn { label: "Shadows: " + (app.get("shadows", true) ? "On" : "Off"); tint: app.cChip; fg: app.cText; onClicked: app.save("shadows", !app.get("shadows", true)) }
                        PBtn { label: "Animations: " + (app.get("animations", true) ? "On" : "Off"); tint: app.cChip; fg: app.cText; onClicked: app.save("animations", !app.get("animations", true)) }
                        PBtn { label: "Blur: " + (app.get("blur", false) ? "On" : "Off"); tint: app.cChip; fg: app.cText; onClicked: app.save("blur", !app.get("blur", false)) }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 12; color: app.cMuted
                        text: "Blur and shadows use more graphics power. On a weak computer or a virtual machine, keep them off."
                    }
                }
            }

            // 6: Screen
            Item {
                anchors.fill: parent; anchors.margins: 24
                visible: app.page === 6
                Column {
                    anchors.fill: parent; spacing: 12
                    Text { text: "Screen"; font.pixelSize: 22; font.bold: true; color: app.cText }
                    Repeater {
                        model: app.monitors
                        delegate: Column {
                            id: mon
                            required property var modelData
                            width: parent.width; spacing: 10
                            Text { text: mon.modelData.name + "   (now " + mon.modelData.current + ", scale " + mon.modelData.scale + ")"; font.pixelSize: 14; color: app.cText }
                            Text { text: "Resolution and refresh rate"; font.pixelSize: 13; color: app.cMuted }
                            Flow {
                                width: parent.width; spacing: 8
                                Repeater {
                                    model: mon.modelData.modes
                                    delegate: PBtn {
                                        required property string modelData
                                        label: modelData
                                        tint: modelData === mon.modelData.current ? app.cAccent : app.cChip
                                        fg: modelData === mon.modelData.current ? "#FFFFFF" : app.cText
                                        onClicked: app.applyMonitor(mon.modelData.name, modelData, mon.modelData.scale)
                                    }
                                }
                            }
                            Text { text: "Scale"; font.pixelSize: 13; color: app.cMuted }
                            Row {
                                spacing: 8
                                Repeater {
                                    model: [1, 1.25, 1.5, 2]
                                    delegate: PBtn {
                                        required property var modelData
                                        label: String(modelData)
                                        tint: Number(mon.modelData.scale) === Number(modelData) ? app.cAccent : app.cChip
                                        fg: Number(mon.modelData.scale) === Number(modelData) ? "#FFFFFF" : app.cText
                                        onClicked: app.applyMonitor(mon.modelData.name, mon.modelData.current, modelData)
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        visible: app.monitors.length === 0
                        text: "No screen information (this page works on Hyprland only)."
                        font.pixelSize: 13; color: app.cMuted
                    }
                }
            }

            // 7: Keyboard
            Item {
                anchors.fill: parent; anchors.margins: 24
                visible: app.page === 7
                Column {
                    anchors.fill: parent; spacing: 14
                    Text { text: "Keyboard"; font.pixelSize: 22; font.bold: true; color: app.cText }
                    Text { text: "Layouts: English (US) and Arabic"; font.pixelSize: 14; color: app.cText }
                    Text { text: "Shortcut to switch: Alt + Shift"; font.pixelSize: 14; color: app.cMuted }
                    PBtn {
                        label: "Switch layout now"; tint: app.cAccent
                        onClicked: Quickshell.execDetached(app.isHypr
                            ? ["hyprctl", "switchxkblayout", "all", "next"]
                            : ["swaymsg", "input", "type:keyboard", "xkb_switch_layout", "next"])
                    }
                }
            }

            // 8: Wallpaper
            Item {
                anchors.fill: parent; anchors.margins: 24
                visible: app.page === 8
                Column {
                    anchors.fill: parent; spacing: 14
                    Text { text: "Wallpaper"; font.pixelSize: 22; font.bold: true; color: app.cText }
                    Flow {
                        width: parent.width; spacing: 14
                        Repeater {
                            model: app.wallpapers
                            delegate: Rectangle {
                                id: wp
                                required property string modelData
                                width: 190; height: 110; radius: 12
                                color: app.cChip; clip: true
                                Image {
                                    anchors.fill: parent
                                    source: "file:///usr/share/backgrounds/myos/" + wp.modelData
                                    sourceSize: Qt.size(380, 220)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                MouseArea { anchors.fill: parent; onClicked: app.setWallpaper(wp.modelData) }
                            }
                        }
                    }
                }
            }

            // 9: System
            Item {
                anchors.fill: parent; anchors.margins: 24
                visible: app.page === 9
                Column {
                    anchors.fill: parent; spacing: 14
                    Text { text: "System"; font.pixelSize: 22; font.bold: true; color: app.cText }
                    Row {
                        spacing: 10
                        PBtn { label: "Software store"; tint: app.cChip; fg: app.cText; onClicked: app.launch(["gnome-software"]) }
                        PBtn { label: "Printers"; tint: app.cChip; fg: app.cText; onClicked: app.launch(["system-config-printer"]) }
                        PBtn { label: "Task manager"; tint: app.cChip; fg: app.cText; onClicked: app.launch(["lxtask"]) }
                    }
                    Text { text: "Install MyOS to a disk"; font.pixelSize: 15; font.bold: true; color: app.cText; topPadding: 14 }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 13; color: app.cMuted
                        text: "The installer is experimental. Test it inside a virtual machine first. Never run it on a computer with data you care about before you have tested it there."
                    }
                    PBtn { label: "Start installer"; tint: "#E8714F"; onClicked: app.launch(["sh", "/etc/myos/install.sh"]) }
                }
            }

            // 10: About
            Item {
                anchors.fill: parent; anchors.margins: 24
                visible: app.page === 10
                Column {
                    anchors.fill: parent; spacing: 14
                    Text { text: "About"; font.pixelSize: 22; font.bold: true; color: app.cText }
                    Text { text: app.aboutText; font.pixelSize: 14; color: app.cText; lineHeight: 1.5 }
                }
            }
        }
    }
}
