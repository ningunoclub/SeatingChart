#!/usr/bin/env bash
set -euo pipefail

# swift-testing ships inside the Command Line Tools developer directory when no
# full Xcode is installed. SwiftPM's generated test runner does not add that to
# its framework search path, so a bare `swift test` there builds fine but
# silently runs zero tests. Pass the path explicitly when that is the situation.
FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
EXTRA=()
if [[ ! -d /Applications/Xcode.app && -d "$FRAMEWORKS/Testing.framework" ]]; then
    EXTRA+=(-Xswiftc -F -Xswiftc "$FRAMEWORKS")
fi

cd "$(dirname "$0")/.."
exec swift test ${EXTRA[@]+"${EXTRA[@]}"} "$@"
