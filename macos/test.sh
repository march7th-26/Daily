#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/.build"
STAGE="$(mktemp -d "$ROOT/.build/tests.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
xcrun swiftc -parse-as-library -D DAILY_TESTING \
    "$ROOT/App/JournalStore.swift" "$ROOT/Shared/TodoData.swift" "$ROOT/App/TaskStore.swift" \
    "$ROOT/App/UpdateStore.swift" "$ROOT/App/QuoteStore.swift" \
    "$ROOT/App/PackageValidator.swift" "$ROOT/App/WindowController.swift" "$ROOT/App/Palette.swift" \
    "$ROOT/Widget/DaylightWidget.swift" \
    "$ROOT/Tests/RegressionTests.swift" -o "$STAGE/RegressionTests"
"$STAGE/RegressionTests"

xcrun swiftc -parse-as-library \
    "$ROOT/Shared/TodoData.swift" "$ROOT/App/TaskStore.swift" "$ROOT/App/JournalStore.swift" \
    "$ROOT/App/WindowController.swift" "$ROOT/App/Palette.swift" "$ROOT/App/QuickNoteView.swift" \
    "$ROOT/Tests/NoteInputTests.swift" -o "$STAGE/NoteInputTests"
"$STAGE/NoteInputTests"
