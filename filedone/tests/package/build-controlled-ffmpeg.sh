#!/usr/bin/env bash
set -euo pipefail

VERSION="9.0.1"
ARCHIVE="ffmpeg-${VERSION}.tar.xz"
URL="https://ffmpeg.org/releases/${ARCHIVE}"
EXPECTED_SHA256="cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635"
ROOT="$(pwd)/filedone/out/controlled-ffmpeg"
SRC_ROOT="$ROOT/src"
INSTALL_ROOT="$ROOT/install"

rm -rf "$ROOT"
mkdir -p "$SRC_ROOT" "$INSTALL_ROOT"
cd "$SRC_ROOT"

curl --fail --location --retry 3 --output "$ARCHIVE" "$URL"
echo "${EXPECTED_SHA256} *${ARCHIVE}" | sha256sum --check --strict

tar -xf "$ARCHIVE"
cd "ffmpeg-${VERSION}"

./configure \
  --prefix="$INSTALL_ROOT" \
  --arch=x86_64 \
  --target-os=mingw32 \
  --disable-autodetect \
  --disable-gpl \
  --disable-nonfree \
  --enable-mediafoundation \
  --enable-d3d11va \
  --enable-static \
  --disable-shared \
  --disable-debug \
  --disable-doc \
  --disable-ffplay

make -j2 ffmpeg.exe ffprobe.exe
make install

FFMPEG="$INSTALL_ROOT/bin/ffmpeg.exe"
FFPROBE="$INSTALL_ROOT/bin/ffprobe.exe"
test -f "$FFMPEG"
test -f "$FFPROBE"

"$FFMPEG" -hide_banner -buildconf 2>&1 | tee "$ROOT/buildconf.txt"
if grep -q -- '--enable-gpl' "$ROOT/buildconf.txt"; then
  echo 'CONTROLLED_FFMPEG_REJECTED_GPL' >&2
  exit 1
fi
if grep -q -- '--enable-nonfree' "$ROOT/buildconf.txt"; then
  echo 'CONTROLLED_FFMPEG_REJECTED_NONFREE' >&2
  exit 1
fi
if ! grep -q -- '--enable-mediafoundation' "$ROOT/buildconf.txt"; then
  echo 'CONTROLLED_FFMPEG_MISSING_MEDIAFOUNDATION' >&2
  exit 1
fi

"$FFMPEG" -hide_banner -encoders 2>&1 | tee "$ROOT/encoders.txt"
grep -q 'h264_mf' "$ROOT/encoders.txt"
grep -q 'mp3_mf' "$ROOT/encoders.txt"
grep -Eq '[[:space:]]aac[[:space:]]' "$ROOT/encoders.txt"

"$FFMPEG" -hide_banner -version | head -n 1 | tee "$ROOT/version.txt"
sha256sum "$FFMPEG" "$FFPROBE" | tee "$ROOT/binary-sha256.txt"
cp COPYING.LGPLv2.1 "$ROOT/COPYING.LGPLv2.1"
cp LICENSE.md "$ROOT/FFMPEG_LICENSE.md"

echo 'CONTROLLED_LGPL_FFMPEG_BUILD_PASS'
