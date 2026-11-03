# FFmpeg for DropWheel

The FFmpeg that DropWheel ships, built by `build.sh` on GitHub Actions.

- **Licence:** LGPL version 2.1 or later. No GPL or non-free part is enabled, and FFmpeg is built as DLLs that a
  user can replace with their own build.
- **No patented codec inside.** The build holds no decoder, encoder or parser for any format still covered by a
  patent pool: H.264/AVC, HEVC, VVC, AAC, E-AC-3, TrueHD/MLP, DTS, AMR, VC-1 and WMV, WMA, ProRes, DNxHD, AVS,
  RealVideo 3/4, Cook/ATRAC and the like. Decoders, encoders, parsers and bitstream filters are each an explicit
  list in `build.sh`; everything not named there is left out.
- **Through Windows.** DropWheel writes H.264, HEVC and AAC with Windows' own Media Foundation encoders (`h264_mf`,
  `hevc_mf`, `aac_mf`, which call Windows and contain no codec themselves). It reads files in those formats through
  Windows' Media Foundation as well, and hands FFmpeg the decoded pictures and sound.
- **What remains** are codecs whose patents have expired (MPEG-1/2 video and audio, MP3, MPEG-4 Part 2, H.261/H.263,
  AC-3, JPEG and others) or that their owners license royalty-free (AV1, VP8, VP9, Opus, Vorbis, FLAC, ALAC, WebP,
  Theora, Dirac, FFV1 and others).

The libraries (dav1d, libaom, SVT-AV1, libvpx, libwebp, LAME, Opus, Vorbis, soxr, zimg, libass, FreeType, HarfBuzz,
FriBidi, Fontconfig, libxml2, zlib, liblzma, libiconv) come prebuilt from BtbN's public LGPL build image
(https://github.com/BtbN/FFmpeg-Builds). Their exact versions and the image digest go into `libraries.txt` and
`BUILD.txt` in each build. Each release holds FFmpeg's exact source next to the build.
