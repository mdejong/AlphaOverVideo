# Run from AlphaOverVideo/AlphaOverVideo/CopyFramework subdirectory, note
# that AlphaOverVideo.framework must be copied from the build generation
# dir into this directory first. (it will not be checked into git)

cd ../..

SRC=AlphaOverVideo/CopyFramework/AlphaOverVideo.framework

rm -rf AlienEscape/AlphaOverVideo.framework
cp -R ${SRC} AlienEscape

rm -rf CarSpinAlpha/AlphaOverVideo.framework
cp -R ${SRC} CarSpinAlpha

rm -rf Fireworks/AlphaOverVideo.framework
cp -R ${SRC} Fireworks

rm -rf Bandersnatch/AlphaOverVideo.framework
cp -R ${SRC} Bandersnatch

