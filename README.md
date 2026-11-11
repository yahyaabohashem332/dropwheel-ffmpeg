# FFmpeg for DropWheel

The FFmpeg that DropWheel ships, built by `build.sh` on GitHub Actions.

- **Licence:** LGPL version 2.1 or later. No GPL or non-free part is enabled, and FFmpeg is built as DLLs that a
  user can replace with their own build.
- **No patented codec inside.** The build holds no decoder or encoder for any format still covered by a patent
  pool: H.264/AVC, HEVC, VVC, AAC, E-AC-3, TrueHD/MLP, DTS, AMR, VC-1 and WMV, WMA, ProRes, DNxHD, AVS,
  RealVideo 3/4, Cook/ATRAC and the like. Decoders, encoders, parsers and bitstream filters are each an explicit
  list in `build.sh`; everything not named there is left out. The parsers and bitstream filters only find where
  pictures begin and rewrite headers, so that a stream can be copied into another file untouched; none of them
  decodes or encodes.
- **Through Windows.** DropWheel writes H.264, HEVC and AAC with Windows' own Media Foundation encoders (`h264_mf`,
  `hevc_mf`, `aac_mf`, which call Windows and contain no codec themselves). It reads files in those formats through
  Windows' Media Foundation as well, and hands FFmpeg the decoded pictures and sound.
- **What remains** are codecs whose patents have expired (MPEG-1/2 video and audio, MP3, MPEG-4 Part 2, H.261/H.263,
  AC-3, JPEG and others) or that their owners license royalty-free (AV1, VP8, VP9, Opus, Vorbis, FLAC, ALAC, WebP,
  Theora, Dirac, FFV1 and others).
- **Nothing from the network, nothing encrypted.** No network protocol is built, and neither are the readers of
  Audible's encrypted formats.

## Where every part comes from

Every library inside the DLLs is compiled in each build from a pinned source, by the stage scripts of
[FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) at the commit named in `build.sh`: dav1d, libaom, SVT-AV1,
libvpx, libwebp, LAME, Opus, Ogg and Vorbis, soxr, zimg, libass, FreeType, HarfBuzz, FriBidi, Fontconfig, libxml2,
zlib, liblzma, libiconv, libunibreak and the mingw-w64 runtime, with what they in turn need.

Each release holds:

- `ffmpeg-…-win64.zip`: the programs and DLLs; `LICENSE.txt` (the LGPL); `licenses/`, the licence files of every
  library as they stand in its source; `stages.txt`, the repository and commit each library was built from;
  `configuration.txt`, FFmpeg's configure line; `linked.txt`, what each DLL links; `BUILD.txt`.
- `ffmpeg-…-source.tar.gz`: FFmpeg's exact source, the exact sources of the LGPL libraries (libiconv, FriBidi, LAME,
  soxr) and the scripts that built all of it.
