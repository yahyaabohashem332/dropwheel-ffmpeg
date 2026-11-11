#!/bin/bash
# Builds the FFmpeg that DropWheel ships: LGPL v2.1 or later, shared DLLs, and no decoder or encoder of any format
# still covered by a patent pool. H.264, HEVC and AAC are written through Windows' own Media Foundation encoders
# (h264_mf, hevc_mf, aac_mf, which call Windows and hold no codec themselves), and DropWheel decodes those formats
# through Windows before handing FFmpeg raw pictures and sound.
#
# Every library is compiled here from a pinned source by the stage scripts of FFmpeg-Builds
# (https://github.com/BtbN/FFmpeg-Builds) at a fixed commit, so the exact source of everything inside the DLLs is
# known. The sources of FFmpeg and of the LGPL libraries go out with each build, with the scripts that built them,
# and the licence files of every library go in the package.
#
# Usage: ./build.sh win64 <output folder>
set -euo pipefail
# On GitHub Actions: compiling every library needs more disk than the runner has free.
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
    sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL /usr/local/share/boost /usr/share/swift
    df -h /
fi
TARGET="$1"
OUT="$(realpath -m "$2")"
HERE="$(cd "$(dirname "$0")" && pwd)"
FFMPEG_TAG="n9.0.2"
FFMPEG_COMMIT="946fcce07b6dcd0331c8cc609192aeff5e1924f8"
BUILDS_REPO="https://github.com/BtbN/FFmpeg-Builds.git"
BUILDS_COMMIT="c9fe5114060e507409f7ee07edfd82efaf25d767"
VARIANT="lgpl-shared"
ADDIN="9.0"

# The libraries FFmpeg is configured with below, by their stage names in FFmpeg-Builds; each brings what it needs.
STAGES=(libiconv zlib xz libxml2 fribidi fonts libass libvorbis libmp3lame libopus soxr zimg dav1d aom svtav1 libvpx libwebp)
# Of those, the ones under the LGPL: like FFmpeg's own, their exact source goes out with every build.
LGPL_STAGES=(libiconv fribidi libmp3lame soxr)

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
    # FFmpeg's own pictures and sound as filters make them: what a lavfi source (-f lavfi -i color=...) hands on
    wrapped_avframe
)
ENCODERS=(
    # Windows' own encoders for the patented formats
    h264_mf hevc_mf aac_mf
    # royalty-free or expired; h263 is the base the mpeg4 encoder is built on
    libaom_av1 libsvtav1 libvpx_vp8 libvpx_vp9 mpeg4 h263 mjpeg png apng gif libwebp libwebp_anim ffv1 utvideo rawvideo
    bmp tiff wrapped_avframe
    libmp3lame libopus opus libvorbis flac alac
    pcm_alaw pcm_mulaw pcm_s8 pcm_u8 pcm_s16le pcm_s16be pcm_s24le pcm_s24be pcm_s32le pcm_s32be pcm_f32le pcm_f32be
    pcm_f64le pcm_f64be
    ass ssa srt subrip movtext webvtt text
)
# Parsers only find where each picture or frame begins and read a stream's headers, so that a stream can be copied
# into another file untouched. None of them decodes; the h264, hevc, aac, dca, mlp, evc and apv ones are what
# FFmpeg's readers of those streams ask for.
PARSERS=(
    ac3 av1 dirac dvbsub dvdsub flac gif h261 h263 jpeg2000 mjpeg mpeg4video mpegaudio mpegvideo opus png pnm
    vorbis vp3 vp8 vp9 webp bmp qoi
    h264 hevc aac dca mlp tak evc apv
)
# Bitstream filters that only rewrite headers or split and join packets; none of them codes pictures or sound.
BSFS=(aac_adtstoasc chomp dump_extradata null setts
      pgs_frame_merge mpeg4_unpack_bframes text2movsub mov2textsub vp9_metadata vp9_superframe vp9_superframe_split
      vp9_raw_reorder av1_metadata av1_frame_merge av1_frame_split
      extract_extradata h264_mp4toannexb hevc_mp4toannexb vvc_mp4toannexb evc_frame_merge eia608_to_smpte436m pcm_rechunk
)

CONFIGURE=(
    --prefix=/work/prefix --pkg-config-flags=--static
    --enable-shared --disable-static --disable-debug --disable-doc --disable-ffplay
    --disable-autodetect --disable-w32threads --enable-pthreads
    # D3D11 is only the way h264_mf and hevc_mf can take pictures from the graphics card; with no hardware
    # decoder built (--disable-hwaccels), nothing decodes through it.
    --enable-mediafoundation --enable-d3d11va
    --enable-zlib --enable-lzma --enable-iconv --enable-libxml2
    --enable-libdav1d --enable-libaom --enable-libsvtav1 --enable-libvpx --enable-libwebp
    --enable-libmp3lame --enable-libopus --enable-libvorbis --enable-libsoxr --enable-libzimg
    --enable-libass --enable-libfreetype --enable-libharfbuzz --enable-libfribidi --enable-fontconfig
    --disable-decoders --enable-decoder="$(join "${DECODERS[@]}")"
    --disable-encoders --enable-encoder="$(join "${ENCODERS[@]}")"
    --disable-parsers --enable-parser="$(join "${PARSERS[@]}")"
    --disable-bsfs --enable-bsf="$(join "${BSFS[@]}")"
    --disable-hwaccels --disable-outdevs --disable-indevs --enable-indev=lavfi
    # DropWheel works on the files on the PC: no network protocol is built.
    --disable-network
    # Audible's own formats are encrypted; reading them would mean getting round that protection.
    --disable-demuxer=aa,aax
)

WORK="$(mktemp -d)"
chmod 777 "$WORK"
git clone -q "$BUILDS_REPO" "$WORK/builds"
git -C "$WORK/builds" checkout -q "$BUILDS_COMMIT"
cd "$WORK/builds"
# FFmpeg-Builds names its images after the repository it runs in; on GitHub Actions that would be this one.
export GITHUB_REPOSITORY="ffmpeg-builds/ffmpeg-builds"

# What a stage depends on, as FFmpeg-Builds' generate.sh finds it.
stage_deps() {
    (
        source util/vars.sh "$TARGET" "$VARIANT" "$ADDIN" >/dev/null
        source util/dl_functions.sh
        SELF="$1"
        source "$1"
        ffbuild_enabled || exit 0
        ffbuild_depends
    )
}
deps_of() {
    local path sub
    for path in scripts.d/??-"$1" scripts.d/??-"$1".sh; do
        if [[ -d "$path" ]]; then
            for sub in "$path"/*.sh; do stage_deps "$sub"; done
        elif [[ -f "$path" ]]; then
            stage_deps "$path"
        fi
    done | sort -u
}

# Only the stages above and what they need are built: the final stage depends on them alone, and every other
# stage script is taken out.
declare -A KEEP=()
QUEUE=("${STAGES[@]}")
while ((${#QUEUE[@]})); do
    S="${QUEUE[0]}"
    QUEUE=("${QUEUE[@]:1}")
    [[ -n "${KEEP[$S]:-}" ]] && continue
    KEEP[$S]=1
    for D in $(deps_of "$S"); do QUEUE+=("$D"); done
done
for ENTRY in scripts.d/*; do
    NAME="$(basename "$ENTRY" .sh)"
    NAME="${NAME#??-}"
    [[ "$NAME" == final || -n "${KEEP[$NAME]:-}" ]] || rm -rf "$ENTRY"
done
awk -v deps="${STAGES[*]}" '
    /^ffbuild_depends\(\) *\{/ { print; n = split(deps, d, " "); for (i = 1; i <= n; i++) print "    echo " d[i]; skip = 1; next }
    skip && /^\}/ { skip = 0 }
    !skip { print }
' scripts.d/zz-final.sh > "$WORK/zz-final.sh"
mv "$WORK/zz-final.sh" scripts.d/zz-final.sh
echo "Stages built: $(ls scripts.d | tr '\n' ' ')"

# Every enabled stage and the source it was built from.
for ENTRY in scripts.d/*.sh scripts.d/*/*.sh; do
    (
        source util/vars.sh "$TARGET" "$VARIANT" "$ADDIN" >/dev/null
        source util/dl_functions.sh
        SELF="$ENTRY"
        source "$ENTRY"
        ffbuild_enabled || exit 0
        [[ -n "${SCRIPT_SKIP:-}" ]] && exit 0
        echo "$(basename "$ENTRY" .sh) $(set | grep -E '^SCRIPT_[A-Z0-9_]+=' | tr '\n' ' ')"
    )
done > "$WORK/stages.txt"
cat "$WORK/stages.txt"

BASE_IMAGE="ghcr.io/${GITHUB_REPOSITORY}/base-${TARGET}:latest"
docker pull -q "$BASE_IMAGE"
BASE_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "$BASE_IMAGE")"
QUICKBUILD=1 ./makeimage.sh "$TARGET" "$VARIANT" "$ADDIN"
IMAGE="ghcr.io/${GITHUB_REPOSITORY}/${TARGET}-${VARIANT}-${ADDIN}:latest"

cat > "$WORK/inner.sh" <<EOF
set -xe
cd /work
git init -q ffmpeg && cd ffmpeg
git fetch -q --depth 1 https://github.com/FFmpeg/FFmpeg.git $FFMPEG_COMMIT
git checkout -q FETCH_HEAD
# With autodetection off, configure looks for iconv in the C library only (mingw has none) and so never links the
# libiconv it compiled against: it is named here.
./configure \$FFBUILD_TARGET_FLAGS $(printf "'%s' " "${CONFIGURE[@]}") \\
    --extra-cflags="\$FF_CFLAGS" --extra-cxxflags="\$FF_CXXFLAGS" --extra-libs="\$FF_LIBS -liconv" \\
    --extra-ldflags="\$FF_LDFLAGS" --extra-ldexeflags="\$FF_LDEXEFLAGS" \\
    --cc="\$CC" --cxx="\$CXX" --ar="\$AR" --ranlib="\$RANLIB" --nm="\$NM" \\
    --extra-version=dropwheel || { tail -300 ffbuild/config.log; exit 1; }
make -j\$(nproc)
make install
grep -h "^#define FFMPEG_CONFIGURATION" config.h > /work/configuration.txt
grep -h "^EXTRALIBS" ffbuild/config.mak > /work/linked.txt
git archive --format=tar.gz --prefix=ffmpeg-$FFMPEG_TAG/ -o /work/ffmpeg-$FFMPEG_TAG-source.tar.gz HEAD
cp COPYING.LGPLv2.1 /work/LICENSE.txt
for pc in \${FFBUILD_PREFIX:-/opt/ffbuild}/lib/pkgconfig/*.pc; do
    lib="\$(basename "\$pc" .pc)"
    echo "\$lib \$(pkg-config --modversion "\$lib" 2>/dev/null || echo '?')"
done > /work/libraries.txt
EOF
docker run --rm -u "$(id -u):$(id -g)" -v "$WORK":/work "$IMAGE" bash /work/inner.sh

PKG="ffmpeg-$FFMPEG_TAG-dropwheel-$TARGET"
mkdir -p "$OUT/$PKG" "$OUT/sources"
cp "$WORK"/prefix/bin/*.exe "$WORK"/prefix/bin/*.dll "$OUT/$PKG"/
cp "$WORK"/LICENSE.txt "$WORK"/configuration.txt "$WORK"/libraries.txt "$WORK"/linked.txt "$WORK"/stages.txt "$OUT/$PKG"/
{
    echo "FFmpeg $FFMPEG_TAG ($FFMPEG_COMMIT), built for DropWheel by build.sh in https://github.com/yahyaabohashem332/dropwheel-ffmpeg."
    echo "Libraries compiled by FFmpeg-Builds $BUILDS_COMMIT ($BUILDS_REPO), toolchain $BASE_DIGEST."
    echo "stages.txt names the source of every library; licenses/ holds each one's licence files."
    echo "The source of FFmpeg and of the LGPL libraries, with the scripts that built them: $PKG-source.tar.gz beside this build."
} > "$OUT/$PKG/BUILD.txt"

# The licence files of every library, and the sources the LGPL asks for.
python3 "$HERE/collect.py" "$WORK/builds/.cache/downloads" "$WORK/stages.txt" "$OUT/$PKG/licenses" "$OUT/sources" "${LGPL_STAGES[@]}"
cp "$WORK/ffmpeg-$FFMPEG_TAG-source.tar.gz" "$OUT/sources/"
tar --exclude=.git --exclude=.cache --transform 's,^builds,FFmpeg-Builds,' -czf "$OUT/sources/build-scripts.tar.gz" \
    -C "$HERE" build.sh collect.py README.md .github -C "$WORK" builds
cp "$OUT/$PKG/BUILD.txt" "$OUT/$PKG/stages.txt" "$OUT/sources/"

(cd "$OUT" && zip -9 -qr "$PKG.zip" "$PKG" && tar -czf "$PKG-source.tar.gz" sources)
echo "package=$PKG" >> "${GITHUB_OUTPUT:-/dev/null}"
