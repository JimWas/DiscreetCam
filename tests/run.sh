#!/bin/sh
# Build and run the off-device JWR logic tests under GNUstep.
# Requires: gnustep-make, libgnustep-base-dev, clang (or gcc), libblocksruntime-dev.
# On Debian/Ubuntu the required packages are installed automatically when
# gnustep-config is missing. tests/shim, tests/objc, and tests/dispatch
# headers stand in for headers the harness does not otherwise have on Linux.
set -e
cd "$(dirname "$0")"

echo "[jwr-tests] start $(date -u +%H:%M:%S)"

if ! command -v gnustep-config >/dev/null 2>&1; then
    if [ "$(uname -s)" = "Linux" ] && command -v apt-get >/dev/null 2>&1; then
        echo "[jwr-tests] installing GNUstep toolchain..."
        apt-get update -qq >/dev/null 2>&1 || true
        pkgs="clang libgnustep-base-dev gnustep-make make"
        for p in libblocksruntime-dev libobjc-dev gobjc; do
            apt-cache policy "$p" 2>/dev/null | grep -q Candidate && pkgs="$pkgs $p"
        done
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkgs
    else
        echo "GNUstep toolchain not found (gnustep-config missing)." >&2
        echo "This project's tests/run.sh installs it on Debian/Ubuntu." >&2
        exit 2
    fi
fi

mkdir -p build

OBJC_FLAGS="$(gnustep-config --objc-flags) -O0 -g0 -fblocks -fobjc-exceptions"
BASE_LIBS="$(gnustep-config --base-libs)"
RUNTIME_INC=""
if command -v gcc >/dev/null 2>&1; then
    RUNTIME_INC="-I$(gcc -print-file-name=include)"
fi
SOURCES="main.m JWRLogicTests.m JWRTestSupport.m JWRMovieValidationStub.m JWRPreferencesStub.m notify_stub.c ../JWROutputFiles.m ../JWRButtonRouter.m ../JWRPreferences+Normalization.m ../JWRLogger.m"
OUT="build/jwr-logic-tests"

if command -v clang >/dev/null 2>&1; then
    CC="clang"
else
    CC="gcc"
fi

# One frontend at a time keeps peak memory below the sandbox guard; reuse
# objects that are newer than their source so warm runs are quick.
OBJ=""
for src in $SOURCES; do
    name=$(basename "$src")
    obj="build/${name%.*}.o"
    if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
        $CC $OBJC_FLAGS $RUNTIME_INC -I. -Ishim -I.. -c "$src" -o "$obj"
    fi
    OBJ="$OBJ $obj"
done
$CC $BASE_LIBS -o "$OUT" $OBJ -lBlocksRuntime
echo "[jwr-tests] running..."
"./$OUT" > build/last-run.log 2>&1
status=$?
tail -n 80 build/last-run.log
exit $status
