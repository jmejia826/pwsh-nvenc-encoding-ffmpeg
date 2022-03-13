### Version: 0.0.17 (2022-03-13)
- Fixed the chapter issue (initial fix was to remove the -map 0) - Thanks @hbadillo

### Version: 0.0.16
- Added mp4a to the check list for AAC audio -- {"Format": "AAC LC", "Format/Info" : "Advanced Audio Codec Low Complexity", "CodecID": "mp4a-40-2"}

### Version: 0.0.15
- Removed check and use of FFBP
- Added custom progress bar
- Added check if CUDA error occurs and aborts (will change to CPU encoding if detected)
- Added check for subtitle error 94213 (id: tx3g / MOV_TEXT) and convert to srt

### Version: 0.0.14
- Updated code to encode only audio if video is already 265/hevc and/or encode teh whole thing if its not in the format we want in the first run
- Removed -AudioOnly due to the updated code
- fFixed subtitles being stripped (Credit to Hector)
- Fixed shows/movies not being detected when attempting to refresh/rename
            
### Version: 0.0.13
- Added -SonarrRename and -RadarrRename.  It will trigger a rename via said app after th encode happens

### Version: 0.0.12
- added -TempPath which will be used to copy the file to be encoded to and encode to that same path. once encoded, it will be copied/movied back ot the original.  Default will be $env:HOME (c:\users\$username for windows, /home/$username for linux)
- added path status, meaning, you will see how much space was saved from $path as well as the total 

### Version: 0.0.11
- Added -Filter 

### Version: 0.0.10
- Check if filename contains non ascii characters. if yes, do not use ffpb
- Added total space saved (creation of settings.json)

### Version: 0.0.9
- Added -AudioOnly which will process even if the file is already HEVC|(X|H)265 and convert the audio to AAC format (Will skip if audio is AAC)
- Run ffpb (ffmpeg progress bar) if detected
- Added padding to have the 'Checking' filename be right aligned
- Added detection of older hevc (hvc1)

### Version: 0.0.8
- Added -DeleteSource to delete the source file post encoding

### Version: 0.0.7
- Removed skipping of videos under 720p and introduced -LowResolution which will take anything under 720p and encode it at 75% the bitrate of the source. Should help with older shows

### Version: 0.0.6
- If audio is already AAC then copy it instead of re-encoding it
- Added check to see if video is below 720p

### Version: 0.0.5  
- Default audio to AAC VBR 5 (highest quality)
- Added option to convert to AC3

### Version: 0.0.4:
- Detect if video is 10bit to encode in HEVC 10bit
- Detect if interlace and add flag [thanks Hector]

### Version: 0.0.3:
- Added the strip subtitle flag
- Added multithreading support

### Version: 0.0.2:
- Updated default VideoBitrate to 3Mbps
- Added audio conversion to AC3

### Version: 0.0.1:
- Initial release
