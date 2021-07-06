# pwsh-nvenc-encoding-ffmpeg

This script will use FFMPEG to take a file and encode it into x265. I've been working on this since I had issues with TDARR and the new version (version 2) introduced some stuff that just wasn't my cup of tea.

A few assumptions:
- Powershell v7 is installed (at least 7.1)
- Nvidia graphics card is installed and its drivers (can confirm by typing nvidia-smi into command promp / terminal)

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

I will update this file as needed (the readme) 

 
