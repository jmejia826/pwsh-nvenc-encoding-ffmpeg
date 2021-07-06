<#
    .REQUIREMENTS
        PowerShell v7.1.0 or higher

    .DESCRIPTION
        This script do the following (more to come down the road):
            *   Takes a path or file and checks to see if the item is in the HEVC codec. If not:
            *       execute ffmpeg to encode it into HEVC.  New filename will have "x265" appended to it.  Original will NOT be overwritten
            
    .NOTES
        Version:        0.0.16
        Author:         Juan Mejia
        Creation Date:  2020-11-30

    .CHANGELOG
        0.0.16
            Added mp4a to the check list for AAC audio -- {"Format": "AAC LC", "Format/Info" : "Advanced Audio Codec Low Complexity", "CodecID": "mp4a-40-2"}

        0.0.15
            Removed check and use of FFBP
            Added custom progress bar
            Added check if CUDA error occurs and aborts (will change to CPU encoding if detected)
            Added check for subtitle error 94213 (id: tx3g / MOV_TEXT) and convert to srt

        0.0.14
            updated code to encode only audio if video is already 265/hevc and/or encode teh whole thing if its not in the format we want in the first run
            removed -AudioOnly due to the updated code
            fixed subtitles being stripped (Credit to Hector)
            fixed shows/movies not being detected when attempting to refresh/rename
            
        0.0.13
            added -SonarrRename and -RadarrRename.  It will trigger a rename via said app after th encode happens

        0.0.12
            added -TempPath which will be used to copy the file to be encoded to and encode to that same path. once encoded, it will be copied/movied back ot the original.  Default
                    will be $env:HOME (c:\users\$username for windows, /home/$username for linux)
            added path status, meaning, you will see how much space was saved from $path as well as the total 

        0.0.11
            Added -Filter 

        0.0.10
            Check if filename contains non ascii characters. if yes, do not use ffpb
            Added total space saved (creation of settings.json)

        0.0.9
            Added -AudioOnly which will process even if the file is already HEVC|(X|H)265 and convert the audio to AAC format (Will skip if audio is AAC)
            Run ffpb (ffmpeg progress bar) if detected
            Added padding to have the 'Checking' filename be right aligned
            Added detection of older hevc (hvc1)

        0.0.8
            Added -DeleteSource to delete the source file post encoding

        0.0.7
            Removed skipping of videos under 720p and introduced -LowResolution which will take anything under 720p and encode it at 75% the bitrate of the source. Should
                help with older shows

        0.0.6
            If audio is already AAC then copy it instead of re-encoding it
            Added check to see if video is below 720p

        0.0.5  
            Default audio to AAC VBR 5 (highest quality)
            Added option to convert to AC3

        0.0.4:
            Detect if video is 10bit to encode in HEVC 10bit
            Detect if interlace and add flag [thanks Hector]

        0.0.3:
            Added the strip subtitle flag
            Added multithreading support
        
        0.0.2:
            Updated default VideoBitrate to 3Mbps
            Added audio conversion to AC3
        
        0.0.1:
            initial release
#>

# Parameters
[CmdletBinding()]
Param(
    [string]$Path,                                                                  # Either a file or folder
    [switch]$StripSubtitles = $false,                                               # Resulting file would not have any subtitles
    [switch]$AudioToAC3 = $false,                                                   # Will convert the audio to AC3, default is AAC
    [switch]$CopyAudioTracks = $false,                                              # Will not transcode audio tracks but will copy them
    [switch]$LowResolution = $true,                                                 # If enabled, if the video is less than 720p, the $VideoBitRate will automatically be 25% of the video's bitrate
    [string]$Container = "mkv",                                                     # Container type (Default: MKV)
    [string]$VideoBitRate = "3M",                                                   # Video bitrate (Default: 3Mbps)
    [string]$MaximumVideoBitRate = "15M",                                           # Maximum video bitrate (Default: 15Mbps)
    [switch]$10Bit = $false,                                                        # Sets wether or not 10bit should be done
    [switch]$DeleteSource = $false,                                                  # Deletes the original file once it has been encoded
    [int]$ConcurrentEncodes = 1,                                                    # Number of concurrent encodes (Default: 1)
    [string]$Filter = "*",                                                          # Filter for search
    [string]$TempPath = $Env:HOME,                                                  # Temporary folder to copy the files to
    [switch]$RadarrRename = $false,                                                 # If enabled, it will trigger Radarr to rename (if there is a match)
    [switch]$SonarrRename = $false,                                                 # If enabled, it will trigger Sonarr to rename (if there is a match)
    [switch]$CPU = $false                                                           # If enabled, it will use CPU instead of the Nvidia GPU
)

# Function to calculate input (3M or 250K) into bytes
function Get-BytesFromInput {
    # Define our multiplier
    $multiplier = 1                 # Just incase if its specified in bytes already

    # Check the letter after the number
    $Letter = $VideoBitRate.Substring($VideoBitRate.Length - 1).ToLower()
    $inputSize = $VideoBitRate -replace ".{1}$"

    # If the size is higher than Gigabytes, then we should conver tto array
    if ($Letter -eq "k") { $multiplier = 1024 }
    if ($Letter -eq "m") { $multiplier = 1024 * 1024 }
    if ($Letter -eq "g") { $multiplier = 1024 * 1024 }

    # Calculate bitrate
    return ([double]([int]$inputSize * [double]$multiplier))
}

# function to calcualte human readable sizes from bytes
function GetHumanReadableSize($Size) {
    # Define our letters
    $unit = ('B', 'KB', 'MB', 'GB', 'TB', 'PB')

    # Define where we are in the size
    $position = 0

    # Go through the size until it is less than 1024
    while ($Size -gt 1024) {
        $Size = $Size / 1024;
        $position++
    }

    # Return the size as #.##
    $humanFormat = "{0:#.##}{1}" -f ($Size, $unit[$position])
    return $humanFormat
}

# Define our ANSI variables
$ANSI_Reset         = "`e[0m"
$ANSI_Red           = "`e[91m"
$ANSI_Green         = "`e[32m"
$ANSI_Yellow        = "`e[33m"
$ANSI_Blue          = "`e[34m"
$ANSI_Magenta       = "`e[35m"
$ANSI_Cyan          = "`e[36m"
$ANSI_Gray          = "`e[37m"
$ANSI_DarkGray      = "`e[90m"
$ANSI_ReplaceLine   = "`e[1F`e[100J"

# Abort if no path is specified
if (!$Path) { Write-Host "Error.  -Path not specified" -ForegroundColor Yellow -BackgroundColor Red; return }

# Start logging
#Start-Transcript -Path ('nvenc.{0:yyyy-MM-dd HH-mm-ss}.log' -f (Get-Date))
Write-Output "Total input path(s): $($Path.count)"
Write-Output $Path

# Note the temorary space
Write-Output "Temporary Folder: $($ANSI_Red)$TempPath$($ANSI_Reset)"

# Write the process id
Write-Output "Process ID: $($ANSI_Red)$PID$($ANSI_Reset)"

# Define our json to hold the stats
$settingsFileName = Join-Path $PSScriptRoot "settings.json"

$totalSavedSpace = 0
if (Test-Path -Path $settingsFileName -PathType Leaf) {
    # Read the json as a hashtable
    $jsonSettings = Get-Content -Path $settingsFileName | ConvertFrom-Json -Depth 100 -AsHashTable

    # Grab the total
    $totalSavedSpace = $jsonSettings.totalSpaceSaved
}

# Get human readable
$humanReadableTotal = "0B"
if ($totalSavedSpace -gt 0) { $humanReadableTotal = GetHumanReadableSize -Size $totalSavedSpace }

# Display some stats
Write-Output "`r`n"
Write-Output "Total Space Saved: $($ANSI_Green)$humanReadableTotal$($ANSI_Reset) "
Write-Output "`r`n"
Write-Output "$($ANSI_DarkGray)Scanning for files...$($ANSI_Reset)"
Write-Output "`r`n"

# Object that will hold ALL the filenames for conversion.  This would be pre mediainfo testing to see which are valid video files
$AllFiles = New-Object System.Collections.ArrayList

# Go through the different path(s) and add it to the array
ForEach($tmpPath in $Path) {
    # Test to see if the path is a folder or a file
    If (Test-Path "$tmpPath" -PathType Container) {
        # Get all the files and add to the list of files
        $AllFiles = Get-ChildItem -Path $tmpPath -Recurse -Filter $Filter
    } ElseIf (Test-Path "$tmpPath" -PathType Leaf) {
        $AllFiles.Add($tmpPath) > $null
    }
}

# Sorting the list
$AllFiles = $AllFiles | Sort-Object

# Make sure we have the defaults
if ($ConcurrentEncodes -eq 0) { $ConcurrentEncodes = 1 }

# Calculate the bytes from the input
$bytesVideoBitRate = Get-BytesFromInput

Write-Output "Phase 1 Scan has detected $($AllFiles.Count) files"
Write-Output "`r`n" 
Write-Output "$($ANSI_DarkGray)Default values:$($ANSI_Reset)"
Write-Output "$($ANSI_DarkGray)Container: $($ANSI_Yellow)$Container$($ANSI_Reset)"
Write-Output "$($ANSI_DarkGray)VideoBitRate: $($ANSI_Yellow)$VideoBitRate$($ANSI_Reset)"
Write-Output "$($ANSI_DarkGray)MaximumVideoBitRate: $($ANSI_Yellow)$MaximumVideoBitRate$($ANSI_Reset)"
Write-Output "$($ANSI_DarkGray)ConcurrentEncodes: $($ANSI_Yellow)$ConcurrentEncodes$($ANSI_Reset)"
Write-Output "$($ANSI_DarkGray)CopyAudioTracks: $($ANSI_Yellow)$CopyAudioTracks$($ANSI_Reset)"
Write-Output "$($ANSI_DarkGray)LowResolution: $($ANSI_Yellow)$LowResolution$($ANSI_Reset)"
Write-Output "$($ANSI_DarkGray)VideoBitRate in Bytes: $($ANSI_Yellow)$bytesVideoBitRate$($ANSI_Reset)"
Write-Output "$($ANSI_DarkGray)10bit: $($ANSI_Yellow)$10Bit$($ANSI_Reset)"

Write-Output "`r`n"

# Define that we want to use the custom function inside the foreach
$funcDef = $function:GetHumanReadableSize.ToString()

# If Sonarr and/or Radarr is enabled, get the list
$SonarrShows = $null
If ($SonarrRename) {
    # Make sure we have app config
    $app = $jsonSettings.apps.sonarr
    if ($app.host -and $app.apikey) {
        Write-Output "$($ANSI_DarkGray)Sonarr Rename enabled.  Acquiring the list of shows, please wait$($ANSI_Reset)"
        
        # Build the header
        $Header = @{}
        $Header.Add("X-Api-Key", $app.apikey)
        $SonarrShows = Invoke-RestMethod -Uri "$($app.host)/api/v3/series/" -Method GET -Headers $HEADER
        Write-Output "$($ANSI_DarkGray)Acquired $($ANSI_Red)$($SonarrShows.Count) $($ANSI_DarkGray)shows$($ANSI_Reset)"
        Write-Output " "
    }
}

$RadarrMovies = $null
If ($RadarrRename) {
    # Make sure we have app config
    $app = $jsonSettings.apps.radarr
    if ($app.host -and $app.apikey) {
        Write-Output "$($ANSI_DarkGray)Radarr Rename enabled.  Acquiring the list of movies, please wait$($ANSI_Reset)"
        

        # Build the header
        $Header = @{}
        $Header.Add("X-Api-Key", $app.apikey)
        $RadarrMovies = Invoke-RestMethod -Uri "$($app.host)/api/v3/movie/" -Method GET -Headers $HEADER 
        Write-Output "$($ANSI_DarkGray)Acquired $($ANSI_Red)$($RadarrMovies.Count) $($ANSI_DarkGray)movies$($ANSI_Reset)"
        Write-Output " "
    }
}

$Global:CUDA_ERROR = $false

# Go through all the files to see which are video files
$AllFiles | ForEach-Object -ThrottleLimit $ConcurrentEncodes -Parallel {
    
    if ($Global:CUDA_ERROR -eq $true) { continue }

    # Give the object a variable
    $File = $_

    # Define the function inside this thread...
    $function:GetHumanReadableSize = $using:funcDef
    
    # If the object is NOT a directory (it gets added from the recurse)
    if (Test-Path $File -PathType Container) { Write-Output "`r`n$($using:ANSI_DarkGray)Skipping: Directory object: $File$($using:ANSI_Reset)"; Continue }

    # A few variables
    $SkipFile = $true                               # Skip the file for any number of reason
    $AudioToAC3 = $false                            # If true, audio will be converted to ac3, else it is copied
    $10BitVideo = $false                            # If true, the video will retain the 10bit video depth
    $Interlace = $false                             # If true, the video is interlaced and need to be deinterlaced
    $IsAudioAAC = $false                            # If true, audio is already AAC

    # Pad the 'file' for output
    #$ScreenWidth = $using:Host.UI.RawUI.BufferSize.Width
   # $FileNamePadded = $File.Name.PadLeft(($ScreenWidth - 9), " ")

    # Show which file we are on
    $currentPosition = ($($using:AllFiles).IndexOf($File)) + 1
    $totalFiles = $using:AllFiles.Count
    $sessionPercentage = [double]([double]$currentPosition / [double]$totalFiles) * 100 
    $humanReadableOldFileSize = GetHumanReadableSize -Size (Get-ChildItem -Path $File).Length
    $statusString = "$($using:ANSI_Gray)$(Get-Date) [$PID]`t$($using:ANSI_Reset)Checking: [$($using:ANSI_Red)$($currentPosition.ToString().PadLeft(($totalFiles.ToString().Length),'0'))$($using:ANSI_Red)/"
    $statusString = $statusString + "$($using:ANSI_Red)$totalFiles$($using:ANSI_Reset)] $($using:ANSI_Green)$(("{0:n2}%" -f ($sessionPercentage)))`t$($File.Name)$($using:ANSI_Reset) ("
    $statusString = $statusString + "$($using:ANSI_Red)$humanReadableOldFileSize$($using:ANSI_Reset))"
    Write-Output $statusString
    
    # Execute mediainfo to see if this is a video file
    $mediaInfo = mediainfo -f $File --Output=JSON | ConvertFrom-Json -AsHashTable
    
    # Our flags
    $encodeVideo = $true
    $encodeAudio = $false

    # Lets make sure we have a video track
    $tracks = $mediaInfo.media.track
    $ProposedBitRate = 0
    $OverallBitRate = 0
    $TotalFrameCount = 0;
    $isFileValidForEncoding = $false
    $SubtitleToSRT = $false
    $skipMap0 = $false
    ForEach($track in $tracks) { 
        # Make sure we have a duration 
        If ([double]$track.Duration -gt 0) { $isFileValidForEncoding = $true } 

        # Check the track type to perform some checks
        if ($track."@type" -eq "Video") { 
            # Get the framecount
            $TotalFrameCount = [double]$track.FrameCount
            
            # CHeck if already HEVC
            if ($track.CodecID.ToLower() -like "*hevc*" -or $track.CodecID -like "*265*" -or $track.CodecID.ToLower() -like '*hvc1*') {
                $encodeVideo = $false
            } else {
                # Check if 10bit
                if ($track.BitDepth -eq 10) { $10BitVideo = $true }

                # Check if interlaced
                if ($track.ScanType -eq "Interlaced") { $Interlace = $true }

                # Check if resolution is below 720p and mark as skip if true
                if (([int]$track.Width -lt 1280 -and [int]$track.Height -lt 720) -or ($OverallBitRate -lt $using:bytesVideoBitRate) -and $using:LowResolution) { 
                    # Grab the current bitrate
                    $ProposedBitRate = ([double]$track.BitRate * 0.75) / 1000   # This is the bitrate at 75% and then / 1000 to get it into kbps

                    # if its 0, use the overall bitrate
                    if ($ProposedBitRate -eq 0) { $ProposedBitRate = ($OverallBitRate * 0.75) / 1000 }

                    # if proposed is less than 50, lets use default of 350K
                    if ($ProposedBitRate -lt 350) { $ProposedBitRate = 350 }
                 }
            }
        } elseif ($track."@type" -eq "Audio") {
            if ($using:AudioToAC3 -and ($track.CodecID -ne "A_AC3" -or $track.CodecID -ne "A_EAC3")) {
                $AudioToAC3 = $true
                $encodeAudio = $true
            } elseif ($track.CodecID -notlike "*AAC*" -and $track.CodecID -notlike '*mp4a*') {
                $encodeAudio = $true
            }
        } elseif ($track."@type" -eq "General") {
            $OverallBitRate = [double]$track.OverallBitRate
        } elseif ($track."@type" -eq "Text") {
            # See if the "CodecID" is tx3g
            if ($track.CodecID -eq "tx3g") { 
                $SubtitleToSRT = $true
                $statusString = "$($using:ANSI_Gray)$(Get-Date) [$PID]`t$($using:ANSI_Magenta)Potential Subtitle 94213. $($using:ANSI_Gray)Attempting to convert subtitle "
                $statusString = $statusString + "$($using:ANSI_Yellow)tx3g $($using:ANSI_Gray)to $($using:ANSI_Yellow)srt$($using:ANSI_Reset)"
                Write-Output $statusString
            }
        } elseif ($track."@type" -eq "Menu" -and $using:Container -eq "mkv") {
            # skip the -map 0 flag
            $skipMap0 = $true  
        }
    }

    # Set our skip file
    $SkipFile = if (-not $encodeVideo -and -not $encodeAudio) { $true } else { $false }
    
    # Skip file if we are NOT to encode because is not a valid file
    If (-not $isFileValidForEncoding) { $SkipFile = $true }

    # If we are not skipping, proceed with detections
    If (!$SkipFile) {
        # Get just the filename
        $FileNameNoExtension = (Get-ChildItem $File).BaseName
        if ($FileNameNoExtension.Length -eq 0) {
            # Get just the filename
            $FileNameNoExtension = $File.Name

            # split by .
            $array = $FileNameNoExtension -Split '\.'
            
            # Join all the components except last
            $t = New-Object System.Collections.ArrayList
            for ($i=0; $i -lt $array.count - 1 ; $i++) { $t.Add($array[$i]) > $null }

            # if ($array.Count -gt 1) { $FileNameNoExtension = $array -Join '.' } else { $FileNameNoExtension = $array[0] }
            $FileNameNoExtension = $t -Join "."
        }

        # Copy the file to the temp space as 'src'
        $fz = GetHumanReadableSize -Size (Get-ChildItem -Path $File).Length
        $tempSource = Join-Path $using:TempPath $File.Name
        $statusString = "$($using:ANSI_Gray)$(Get-Date) [$PID]`t$($using:ANSI_Reset)Copying: `t$($using:ANSI_Green)$File $($ANSI_Reset)($($using:ANSI_Red)$fz$($using:ANSI_Reset)) to "
        $statusString = $statusString + "$($using:ANSI_Magenta)$using:TempPath$($using:ANSI_Reset)`r`n"
        Write-Output $statusString

        if ($IsWindows) { copy $File $tempSource } else { rsync "$File" "$TempSource" }
        # Copy-Item -Path $File -Destination $TempSource

        $FileNameEncoded = "$FileNameNoExtension.x265.$($using:Container)"
        $NewFileName = Join-Path $using:TempPath $FileNameEncoded
        
        # build flag options
        $videoProfile = 'main'
        $encodingBitRate = if ($using:LowResolution -and $ProposedBitRate -gt 0) { "$($ProposedBitRate)K" } else { $using:VideoBitRate }
        $subtitleCopyFlag = If (-not $SubtitleToSRT) { '-c:s copy' } else { '-c:s srt' }
        $pixFormat = ''
        if ($10BitVideo -or $using:10Bit) { $videoProfile = 'main10'; $pixFormat = '-pix_fmt p010le'}
        
        $AudioFlag = if (-not $encodeAudio) { '-c:a copy'} else { '-c:a aac' }
        $VideoFlag = "-c:v hevc_nvenc -b:v $encodingBitRate -maxrate:v $using:MaximumVideoBitRate -bufsize:v 12M -preset slow -profile:v $videoProfile -rc"
        $VideoFlag += " vbr_hq -rc-lookahead:v 32 -spatial_aq:v 1 -aq-strength:v 8"

        # If we are using CPU, a few things need to change
        If ($using:CPU) { $VideoFlag = "-c:v libx265 -x265-params pass=2" } else { $VideoFlag = "-c:v hevc_nvenc" }
        $VideoFlag = "$VideoFlag -b:v $encodingBitRate -maxrate:v $using:MaximumVideoBitRate -bufsize:v 12M -preset slow -profile:v $videoProfile -rc"
        $VideoFlag += " vbr_hq -rc-lookahead:v 32 -spatial_aq:v 1 -aq-strength:v 8"

        # If we are not encoding video, use the copy
        if (-not $encodeVideo) { $VideoFlag = "-c:v copy" }

        if ($AudioToAC3 -and !$using:CopyAudioTracks) { $AudioFlag = '-c:a eac3 -ab:a 640k' }
        #if ($using:AudioOnly) { $VideoFlag = '-c:v copy' }
        if ($using:CopyAudioTracks) { $AudioFlag = '-c:a copy' }
        if ($using:StripSubtitles ) { $SubtitleFlag = '-sn'; $subtitleCopyFlag = '' }
        if ($Interlace) { $deinterlace = '-vf yadif=deint=interlaced' }

        # Check to see if we require the metadata stuff
        $map0 = if ($skipMap0) { '' } else { '-map 0' }

        # Build the command
        $command = "-i `"$tempSource`" $map0 -max_muxing_queue_size 9999 $deinterlace $SubtitleFlag $VideoFlag $AudioFlag $pixFormat $subtitleCopyFlag `"$NewFileName`"" 

        # See if we have the ffmpeg progress bar
        $ffmpeg = "ffmpeg"
        
        # Execute
        #Write-Host "Executing: " -NoNewLine -ForegroundColor DarkGray; Write-host "$ffmpeg" -NoNewLine -ForegroundColor Blue; Write-Host " $command" -ForegroundColor Yellow
        # $process = Start-Process -FilePath $ffmpeg -ArgumentList $command -Wait -NoNewWindow -PassThru
        # $ffmpeg_output_file = "/tmp/ffmpeg_nvenc_output-$(Get-Random).log"
        # $process = Start-Process -FilePath $ffmpeg -ArgumentList $command -NoNewWindow -RedirectStandardError $ffmpeg_output_file -PassThru

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo.Filename = $ffmpeg
        $process.StartInfo.Arguments = "$command"
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.CreateNoWindow = $true
        $process.Start() | Out-Null
        
        # Wait 1 second 
        # Start-Sleep 1

        # Format the display filename
        $displayEncodingFilename = $FileNameEncoded
        if ($displayEncodingFilename.Length -gt 90) { 
            $LeftPart = $displayEncodingFilename.Substring(0,67)
            $rightPart = $displayEncodingFilename.Substring($displayEncodingFilename.Length - 20, 20)
            $displayEncodingFilename = "$LeftPart...$rightPart"
        }

        # Loop until ffmpeg exists
        $didEncode = $False
        
        # While (Get-Process -id $process.Id -ErrorAction SilentlyContinue) {
        While (-not $process.HasExited) {
            
            # Get the last row
            if ($process.StandardError.Peek()) {
                $line = $process.StandardError.ReadLineAsync().Result
                if ($line) {
                    $lastRow = $line.Trim()

                    # See if we have a CUDA error
                    if ($lastRow -like '*CUDA_ERROR_*') {
                        Write-Host ""
                        Write-Host "*********************************************************" -BackgroundColor Red -ForegroundColor Yellow
                        Write-Host "**** ERR ENCODING — CUDA ERROR DETECTED ****" -BackgroundColor Red -ForegroundColor Yellow
                        Write-Host "*********************************************************" -BackgroundColor Red -ForegroundColor Yellow
                        Write-Host ""

                        # Remove the temp files
                        Remove-Item -Path $NewFileName -Force -ErrorAction SilentlyContinue
                        Remove-Item -Path $tempSource -Force -ErrorAction SilentlyContinue
        
                        # Set our flag that this is a must end
                        [Environment]::Exit(1)
                    } elseif ($lastRow -like "*Subtitle codec 94213*") {
                        Write-Output "$($using:ANSI_Red)Subtitle 94213 error detected$($using:ANSI_Reset)"
                    }
                    
                    # Make sure we have the required item
                    if ($lastRow.StartsWith("frame=")) {
                        
                        $didEncode = $true
                        # Split by q= since we care about the first part
                        $firstSplit = $lastRow -Split " q="
                        $dataArray = $firstSplit[0] -split "="
                        $currentFrame = [double](($dataArray[1] -Replace "fps", "") -Replace " ", "")
                        $fps = [double]($dataArray[2] -Replace " ", "")
                        if ($fps -eq 0) { $fps = 1 }

                        # Calculate the percentage
                        $percentage = (($currentFrame / $TotalFrameCount) * 100)
                        # $progresBarFilled = "█" * ($percentage)
                        # $progressBarEmpty = " " * (100 - $percentage)
                        # $progressBar = "$progresBarFilled$ProgressBarEmpty"

                        # Calculate the time left
                        $timeLeftSeconds = (($TotalFrameCount - $currentFrame) / $fps)
                        $timeSpan = New-TimeSpan -Seconds $timeLeftSeconds
                        $timeLeft = $timeSpan.ToString("hh'h 'mm'm 'ss's'")

                        # # Display it
                        #e[1F`e[100J 1f - moves up, 100j clears the line
                        $statusString = "$($using:ANSI_ReplaceLine)$($using:ANSI_Gray)Encoding: $($using:ANSI_Magenta)$displayEncodingFilename$($using:ANSI_Reset) :"
                        $statusString = $statusString + "$($using:ANSI_Yellow) $(("{0:n2}%" -f ($percentage))) $($using:ANSI_Cyan)$currentFrame/$totalFrameCount "
                        $statusString = $statusString + "$($using:ANSI_Gray)($timeLeft - $($fps)fps)$($using:ANSI_Reset)"
                        Write-Output $statusString

                        # New method -- $progresBarFille
                        # Write-Host "Encoding: $FileNameEncoded.  $currentFrame/$TotalFrameCount | $fps fps.  $percentage.  $timeLeftSeconds"
                        # Write-Progress -Activity "Encoding: $FileNameEncoded" -Status "$currentFrame/$TotalFrameCount | $fps fps" -PercentComplete $percentage -SecondsRemaining $timeLeftSeconds
                    }
                }
            }
        }

        # If we did an encode, lets update with the 100% line
        If ($didEncode) {
            # Calculate Progress
            $percentage = ($TotalFrameCount / $TotalFrameCount) * 100
            
            # Display it
            $statusString = "$($using:ANSI_ReplaceLine)$($using:ANSI_Gray)Encoding: $($using:ANSI_Magenta)$displayEncodingFilename$($using:ANSI_Reset) :"
            $statusString = $statusString + "$($using:ANSI_Yellow) $(("{0:n2}%" -f ($percentage))) $($using:ANSI_Cyan)$currentFrame/$totalFrameCount "
            $statusString = $statusString + "$($using:ANSI_Gray)($timeLeft - $($fps)fps)$($using:ANSI_Reset)"
            Write-Output $statusString                            
        }

        # Delete the new file if it is reported a fialed
        if (($process.ExitCode -ne '0')) { 
            Write-Output "FAILED: $($using:ANSI_Red)$NewFileName$($using:ANSI_Reset)"
            Remove-Item -Path $NewFileName -Force -ErrorAction SilentlyContinue
        } else {
            # Calculate how much space was saved
            $savedSpace = (Get-ChildItem -Path $File).Length - (Get-ChildItem -Path $NewFileName).Length
            $percentage = "{0:#.#}%" -f (100 - ((Get-ChildItem -Path $NewFileName).Length / (Get-ChildItem -Path $File).Length) * 100)

            # Get the total saved space
            $totalSavedSpace = 0
            $sessionSavedSpace = 0
            $jsonSettings = @{}
            if (Test-Path -Path $using:settingsFileName -PathType Leaf) {
                # Read the json as a hashtable
                $jsonSettings = Get-Content -Path $using:settingsFileName | ConvertFrom-Json -Depth 100 -AsHashTable

                # Grab the total
                $totalSavedSpace = $jsonSettings.totalSpaceSaved
                $sessionSavedSpace = $jsonSettings.session
                $sessionSavedByPath = $jsonSettings.path
                if (-not $sessionSavedSpace) { $sessionSavedSpace = @{} }
                if (-not $sessionSavedByPath) { $sessionSavedByPath = @{} }
            }

            # Increase the total
            $totalSavedSpace += $savedSpace
            $sessionSavedSpace["pid_$PID"] += $savedSpace
            $sessionSavedByPath["$using:Path"] += $savedSpace

            # Save the total back to the json and then save the json
            $jsonSettings['totalSpaceSaved'] = $totalSavedSpace
            $jsonSettings['session'] = $sessionSavedSpace
            $jsonSettings['path'] = $sessionSavedByPath
            ($jsonSettings | ConvertTo-Json -Depth 100) | Out-File -Path $using:settingsFileName

            # Get human readable
            $humanReadableTotal = GetHumanReadableSize -Size $totalSavedSpace
            $humanReadableSession = GetHumanReadableSize -Size $sessionSavedSpace["pid_$PID"]
            $humanReadableFile = GetHumanReadableSize -Size $savedSpace
            $humanReadableOldFileSize = GetHumanReadableSize -Size (Get-ChildItem -Path $File).Length
            $humanReadableNewFileSize = GetHumanReadableSize -Size (Get-ChildItem -Path $NewFileName).Length
            
            # Display some stats
            # Write-Host "`r`n"
            $statusString = "Space Saved (Overall): $($using:ANSI_Green)$humanReadableTotal $($using:ANSI_Reset)"
            $statusString = $statusString + "| Saved Space (This Session): $($using:ANSI_Green)$humanReadableSession $($using:ANSI_Reset)"
            $statusString = $statusString + "| Saved Space (This File): $($using:ANSI_Green)$humanReadableFile $($using:ANSI_Reset)"
            $statusString = $statusString + "($($using:ANSI_Red)$percentage$($using:ANSI_Reset)) "
            $statusString = $statusString + "Old File Size: $($using:ANSI_Yellow)$humanReadableOldFileSize $($using:ANSI_Reset)| New File Size: $($using:ANSI_Yellow)"
            $statusString = $statusString + "$humanReadableNewFileSize$($using:ANSI_Reset)"
            Write-Output $statusString
            
            # Write-Host "`r`n"
        }

        # Copy the encoded file to the destination
        if ($didEncode) {
            $tempSource = Join-Path $using:TempPath $File.Name
            $statusString = "$($using:ANSI_Gray)$(Get-Date) [$PID]`t$($using:ANSI_Reset)Copying: `t$($using:ANSI_Green)$NewFileName $($using:ANSI_Reset)($($using:ANSI_Red)$humanReadableNewFileSize$($using:ANSI_Reset)) to "
            $statusString = $statusString + "$($using:ANSI_Magenta)$($File.DirectoryName)$($using:ANSI_Reset)"
            Write-Output $statusString

            if ($IsWindows) { copy $NewFileName $File.DirectoryName } else { rsync "$NewFileName" "$($File.DirectoryName)" }
            # Copy-Item -Path $NewFileName -Destination $File.DirectoryName

            # Calculate checksum
            $TempHash = (Get-FileHash -Path $NewFileName).Hash
            $FinalHash = (Get-FileHash -Path (Join-Path $File.DirectoryName $FileNameEncoded)).Hash
            
            # Delete the source file
            if ($using:DeleteSource -and (Test-Path "$NewFileName" -PathType Leaf) -and ((Get-Item -Path $NewFileName).Length -gt 5242880) -and ($process.ExitCode -eq '0') -and ($TempHash -eq $FinalHash)) { 
                Write-Output "Deleting: $($using:ANSI_Magenta)$File$($using:ANSI_Reset)"
                Remove-Item -Path $File -Force
            }
        }

        # Remove our temp
        Remove-Item -Path $NewFileName -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempSource -Force -ErrorAction SilentlyContinue
        
        # Do not continue if we did not encode
        if (-not $didEncode) { Continue }

        # If the rename is enable
        If ($using:SonarrRename -or $using:RadarrRename) {
            # Get the name of the folder
            $NameOfMedia = $null
            $DestinationFolder = $File.DirectoryName
            While(-not $NameOfMedia) {
                $LastPath = Split-Path $DestinationFolder -Leaf
                $DestinationFolder = Split-Path $DestinationFolder
                If ($LastPath.ToLower() -notlike '*season*' -and $LastPath.ToLower() -notlike '*special*') { $NameOfMedia = $LastPath }
                If (-not $DestinationFolder) { break }
            }

            # Only continue if we have a valid name
            If ($NameOfMedia) {
                # Get the app name
                $appName = If ($using:SonarrRename) { "Sonarr" } else { "Radarr" }
                $searchData = If ($using:SonarrRename) { $using:SonarrShows } else { $using:RadarrMovies }
                Write-Output "$($using:ANSI_Red)$appName$($using:ANSI_DarkGray):`tLocating id for $($using:ANSI_Magenta)$NameOfMedia$($using:ANSI_Reset)"
            
                # The object for the id
                $arrMedia = @{}
                ForEach($entry in $searchData) {
                    $entryFolder = Split-Path $entry.path -Leaf
                    If ($entryFolder.ToLower() -eq $NameOfMedia.ToLower()) { $arrMedia = $entry; break }
                }

                # If we have the media dictionary, continue
                if ($arrMedia.id.Length -gt 0) {
                    #   Notify the id
                    $statusString = "$($using:ANSI_Red)$appName$($using:ANSI_DarkGray):`tid for $($using:ANSI_Magenta)$NameOfMedia$($using:ANSI_DarkGray) is $($using:ANSI_Green)$($arrMedia.id)$($using:ANSI_Reset)"
                    Write-Output $statusString
                    # Build the header
                    $app = $jsonSettings.apps."$($appName.ToLower())"
                    $Header = @{}
                    $Header.Add("X-Api-Key", $app.apikey)

                    # Build the command
                    Write-Output "$($using:ANSI_Red)$appName$($using:ANSI_DarkGray):`tRefreshing $($using:ANSI_Magenta)$($arrMedia.title)$($using:ANSI_Reset)"
                    $command = @{}
                    
                    # depending on the type is either a value or array
                    if ($using:SonarrRename) {
                        $command['name'] = "RefreshSeries"
                        $command['seriesId'] = $arrMedia.id
                    } elseif ($using:RadarrRename) {
                        $command['name'] = "RefreshMovie"
                        $command['movieIds'] = @($arrMedia.id)
                    }
                    
                    # Send the command
                    $Response = Invoke-RestMethod -Uri "$($app.host)/api/v3/command" -Method POST -Headers $Header -Body ($command | ConvertTo-Json -Depth 10)

                    # If it went through, let's wait 60s for the 'scan' to finish. hopefully that's enough time for it to detect the changes
                    If ($Response.name -eq $command.name) {
                        # Set a counter in order for us to abort after a certain time
                        $RenameCounter = 0

                        # go in a loop
                        $dots = ""
                        Write-Output "$($using:ANSI_ReplaceLine)$($using:ANSI_Red)$appName$($using:ANSI_DarkGray):`tWaiting to allow the refresh to complete $dots$($using:ANSI_Reset)"
                        $IsFileThere = $False
                        $arrMediaFile = @{}
                        While($RenameCounter -lt 60) {
                            $dots = $dots + "."
                            Write-Output "$($using:ANSI_ReplaceLine)$($using:ANSI_Red)$appName$($using:ANSI_DarkGray):`tWaiting to allow the refresh to complete $dots$($using:ANSI_Reset)"
                        
                            Start-Sleep -Seconds 1     # 1 second1 between checks

                            # Get the files that are eligible for rename
                            $v3 = If($using:SonarrRename) { "" } else { "/v3" }
                            $RenameFilesList = Invoke-RestMethod -Uri "$($app.host)/api$v3/rename?$(If($using:SonarrRename){`"series`"} else {`"movie`"})Id=$($arrMedia.id)" -Headers $Header
                            
                            # Make sure that the new filename is part of the rename file list
                            ForEach($RenameFile in $RenameFilesList) {
                                if ((Split-Path $RenameFile.existingPath -Leaf).ToLower() -eq "$($(Split-Path $NewFileName -Leaf).ToLower())") { 
                                    $IsFileThere = $True
                                    $RenameCounter = 200
                                    $arrMediaFile = $RenameFile
                                }
                            }

                            # increase the counter
                            $RenameCounter = $RenameCounter + 1
                        }
                        
                        # If the file is there, lets rename
                        If ($IsFileThere) {
                            $dots = ""
                            Write-Output "`r`n$($using:ANSI_ReplaceLine)$($using:ANSI_Red)$appName$($using:ANSI_DarkGray):`tThe new filename has been detected.  Proceeding to rename $dots$($using:ANSI_Reset)"
                        
                            # Build the command
                            $command = @{}
                            $command['name'] = 'RenameFiles'
                            if ($using:SonarrRename) {
                                $command['seriesId'] = $arrMedia.id
                                $command['files'] = @($arrMediaFile.episodeFileId)
                            } elseif ($using:RadarrRename) {
                                $command['movieId'] = $arrMedia.id
                                $command['files'] = @($arrMediaFile.movieFileId)
                            }

                            # Send the command
                            For($i = 0; $i -lt 3; $i++) {
                                $dots = $dots + "."
                                Write-Output "$($using:ANSI_ReplaceLine)$($using:ANSI_Red)$appName$($using:ANSI_DarkGray):`tThe new filename has been detected.  Proceeding to rename $dots$($using:ANSI_Reset)"
                                $Response = Invoke-RestMethod -Uri "$($app.host)/api/v3/command" -Method POST -Headers $Header -Body ($command | ConvertTo-Json -Depth 10)
                                Start-Sleep -Seconds 1
                            }
                        }
                    }             
                }
            }
        }

        # Send a blank
        Write-Output ""
    }
}

# Remove the pid_$PID from session
$jsonSettings = Get-Content -Path $settingsFileName | ConvertFrom-Json -Depth 100 -AsHashTable

# Grab the SESSION section
$sessionSavedSpace = $jsonSettings.session
$sessionPID = $sessionSavedSpace["pid_$PID"]

# Remove the pid
$sessionSavedSpace.Remove("pid_$PID")

# Save it
($jsonSettings | ConvertTo-Json -Depth 100) | Out-File -Path $settingsFileName

# Get some numbers
$totalSavedSpace = $jsonSettings.totalSpaceSaved
$sessionSavedSpace = $jsonSettings.session
$sessionSavedByPath = $jsonSettings.path

# Convert to human readable
$HumanReadableSessionSaved = GetHumanReadableSize -Size $sessionPID
$HumanReadableTotalSaved = GetHumanReadableSize -Size $totalSavedSpace

# Do a final display of status
Write-Output "`r`n`r`nSpace Saved"
Write-Output "`tSession: $($ANSI_Magenta)$HumanReadableSessionSaved$($ANSI_Reset)"
ForEach($key in $sessionSavedByPath.Keys) {
    $TempHumanSpace = GetHumanReadableSize -Size $sessionSavedByPath["$key"]
    # Write-Host "`tPath [" -NoNewLine; Write-Host $key -ForegroundColor Red -NoNewLine; Write-Host "]: " -NoNewLine; Write-Host $TempHumanSpace -ForegroundColor Magenta
    Write-Output "`tPath [$($ANSI_Red)$key$($ANSI_Reset)]: $($ANSI_Magenta)$TempHumanSpace$($ANSI_Reset)"
}
# Write-Host "`tOverall Total: " -NoNewLine; Write-Host $HumanReadableTotalSaved -ForegroundColor Magenta
Write-Output "`tOverAll Total: $($ANSI_Magenta)$HumanReadableTotalSaved$($ANSI_Reset)"
Write-Output "`r`n`r`n"

# Stop Logging
#Stop-Transcr
