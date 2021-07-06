# pwsh-nvenc-encoding-ffmpeg

This script will use FFMPEG to take a file and encode it into x265. I've been working on this since I had issues with TDARR and the new version (version 2) introduced some stuff that just wasn't my cup of tea.

The script will scan the specified path for all files, it will execute mediainfo on each file to see if the file is 265 or not, what the audio tracks are etc. If the conditions match (not 265 or not AAC), then the file a candidate for encoding.  The file is copied to the temp path and encoded.  The file name is modified to include <original_filename>.x265.<extension> and it is then copied back to the original source.  If delete source is enabled, it will delete teh source and proceed with Sonarr / Radarr rename (if enabled).
  
There are a few defaults, be sure to check the PowerShell's parameter's list ot see what those are.  Example:
  - Default bitrate is 3Mbps
  - Default extension is MKV
  - 10bit is OFF by default
  - Sonarr/Radarr rename is OFF by default
  
  

A few assumptions:
- Powershell v7 is installed (at least 7.1)
- Nvidia graphics card is installed and its drivers (can confirm by typing nvidia-smi into command prompt / terminal)

# How to run it
Open command prompt or terminal and type in 

pwsh nvenc_hevc_conversion.ps1 <paramteters>
  
ex: pwsh nvenc_hevc_conversion.ps1 -10bit -RadarrRename -TempPath /media/nvme-500g-01/tmp -Path /media/multimedia/movies/
  
This will convert everything in /media/multimedia/movies/ to 10bit mkv (mkv is default but you can specify another format as long as ffmpeg will accept it). The -RadarrRename flag, will trigger Radarr to scan the library for that movie and rename it to your naming format based on Radarr.  -TempPath is the temporary location that it will copy the file to for encoding
 
# Other Examples from my actual server  
pwsh nvenc_hevc_conversion.ps1 -10bit -SonarrRename -TempPath /media/nvme-500g-01/tmp -Path /media/multimedia/anime/ -Filter W*
  
pwsh nvenc_hevc_conversion.ps1 -10bit -SonarrRename -TempPath /media/nvme-500g-01/tmp -Path /media/multimedia/television/ -Filter How*
  
# Is a TempPath required?
No but if one is not specified, it will use the user's home directory.  This is to prevent constant read/write if the source is on a remote path (ex: unRAID server or a NAS)

# CPU Encoding?
I have added the flag for CPU encoding but have not coded the FFMPEG parameters to use CPU.  This will be done in upcoming releases as well as falling back to CPU if there is an issue with the NVENC 
  
I will update this file as needed (the readme) 

 
