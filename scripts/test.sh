#!/bin/bash
# Run OpenGram tests via SPM.
# Swift Testing framework requires explicit paths when using Command Line Tools without Xcode.
FRAMEWORK_PATH="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
exec swift test \
    -Xswiftc -I -Xswiftc "$FRAMEWORK_PATH" \
    -Xswiftc -F -Xswiftc "$FRAMEWORK_PATH" \
    -Xlinker -rpath -Xlinker "$FRAMEWORK_PATH" \
    "$@"
