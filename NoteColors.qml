pragma Singleton

import Quickshell
import QtQuick

// Note colours: Keep's twelve, by Keep's names (the backend's COLORS), so
// notes imported from Keep keep theirs. Each is Keep's dark-theme colour
// laid over the theme's surface, so they sit in with the wallpaper's
// palette rather than on top of it.
Singleton {
    id: root

    readonly property var names: ["", "red", "orange", "yellow", "green", "teal", "blue", "darkblue", "purple", "pink", "brown", "gray"]
    readonly property var keep: ({
            red: "#77172e",
            orange: "#692b17",
            yellow: "#7c4a03",
            green: "#264d3b",
            teal: "#0c625d",
            blue: "#256377",
            darkblue: "#284255",
            purple: "#472e5b",
            pink: "#6c394f",
            brown: "#4b443a",
            gray: "#3c3f43"
        })
    readonly property var titles: ({
            "": "Default",
            red: "Coral",
            orange: "Peach",
            yellow: "Sand",
            green: "Mint",
            teal: "Sage",
            blue: "Fog",
            darkblue: "Storm",
            purple: "Dusk",
            pink: "Blossom",
            brown: "Clay",
            gray: "Chalk"
        })

    // A note's fill
    function fill(name) {
        const c = keep[name];
        return c ? Qt.tint(Theme.surface_container_high, Qt.alpha(c, 0.8)) : Theme.surface_container_high;
    }
}
