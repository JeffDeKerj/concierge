#!/usr/bin/env bash
# Shared `swift build` / `swift test` flags. Sourced by make_app.sh and the
# test runner; sets SWIFT_BUILD_FLAGS as an array.
#
# Plain `swift build` works again with the Command Line Tools of
# 2026-11 (checked 2026-11-28). From 2026-09-10 it had needed the native
# build system and the macOS 26.5 SDK; that pin is gone.
SWIFT_BUILD_FLAGS=()

# `swift test` additionally needs the Testing framework, which the Command
# Line Tools keep outside the SDK search path. (There is no XCTest in the
# Command Line Tools at all — tests use Swift Testing.)
TESTING_FW="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
SWIFT_TEST_FLAGS=("${SWIFT_BUILD_FLAGS[@]}")
if [ -d "$TESTING_FW" ]; then
  SWIFT_TEST_FLAGS+=(-Xswiftc -F -Xswiftc "$TESTING_FW"
                     -Xlinker -F -Xlinker "$TESTING_FW"
                     -Xlinker -rpath -Xlinker "$TESTING_FW")
fi
