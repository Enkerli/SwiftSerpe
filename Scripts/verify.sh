#!/bin/bash
#
# Checks the parts of SwiftSerpe that Xcode's test targets can't reach.
#
#   Scripts/verify.sh          # all suites
#   Scripts/verify.sh upi      # one suite
#
# Suites:
#   identity — the audio component triple is unique across every sibling
#              checkout, JUCE and Swift alike, and matches the host app's
#              lookup. First, because codes are forever and this project was
#              scaffolded from another one's.
#   upi      — the Swift UPI parser against packages/upi/vectors/upi.json in
#              music-suite: every case PASS, DIFF or NOT PORTED, with the
#              not-ported forms named in the output. This is the whole reason
#              those vectors were written.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="$REPO/SwiftSerpeExtension"
PACKAGE="${ENKERLI_SWIFT:-$REPO/../enkerli-swift}"
MUSIC_SUITE="${MUSIC_SUITE:-$REPO/../music-suite}"

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

which="${1:-all}"
status=0

PKG_BIN=""
build_package() {
    [ -n "$PKG_BIN" ] && return 0
    if [ ! -f "$PACKAGE/Package.swift" ]; then
        echo "FAIL: no foundation package at $PACKAGE"
        echo "      git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift"
        echo "      (or set ENKERLI_SWIFT=/path/to/enkerli-swift)"
        status=1
        return 1
    fi
    swift build --package-path "$PACKAGE" >/dev/null || {
        echo "FAIL: the foundation package did not build"; status=1; return 1; }
    PKG_BIN="$(swift build --package-path "$PACKAGE" --show-bin-path)"
}

# UI and Shell are left out — these suites are headless — and so are the
# package's own test targets, whose objects carry a second `main`.
package_flags() {
    build_package || return 1
    echo "-I $PKG_BIN/Modules"
    find "$PKG_BIN" -name "*.o" ! -path "*/UI.build/*" ! -path "*/Shell.build/*" \
        ! -path "*Tests.build/*" | sort
}

# Every extension source that does not need the AU shell: the notation, the
# analysis, the session. The two AU subclasses and the view need CoreAudioKit
# and a host, and are checked by building the schemes.
headless_sources() {
    find "$EXT/UPI" "$EXT/Rhythm" -name "*.swift" 2>/dev/null | sort
}

run_identity() {
    echo "── identity ───────────────────────────────────────"
    python3 "$REPO/Scripts/tests/component-identity.py" || status=1
}

run_upi() {
    echo "── upi ────────────────────────────────────────────"
    cp "$REPO/Scripts/tests/upi-main.swift" "$BUILD/main.swift"
    swiftc -Onone $(package_flags) $(headless_sources) "$BUILD/main.swift" \
        -o "$BUILD/upi" || { status=1; return 0; }
    MUSIC_SUITE="$MUSIC_SUITE" "$BUILD/upi" || status=1
}

case "$which" in
    identity) run_identity ;;
    upi) run_upi ;;
    all) run_identity; run_upi ;;
    *) echo "unknown suite: $which"; exit 2 ;;
esac

echo
if [ $status -eq 0 ]; then echo "verify: OK"; else echo "verify: FAILURES"; fi
exit $status
