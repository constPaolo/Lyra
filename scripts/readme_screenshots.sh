#!/usr/bin/env bash
# Retakes the README screenshots in docs/ with a debug build in demo mode
# (see Sources/Lyra/App/DemoMode.swift).
#
# It runs a copy of the binary named "LyraDemo", which keeps its own
# preferences (seeded from yours), so your history, likes and volume aren't
# touched. Songs play muted. The Recap shot uses made-up listening history,
# written only to LyraDemo's own history file (deleted at the end). The app comes to the front for each shot:
# don't type while it runs (about a minute).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build
BIN_DIR="$(swift build --show-bin-path)"
cp "$BIN_DIR/Lyra" "$BIN_DIR/LyraDemo"

TMP_DIR="$(mktemp -d)"
cat > "$TMP_DIR/window_id.swift" <<'SWIFT'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
if let w = windows.first(where: { ($0[kCGWindowOwnerName as String] as? String) == "LyraDemo"
                                  && ($0[kCGWindowLayer as String] as? Int) == 0 }) {
    print(w[kCGWindowNumber as String]!)
}
SWIFT

seed_preferences() {
    defaults delete LyraDemo >/dev/null 2>&1 || true
    defaults export Lyra - | defaults import LyraDemo -
}

# shot <file name> <seconds to wait> <launch arguments...>
shot() {
    local name="$1" wait="$2"
    shift 2
    pkill -x LyraDemo >/dev/null 2>&1 || true
    "$BIN_DIR/LyraDemo" -LyraDemoSize 1280x800 "$@" >/dev/null 2>&1 &
    sleep "$wait"
    local id
    id="$(swift "$TMP_DIR/window_id.swift")"
    screencapture -o -x -l "$id" "$TMP_DIR/$name.png"
    sips --resampleWidth 1600 "$TMP_DIR/$name.png" --out "docs/$name.png" >/dev/null
    pkill -x LyraDemo || true
    sleep 1
    echo "docs/$name.png"
}

seed_preferences
shot home        7  -LyraDemoAppearance light -LyraDemo home -LyraDemoPlay "Let It Happen" -LyraDemoSeek 49
shot lyrics-dark 9  -LyraDemoAppearance dark  -LyraDemo lyrics -LyraDemoPlay "The Less I Know The Better" -LyraDemoSeek 62
shot search      7  -LyraDemoAppearance light -LyraDemo "search:tame" -LyraDemoPlay "Let It Happen" -LyraDemoSeek 49
shot visualizer  9  -LyraDemoAppearance light -LyraDemo visualizer -LyraDemoPlay "Let It Happen" -LyraDemoSeek 130
shot album       7  -LyraDemoAppearance light -LyraDemo album -LyraDemoPlay "Level Up"
shot albums-dark 7  -LyraDemoAppearance dark  -LyraDemo albums -LyraDemoPlay "Level Up"
shot playlist    7  -LyraDemoAppearance light -LyraDemo "playlist:Late Night Coding" -LyraDemoPlay "Weird Fishes"
shot settings    7  -LyraDemoAppearance light -LyraDemo settings
shot recap       7  -LyraDemoAppearance light -LyraDemo recap -LyraDemoSeedHistory YES -LyraDemoPlay "Let It Happen" -LyraDemoSeek 49

# Onboarding needs an empty library.
defaults delete LyraDemo >/dev/null 2>&1 || true
shot onboarding  5  -LyraDemoAppearance light -LyraDemo onboarding

# The app writes its preferences back as it quits: give it a moment.
sleep 2
defaults delete LyraDemo >/dev/null 2>&1 || true
rm -rf "$HOME/Library/Application Support/LyraDemo"
rm -f "$BIN_DIR/LyraDemo"
rm -rf "$TMP_DIR"
