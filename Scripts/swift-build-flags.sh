#!/usr/bin/env bash
# Shared `swift build` / `swift test` flags. Sourced by make_app.sh and the
# test runner; sets SWIFT_BUILD_FLAGS as an array.
#
# The Command Line Tools update of 2026-09-10 (Swift 6.4, macOS 27 SDK) broke
# the default "swiftbuild" backend on this box — every package, even a fresh
# `swift package init`, dies with "Could not initialize build system … Unknown
# error parsing property list". The native backend works but cannot find the
# SwiftUI macro plugin in the macOS 27 SDK, so we pin the previous SDK while
# it is still installed. Delete this once a toolchain update fixes the default.
SDK_265="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [ -d "$SDK_265" ]; then
  SWIFT_BUILD_FLAGS=(--build-system native --sdk "$SDK_265")
else
  SWIFT_BUILD_FLAGS=()
fi

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
