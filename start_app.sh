#!/bin/bash

# Create our array
array=()
array+=('pwsh')
array+=('/app/nvenc_hevc_conversion.ps1')
array+=('-Path')
array+=('/media')
array+=('-TempPath')
array+=('/encoding')
array+=('-VideoBitRate')
array+=("$VIDEO_BIT_RATE")
array+=('-Filter')
array+=("$FILTER")

# Now lets check if we have some flags
if [ "$TEN_BIT_ENCODING" == 1 ]; then array+=('-10Bit'); fi
if [ "$DELETE_SOURCE_FILE" == 1 ]; then array+=('-DeleteSource'); fi
# if [ "$CONCURRENT_ENCODES" -gt 1 ]; then array+=('-ConcurrentEncodes'); array+=("$CONCURRENT_ENCODES"); fi
if [ "$SONARR_RENAME" == 1 ]; then array+=('-SonarrRename'); fi
if [ "$RADARR_RENAME" == 1 ]; then array+=('-RadarrRename'); fi

echo "${array[@]}"
 "${array[@]}"
