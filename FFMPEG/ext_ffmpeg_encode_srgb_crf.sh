#!/bin/sh
#
# This shell script will encode a specific video file using
# ffmpeg and the x264 library to generate a .m4v video file
# that contains compressed H264 encoded video output. The
# .m4v video file format can be read natively in iOS.
#
# ext_ffmpeg_encode_srgb_crf.sh IN.mov OUT.m4v ?CRF? ?PROFILE?
#
# IN.mov : name of Quicktime Animation codec .mov file or other ffmpeg compat input
# OUT.m4v : name of output H264 file
# CRF : Quality integer value in range 1 to 50. 1 is max quality, 50 is lowest
#  while the default quality is 23.
# PROFILE : "baseline" (default) or "main" or "high"

INPUT=$1
OUTPUT=$2
CRF=$3
PROFILESTR=$4

USAGE="usage : ext_ffmpeg_encode_srgb_crf.sh IN.mov OUT.m4v ?CRF? ?PROFILE?"

if test "$INPUT" = ""; then
  echo "$USAGE : INPUT ARGUMENT MISSING"
  exit 1
fi

if test "$OUTPUT" = ""; then
  echo "$USAGE : OUTPUT ARGUMENT MISSING"
  exit 1
fi

# 1 Pass encoding with a "Constant Rate Factor"
# CFR range: 0 -> 51 (0 = lossless, 23 default, 51 lowest quality)

if test "$CRF" = ""; then
  CRF=23
fi

if test "$PROFILESTR" = ""; then
  #PROFILESTR=baseline
  PROFILESTR=main
fi

if test "$PROFILESTR" = "baseline"; then
  PIXFMT=yuv420p
  PROFILE="-profile:v baseline"
fi

if test "$PROFILESTR" = "main"; then
  PIXFMT=yuv420p
  PROFILE="-profile:v main"
fi

if test "$PROFILESTR" = "high"; then
  PIXFMT=yuv420p
  PROFILE="-profile:v high"
fi

# DO NOT use the "veryslow" preset, it generates .mov or .m4v files that will not actually
# play on iOS hardware.

#PRESET="-preset:v veryslow"
PRESET="-preset:v slow"

# Baseline is used to create videos that are compatible with all iOS
# devices from older iPhones to new iPad devices.
#PIXFMT=yuv420p
#PROFILE="-profile:v baseline"

# Main profile still uses 4:2:0 but it could produce videos that
# are smaller than baseline. The downside is that videos encoded
# with main will not play on old iPhones. Uses more powerful
# CABAC encoder.
#PIXFMT=yuv420p
#PROFILE="-profile:v main"

# The plain high profile still makes use of 4:2:0 but should
# have access to better compression.
#PIXFMT=yuv420p
#PROFILE="-profile:v high"

# The High 4:2:2 Profile (Hi422P) enables use of 4:2:2 pixels
# and only works with iPad2 and iPad3 and iPhone 4S. Also note
# that 4:2:2 video will not play with Quicktime player or Mplayer.
#PIXFMT=yuv422p
#PROFILE="-profile:v high422"

# The High 4:4:4 Profile should be as close to lossless as
# the color conversion gets.
#PIXFMT=yuv444p
#PROFILE="-profile:v high444"

# If the 4:4:4 lossless mode is enabled with -crf 0, then should
# disable the 8x8 DCT logic since it seems to be incompatable
# with the H.264 specs. This disables 8x8 DCT and refs to 8x8 blocks.
# FLAGS=-x264opts no-8x8dct:no-mixed-refs

# Colorspace flags to explicitly set BT.709 except for gamma as sRGB
# Rec.709
COLORSPACE="-color_primaries bt709 -color_trc iec61966_2_1 -colorspace bt709"

# By default, x264 --tune is not set. The film setting should
# be used for live video input with film grain. The animation
# setting should be used for generated images with consistent
# and smooth colors without grain.
#TUNE="-tune:v film"
TUNE="-tune:v animation"

echo "ffmpeg -y -i $INPUT -c:v libx264 -pix_fmt $PIXFMT $PRESET $PROFILE $TUNE -crf $CRF $COLORSPACE $OUTPUT"
ffmpeg -y -i $INPUT -c:v libx264 -pix_fmt $PIXFMT $PRESET $PROFILE $TUNE -crf $CRF $COLORSPACE \
$OUTPUT

# Once conversion to .m4v is completed, do another conversion of the H264
# encoded data back to uncompressed Animation codec.

#OUTMOV=`echo $OUTPUT | sed -e s/.m4v/_decoded.mov/g`
#ffmpeg -y -i "$OUTPUT" -vcodec qtrle "$OUTMOV"

exit 0

