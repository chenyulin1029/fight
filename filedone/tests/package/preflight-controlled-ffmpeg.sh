#!/usr/bin/env bash
set -euo pipefail

VERSION="9.0.1"
ARCHIVE="ffmpeg-${VERSION}.tar.xz"
URL="https://ffmpeg.org/releases/${ARCHIVE}"
EXPECTED_SHA256="cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635"
ROOT="$(pwd)/filedone/out/controlled-ffmpeg-preflight"
rm -rf "$ROOT"
mkdir -p "$ROOT"
cd "$ROOT"

cat > d3d11_probe.c <<'EOF'
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxva.h>
ID3D11DeviceContext *p_context;
ID3D11Texture2D *p_texture;
ID3D11VideoDecoder *p_decoder;
ID3D11VideoContext *p_video_context;
int main(void) { return !(p_context == 0 && p_texture == 0 && p_decoder == 0 && p_video_context == 0); }
EOF

set +e
gcc -c d3d11_probe.c -o d3d11_probe.o > d3d11_probe.stdout.txt 2> d3d11_probe.stderr.txt
HEADER_RC=$?
set -e
cat d3d11_probe.stdout.txt || true
cat d3d11_probe.stderr.txt || true
echo "D3D11_HEADER_COMPILE_RC=$HEADER_RC"

curl --fail --location --retry 3 --output "$ARCHIVE" "$URL"
echo "${EXPECTED_SHA256} *${ARCHIVE}" | sha256sum --check --strict
tar -xf "$ARCHIVE"
cd "ffmpeg-${VERSION}"

./configure \
  --prefix="$ROOT/install" \
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
  --disable-ffplay > "$ROOT/configure.stdout.txt" 2> "$ROOT/configure.stderr.txt"

cat "$ROOT/configure.stdout.txt"
cat "$ROOT/configure.stderr.txt"

echo '=== GLOBAL CONFIG MACROS ==='
grep -E '^(#define CONFIG_D3D11VA|#define CONFIG_MEDIAFOUNDATION)' config.h || true

echo '=== COMPONENT CONFIG MACROS ==='
grep -E '^(#define CONFIG_H264_MF_ENCODER|#define CONFIG_MP3_MF_ENCODER|#define CONFIG_AAC_ENCODER)' config_components.h || true

echo '=== CONFIG LOG D3D11VA / DXVA / D3D11 ==='
grep -i -C 4 -E 'd3d11va|dxva_h|ID3D11VideoDecoder|ID3D11VideoContext|d3d11\.h|dxva\.h' ffbuild/config.log | tail -n 240 || true

D3D11_CONFIG=$(awk '/^#define CONFIG_D3D11VA /{print $3}' config.h | tail -n1)
MF_CONFIG=$(awk '/^#define CONFIG_MEDIAFOUNDATION /{print $3}' config.h | tail -n1)
H264_MF_CONFIG=$(awk '/^#define CONFIG_H264_MF_ENCODER /{print $3}' config_components.h | tail -n1)
MP3_MF_CONFIG=$(awk '/^#define CONFIG_MP3_MF_ENCODER /{print $3}' config_components.h | tail -n1)
AAC_CONFIG=$(awk '/^#define CONFIG_AAC_ENCODER /{print $3}' config_components.h | tail -n1)

echo "D3D11VA_CONFIG=${D3D11_CONFIG:-MISSING}"
echo "MEDIAFOUNDATION_CONFIG=${MF_CONFIG:-MISSING}"
echo "H264_MF_ENCODER_CONFIG=${H264_MF_CONFIG:-MISSING}"
echo "MP3_MF_ENCODER_CONFIG=${MP3_MF_CONFIG:-MISSING}"
echo "AAC_ENCODER_CONFIG=${AAC_CONFIG:-MISSING}"

if [[ "$HEADER_RC" -ne 0 ]]; then
  echo 'D3D11_PREFLIGHT_FAIL_HEADERS' >&2
  exit 20
fi
if [[ "${MF_CONFIG:-0}" != "1" || "${H264_MF_CONFIG:-0}" != "1" || "${MP3_MF_CONFIG:-0}" != "1" || "${AAC_CONFIG:-0}" != "1" ]]; then
  echo 'D3D11_PREFLIGHT_FAIL_MEDIAFOUNDATION_CONFIG' >&2
  exit 21
fi
if [[ "${D3D11_CONFIG:-0}" != "1" ]]; then
  echo 'D3D11_PREFLIGHT_FAIL_CONFIG_D3D11VA' >&2
  exit 22
fi

echo 'CONTROLLED_FFMPEG_D3D11_PREFLIGHT_PASS'
