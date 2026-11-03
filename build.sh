#!/bin/bash
# Builds the FFmpeg that DropWheel ships: LGPL v2.1 or later, shared DLLs, and no implementation of any codec still
# covered by a patent pool. H.264, HEVC and AAC are written through Windows' own Media Foundation encoders (h264_mf,
# hevc_mf, aac_mf), and DropWheel decodes those formats through Windows before handing FFmpeg raw pictures and sound.
#
# The libraries come prebuilt in BtbN's public LGPL build image (https://github.com/BtbN/FFmpeg-Builds); only FFmpeg
# itself is configured and compiled here, so every component it may contain is listed below.
#
# Usage: ./build.sh win64|winarm64 <output folder>
set -euo pipefail
TARGET="$1"
OUT="$(realpath -m "$2")"
FFMPEG_TAG="n9.0.2"
FFMPEG_COMMIT="946fcce07b6dcd0331c8cc609192aeff5e1924f8"
IMAGE="ghcr.io/btbn/ffmpeg-builds/${TARGET}-lgpl-shared-9.0:latest"

join() { local IFS=,; echo "$*"; }

# Codecs whose patents have expired or whose owners license them royalty-free.
DECODERS=(
    # video
    av1 libdav1d vp8 vp9 theora vp3 mpeg1video mpeg2video mpeg4 h261 h263 h263i h263p flv
    mjpeg mjpegb jpeg2000 jpegls png apng gif webp bmp tiff ppm pgm pgmyuv pbm pam pcx targa sgi qoi hdr dpx
    ffv1 ffvhuff huffyuv utvideo rawvideo v210 yuv4 qtrle msrle msvideo1 cinepak dirac snow
    # audio
    mp1 mp1float mp2 mp2float mp3 mp3float flac alac opus vorbis ac3 ac3_fixed ape tta wavpack gsm gsm_ms
    pcm_alaw pcm_mulaw pcm_s8 pcm_u8 pcm_s16le pcm_s16be pcm_u16le pcm_u16be pcm_s24le pcm_s24be pcm_u24le pcm_u24be
    pcm_s32le pcm_s32be pcm_u32le pcm_u32be pcm_s64le pcm_s64be pcm_f16le pcm_f24le pcm_f32le pcm_f32be pcm_f64le pcm_f64be
    pcm_s16le_planar pcm_s24le_planar pcm_s32le_planar pcm_s8_planar pcm_s16be_planar pcm_dvd pcm_bluray pcm_lxf
    adpcm_ima_wav adpcm_ima_qt adpcm_ms adpcm_yamaha adpcm_swf adpcm_g726 adpcm_g726le
    # subtitles
    ass ssa srt subrip movtext webvtt text microdvd subviewer subviewer1 sami realtext mpl2 pjs jacosub vplayer stl
    dvdsub dvbsub pgssub xsub ccaption
)
ENCODERS=(
    # Windows' own encoders for the patented formats
    h264_mf hevc_mf aac_mf
    # royalty-free or expired
    libaom_av1 libsvtav1 libvpx_vp8 libvpx_vp9 mpeg4 mjpeg png apng gif libwebp libwebp_anim ffv1 utvideo rawvideo
    bmp tiff wrapped_avframe
    libmp3lame libopus opus libvorbis flac alac
    pcm_alaw pcm_mulaw pcm_s8 pcm_u8 pcm_s16le pcm_s16be pcm_s24le pcm_s24be pcm_s32le pcm_s32be pcm_f32le pcm_f32be
    pcm_f64le pcm_f64be
    ass ssa srt subrip movtext webvtt text
)
PARSERS=(
    ac3 av1 dirac dvbsub dvdsub flac gif h261 h263 jpeg2000 mjpeg mpeg4video mpegaudio mpegvideo opus png pnm
    vorbis vp3 vp8 vp9 webp bmp qoi
)
# Bitstream filters that only rewrite headers or split and join packets; none of them codes pictures or sound.
BSFS=(aac_adtstoasc chomp dump_extradata null setts
      pgs_frame_merge mpeg4_unpack_bframes text2movsub mov2textsub vp9_metadata vp9_superframe vp9_superframe_split
      vp9_raw_reorder av1_metadata av1_frame_merge av1_frame_split
)

CONFIGURE=(
    --prefix=/work/prefix --pkg-config-flags=--static
    --enable-shared --disable-static --disable-debug --disable-doc --disable-ffplay
    --disable-autodetect --disable-w32threads --enable-pthreads
    --enable-mediafoundation --enable-zlib --enable-lzma --enable-iconv --enable-libxml2
    --enable-libdav1d --enable-libaom --enable-libsvtav1 --enable-libvpx --enable-libwebp
    --enable-libmp3lame --enable-libopus --enable-libvorbis --enable-libsoxr --enable-libzimg
    --enable-libass --enable-libfreetype --enable-libharfbuzz --enable-libfribidi --enable-fontconfig
    --disable-decoders --enable-decoder="$(join "${DECODERS[@]}")"
    --disable-encoders --enable-encoder="$(join "${ENCODERS[@]}")"
    --disable-parsers --enable-parser="$(join "${PARSERS[@]}")"
    --disable-bsfs --enable-bsf="$(join "${BSFS[@]}")"
    --disable-hwaccels --disable-outdevs --disable-indevs --enable-indev=lavfi
)

WORK="$(mktemp -d)"
chmod 777 "$WORK"
cat > "$WORK/inner.sh" <<EOF
set -xe
cd /work
git init -q ffmpeg && cd ffmpeg
git fetch -q --depth 1 https://github.com/FFmpeg/FFmpeg.git $FFMPEG_COMMIT
git checkout -q FETCH_HEAD
./configure \$FFBUILD_TARGET_FLAGS $(printf "'%s' " "${CONFIGURE[@]}") \\
    --extra-cflags="\$FF_CFLAGS" --extra-cxxflags="\$FF_CXXFLAGS" --extra-libs="\$FF_LIBS" \\
    --extra-ldflags="\$FF_LDFLAGS" --extra-ldexeflags="\$FF_LDEXEFLAGS" \\
    --cc="\$CC" --cxx="\$CXX" --ar="\$AR" --ranlib="\$RANLIB" --nm="\$NM" \\
    --extra-version=dropwheel || { tail -300 ffbuild/config.log; exit 1; }
make -j\$(nproc)
make install
grep -h "^#define FFMPEG_CONFIGURATION" config.h > /work/configuration.txt
git archive --format=tar.gz --prefix=ffmpeg-$FFMPEG_TAG/ -o /work/ffmpeg-$FFMPEG_TAG-source.tar.gz HEAD
cp COPYING.LGPLv2.1 /work/LICENSE.txt
for lib in dav1d aom SvtAv1Enc vpx libwebp mp3lame opus vorbis soxr zimg libass freetype2 harfbuzz fribidi fontconfig libxml-2.0 zlib liblzma; do
    echo "\$lib \$(pkg-config --modversion \$lib 2>/dev/null || echo '?')"
done > /work/libraries.txt
EOF
docker pull -q "$IMAGE"
DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "$IMAGE")"
docker run --rm -u "$(id -u):$(id -g)" -v "$WORK":/work "$IMAGE" bash /work/inner.sh

PKG="ffmpeg-$FFMPEG_TAG-dropwheel-$TARGET"
mkdir -p "$OUT/$PKG"
cp "$WORK"/prefix/bin/*.exe "$WORK"/prefix/bin/*.dll "$OUT/$PKG"/
cp "$WORK"/LICENSE.txt "$WORK"/configuration.txt "$WORK"/libraries.txt "$OUT/$PKG"/
{
    echo "FFmpeg $FFMPEG_TAG ($FFMPEG_COMMIT), built for DropWheel by build.sh in this repository."
    echo "Libraries from $DIGEST"
    echo "FFmpeg's source: ffmpeg-$FFMPEG_TAG-source.tar.gz beside this build; the libraries' source: https://github.com/BtbN/FFmpeg-Builds/tree/master/scripts.d"
} > "$OUT/$PKG/BUILD.txt"
cp "$WORK/ffmpeg-$FFMPEG_TAG-source.tar.gz" "$OUT"/
(cd "$OUT" && zip -9 -qr "$PKG.zip" "$PKG")
echo "package=$PKG" >> "${GITHUB_OUTPUT:-/dev/null}"
