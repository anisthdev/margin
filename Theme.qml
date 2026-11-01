pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Copied from Seedling (itself from quickbar 9e7052b), so margin looks like
// the shell's menus.
// Colours come from colors.css in the app's own config folder, which
// matugen writes from the wallpaper (any `@define-color NAME rgba(…)` file
// will do). The file is watched, so a wallpaper change recolours it live.
Singleton {
    id: root

    // Google Sans Flex, Android 16's own; variable, so weights between the
    // named ones work (bodyWeight)
    readonly property string fontFamily: "Google Sans Flex"
    // What a Label's default Medium renders at: a little under 500, as
    // end-4's shell sets its body text
    readonly property int bodyWeight: 450
    // The full-screen menus' titles (Entertainment, Search movies): a
    // little under Bold
    readonly property int titleWeight: 620
    // How round titles' letters are (the font's ROND axis, 0-100)
    readonly property real titleRoundness: 100
    // Same as the terminal; for figures that shouldn't shift as they change
    readonly property string monoFamily: "SF Mono"
    readonly property int fontSize: 14
    readonly property int barHeight: 38
    readonly property int radius: 10
    // Menus and cards; what sits inside them uses radius
    readonly property int cardRadius: 16
    readonly property int gap: 10

    // Opacity for every matugen colour, replacing the 0.8 in colors.css.
    // Opaque, unlike the shell's see-through menus: margin is an ordinary
    // window, which Hyprland already shows at 0.9.
    readonly property real alpha: 1

    readonly property int animFast: 150
    readonly property int animNormal: 280

    // Material 3 easing curves, as easing.bezierCurve values
    readonly property var emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]

    property color background: Qt.rgba(16 / 255, 21 / 255, 13 / 255, 0.8)
    property color on_background: Qt.rgba(223 / 255, 228 / 255, 215 / 255, 0.8)
    property color on_surface: Qt.rgba(223 / 255, 228 / 255, 215 / 255, 0.8)
    property color inverse_surface: Qt.rgba(223 / 255, 228 / 255, 215 / 255, 0.8)
    property color inverse_primary: Qt.rgba(146 / 255, 71 / 255, 89 / 255, 0.8)
    property color on_surface_variant: Qt.rgba(191 / 255, 202 / 255, 182 / 255, 0.8)
    property color surface_container: Qt.rgba(28 / 255, 33 / 255, 25 / 255, 0.8)
    property color surface_container_high: Qt.rgba(38 / 255, 44 / 255, 35 / 255, 0.8)
    property color surface_container_low: Qt.rgba(24 / 255, 29 / 255, 21 / 255, 0.8)
    property color surface_container_lowest: Qt.rgba(10 / 255, 16 / 255, 8 / 255, 0.8)
    property color surface_container_highest: Qt.rgba(49 / 255, 54 / 255, 45 / 255, 0.8)
    property color outline: Qt.rgba(138 / 255, 148 / 255, 130 / 255, 0.8)
    property color error: Qt.rgba(255 / 255, 180 / 255, 171 / 255, 0.8)
    property color on_error: Qt.rgba(105 / 255, 0, 5 / 255, 0.8)
    property color primary: Qt.rgba(255 / 255, 177 / 255, 193 / 255, 0.8)
    property color on_primary: Qt.rgba(89 / 255, 25 / 255, 44 / 255, 0.8)
    property color primary_container: Qt.rgba(117 / 255, 48 / 255, 66 / 255, 0.8)
    property color on_primary_container: Qt.rgba(255 / 255, 217 / 255, 223 / 255, 0.8)
    property color secondary: Qt.rgba(176 / 255, 207 / 255, 169 / 255, 0.8)
    property color on_secondary: Qt.rgba(29 / 255, 54 / 255, 28 / 255, 0.8)
    property color secondary_container: Qt.rgba(51 / 255, 77 / 255, 48 / 255, 0.8)
    property color on_secondary_container: Qt.rgba(204 / 255, 235 / 255, 196 / 255, 0.8)
    property color tertiary: Qt.rgba(198 / 255, 204 / 255, 131 / 255, 0.8)
    property color inverse_on_surface: Qt.rgba(58 / 255, 45 / 255, 46 / 255, 0.8)
    property color outline_variant: Qt.rgba(87 / 255, 65 / 255, 67 / 255, 0.8)
    property color tertiary_fixed: Qt.rgba(175 / 255, 240 / 255, 213 / 255, 0.8)
    property color tertiary_container: Qt.rgba(7 / 255, 81 / 255, 61 / 255, 0.8)
    property color on_tertiary_container: Qt.rgba(175 / 255, 240 / 255, 213 / 255, 0.8)

    function parse(css) {
        const re = /@define-color\s+(\w+)\s+rgba\((\d+),\s*(\d+),\s*(\d+),\s*[\d.]+\)/g;
        let m;
        while ((m = re.exec(css)) !== null) {
            if (root[m[1]] === undefined)
                continue;
            root[m[1]] = Qt.rgba(m[2] / 255, m[3] / 255, m[4] / 255, root.alpha);
        }
    }

    FileView {
        // Its own palette, `@define-color NAME rgba(…)` lines (matugen
        // writes it from the wallpaper); without it, the colours above
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/margin/colors.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
    }
}
