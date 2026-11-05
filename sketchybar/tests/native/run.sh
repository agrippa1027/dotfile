#!/bin/bash
set -euo pipefail
test_root="$(cd "$(dirname "$0")" && pwd)"
engine="${1:-$HOME/dev/SketchyBar}"
bridge="${2:-$HOME/dev/SbarLua}"
build="$(mktemp -d /private/tmp/sketchybar-native-tests.XXXXXX)"
flags=(-std=c99 -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer)
frameworks=(-F/System/Library/PrivateFrameworks)
for framework in Carbon AppKit QuartzCore CoreAudio CoreWLAN CoreVideo IOKit SkyLight DisplayServices MediaRemote; do
  frameworks+=(-framework "$framework")
done

make -C "$engine" arm64 ODIR="$build/engine" \
  CFLAGS="${flags[*]} -Wall -fvisibility=hidden -fno-common" > "$build/build.log" 2>&1 || {
  cat "$build/build.log"
  exit 1
}
objects=()
for object in "$build/engine/"*.o "$build/engine/"*.om; do
  [[ "$object" == */popup.o ]] || objects+=("$object")
done
clang "${flags[@]}" \
  "-DSKETCHYBAR_SOURCE=\"$engine/src/sketchybar.c\"" \
  "-DSKETCHYBAR_POPUP_SOURCE=\"$engine/src/popup.c\"" \
  "$test_root/lazy_windows.c" "${objects[@]}" "${frameworks[@]}" -o "$build/lazy-windows"
"$build/lazy-windows"
clang "${flags[@]}" "$engine/tests/popup_grid.c" -o "$build/grid"
"$build/grid"
clang "${flags[@]}" "$engine/tests/cursor.m" -framework Foundation -framework CoreGraphics -o "$build/cursor"
"$build/cursor"

lua_prefix="$(/opt/homebrew/bin/brew --prefix lua)"
clang "${flags[@]}" -Wno-deprecated-declarations \
  "-DSBARLUA_SOURCE=\"$bridge/src/sketchybar.c\"" "$test_root/sbarlua_callbacks.c" \
  "$bridge/src/parsing.c" "$bridge/src/cJSON.c" \
  "-I$lua_prefix/include/lua" "$lua_prefix/lib/liblua.a" -framework CoreFoundation -o "$build/callbacks"
"$build/callbacks"
printf 'Native sanitizer checks passed. Build outputs: %s\n' "$build"
