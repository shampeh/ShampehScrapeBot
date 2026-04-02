param(
    [string]$InputUrl
)

# yt-dlp multi-site profile/channel/playlist downloader
# Supports: YouTube, Twitch, TikTok, Instagram, PornHub, xHamster, ...
# Requires: yt-dlp.exe (in PATH or same folder) + ffmpeg.exe recommended

$IsInteractiveMode = [string]::IsNullOrWhiteSpace($InputUrl)

if ($IsInteractiveMode) {
    Write-Host "Multi-site downloader (YouTube / Twitch / TikTok / Kick / Rumble / X/Twitter / Reddit / Facebook / SoundCloud)" -ForegroundColor Cyan
    Write-Host "Paste channel / user / profile / playlist URL" -ForegroundColor Gray
    Write-Host "Examples:"
    Write-Host "  https://www.youtube.com/@MrBeast" -ForegroundColor DarkCyan
    Write-Host "  https://www.twitch.tv/summit1g" -ForegroundColor DarkCyan
    Write-Host "  https://www.tiktok.com/@shampeh.ai" -ForegroundColor DarkCyan
    Write-Host "  https://kick.com/xqc" -ForegroundColor DarkCyan
    Write-Host "  https://rumble.com/c/channelname" -ForegroundColor DarkCyan
    Write-Host "  https://x.com/username" -ForegroundColor DarkCyan
    Write-Host "  https://www.reddit.com/r/videos/" -ForegroundColor DarkCyan
    Write-Host "  https://www.facebook.com/pagename" -ForegroundColor DarkCyan
    Write-Host "  https://soundcloud.com/artist" -ForegroundColor DarkCyan
    Write-Host "  https://www.youtube.com/playlist?list=PL..." -ForegroundColor DarkCyan
}

function Get-SafeName {
    param([string]$Name)

    $invalid = [IO.Path]::GetInvalidFileNameChars() -join ''
    $re = "[" + [RegEx]::Escape($invalid) + "]"
    $safe = [RegEx]::Replace($Name, $re, '_').Trim(' _-')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'download'
    }

    return $safe
}

function Get-UrlBasedFolderName {
    param([string]$Url)

    if ($Url -match '(?:youtube\.com|youtu\.be)/(?:@|channel/|user/|c/)([^/?#]+)') {
        return $Matches[1]
    }
    elseif ($Url -match 'twitch\.tv/([^/?#]+)') {
        return $Matches[1] + " - Twitch"
    }
    elseif ($Url -match 'tiktok\.com/@([^/?#]+)') {
        return $Matches[1] + " - TikTok"
    }
    elseif ($Url -match 'kick\.com/([^/?#]+)') {
        return $Matches[1] + " - Kick"
    }
    elseif ($Url -match 'rumble\.com/(?:c|user)/([^/?#]+)') {
        return $Matches[1] + " - Rumble"
    }
    elseif ($Url -match '(?:twitter|x)\.com/([^/?#]+)') {
        return $Matches[1] + " - X"
    }
    elseif ($Url -match 'reddit\.com/(?:r|u)/([^/?#]+)') {
        return $Matches[1] + " - Reddit"
    }
    elseif ($Url -match 'facebook\.com/([^/?#]+)') {
        return $Matches[1] + " - Facebook"
    }
    elseif ($Url -match 'soundcloud\.com/([^/?#]+)') {
        return $Matches[1] + " - SoundCloud"
    }

    return $null
}

function Get-FolderNameFromMetadata {
    param(
        [string]$YtDlpPath,
        [string]$Url
    )

    $folderName = $null

    try {
        $jsonRaw = & $YtDlpPath --flat-playlist --dump-single-json "$Url" 2>$null
        if ($jsonRaw) {
            $json = $jsonRaw | ConvertFrom-Json -ErrorAction Stop

            if ($json.uploader -and $json.uploader -notmatch '^YouTube$|^Pornhub$|^xHamster$') {
                $folderName = $json.uploader
            }
            elseif ($json.channel) {
                $folderName = $json.channel
            }
            elseif ($json.uploader_url -match '/(?:@|user/|model/|pornstars/|channels/)([^/]+)') {
                $folderName = $Matches[1]
            }
            elseif ($json.playlist_title) {
                $folderName = $json.playlist_title
            }
            elseif ($json.title -and $json._type -eq 'playlist') {
                $folderName = $json.title
            }
            elseif ($json.username) {
                $folderName = $json.username
            }
        }
    }
    catch {
        return $null
    }

    return $folderName
}

function Get-LatestKnownEntry {
    param(
        [string]$YtDlpPath,
        [string]$Url
    )

    try {
        # Keep this intentionally tiny: only ask for the first playlist item.
        $latestJsonRaw = & $YtDlpPath --flat-playlist --playlist-items 1 --dump-single-json "$Url" 2>$null
        if (-not $latestJsonRaw) {
            return $null
        }

        $latestJson = $latestJsonRaw | ConvertFrom-Json -ErrorAction Stop

        if ($latestJson.entries -and $latestJson.entries.Count -gt 0) {
            return $latestJson.entries[0]
        }

        if ($latestJson.id) {
            return $latestJson
        }
    }
    catch {
        return $null
    }

    return $null
}

function Test-EntryAlreadyPresent {
    param(
        [string]$DownloadDir,
        [string]$ArchiveFile,
        [string]$EntryId
    )

    if ([string]::IsNullOrWhiteSpace($EntryId)) {
        return $false
    }

    $escapedId = [regex]::Escape($EntryId)

    if (Test-Path $DownloadDir) {
        $matchingFile = Get-ChildItem -Path $DownloadDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "\[$escapedId\]" } |
            Select-Object -First 1

        if ($matchingFile) {
            Write-Output "Entry already exists locally: $($matchingFile.Name)"
            return $true
        }
    }

    if (Test-Path $ArchiveFile) {
        $archiveMatch = Select-String -Path $ArchiveFile -Pattern "(^|\s)$escapedId$" -SimpleMatch:$false -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($archiveMatch) {
            Write-Output "Entry already exists in the download archive: $EntryId"
            return $true
        }
    }

    return $false
}

# Make sure script runs relative to its own folder
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$ytDlpPath = Join-Path $scriptDir "yt-dlp.exe"

if (-not (Test-Path $ytDlpPath)) {
    Write-Host "`nyt-dlp.exe not found in script folder: $scriptDir" -ForegroundColor Red
    exit 1
}

if ($IsInteractiveMode) {
    Write-Host "`nChecking yt-dlp for updates..." -ForegroundColor Cyan
    & $ytDlpPath -U
}

# Support both app mode and manual mode
if ($IsInteractiveMode) {
    Write-Host "`nURL: " -NoNewline -ForegroundColor Yellow
    $InputUrl = Read-Host
}

$inputUrl = $InputUrl.Trim()

if ([string]::IsNullOrWhiteSpace($inputUrl)) {
    Write-Host "No URL entered. Exiting." -ForegroundColor Red
    exit 1
}

$knownSitePatterns = @(
    'youtube\.com',
    'youtu\.be',
    'twitch\.tv',
    'tiktok\.com',
    'kick\.com',
    'rumble\.com',
    'twitter\.com',
    'x\.com',
    'reddit\.com',
    'facebook\.com',
    'fb\.watch',
    'soundcloud\.com'
)

$isKnownSite = $false
foreach ($pattern in $knownSitePatterns) {
    if ($inputUrl -match $pattern) {
        $isKnownSite = $true
        break
    }
}

if (-not $isKnownSite) {
    Write-Host "Unsupported URL. Not in known website list. No files or folders will be created." -ForegroundColor Red
    exit 2
}

# Use a cheap URL-based folder guess first so the newest-item precheck can happen
# before any heavier metadata scan.
$folderName = Get-UrlBasedFolderName -Url $inputUrl
if ([string]::IsNullOrWhiteSpace($folderName)) {
    $folderName = "MultiSite_Download_" + (Get-Date -Format "yyyyMMdd_HHmm")
}

$safeName = Get-SafeName -Name $folderName
$rootDir = $scriptDir
$downloadDir = Join-Path $rootDir $safeName
$archiveDir = Join-Path $rootDir 'zzArchive'
$archiveFile = Join-Path $archiveDir ("archive-" + $safeName + ".txt")

if (-not (Test-Path $archiveDir)) {
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
}

if (-not (Test-Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
}

Write-Host "`nDownload folder:" -ForegroundColor Green
Write-Host "  $downloadDir" -ForegroundColor White
Write-Host "Archive file:" -ForegroundColor Green
Write-Host "  $archiveFile" -ForegroundColor White

# Fast path:
# 1) Ask yt-dlp only for the first remote item.
# 2) If that exact item already exists locally/archive, skip the entire scrape.
# 3) If it does not exist, then proceed to the full scan/download.
$latestEntry = Get-LatestKnownEntry -YtDlpPath $ytDlpPath -Url $inputUrl
if ($latestEntry -and $latestEntry.id) {
    Write-Output "Latest remote item detected from first page: $($latestEntry.id)"

    if (Test-EntryAlreadyPresent -DownloadDir $downloadDir -ArchiveFile $archiveFile -EntryId $latestEntry.id) {
        Write-Output "Skipping scrape because the newest item is already present. Assuming older items were already handled."
        exit 10
    }

    Write-Output "Newest item was not found locally. Running full scan/download now."
}
else {
    Write-Output "Could not determine the newest remote item from the first page. Falling back to normal scrape."
}

# Optional nicer naming after we already know a full scan is needed.
$metadataFolderName = Get-FolderNameFromMetadata -YtDlpPath $ytDlpPath -Url $inputUrl
if (-not [string]::IsNullOrWhiteSpace($metadataFolderName)) {
    $metadataSafeName = Get-SafeName -Name $metadataFolderName

    if ($metadataSafeName -ne $safeName) {
        $metadataDownloadDir = Join-Path $rootDir $metadataSafeName
        $metadataArchiveFile = Join-Path $archiveDir ("archive-" + $metadataSafeName + ".txt")

        # Prefer an already-existing metadata-based folder/archive if it exists from older runs.
        if ((Test-Path $metadataDownloadDir) -or (Test-Path $metadataArchiveFile)) {
            $safeName = $metadataSafeName
            $downloadDir = $metadataDownloadDir
            $archiveFile = $metadataArchiveFile

            if (-not (Test-Path $downloadDir)) {
                New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
            }

            Write-Output "Switching to existing metadata-based folder/archive:"
            Write-Output "  $downloadDir"
            Write-Output "  $archiveFile"
        }
    }
}

Write-Output "Starting yt-dlp ..."

& $ytDlpPath `
    --no-abort-on-error `
    --ignore-errors `
    --no-continue `
    --restrict-filenames `
    --windows-filenames `
    --no-overwrites `
    --download-archive "$archiveFile" `
    --format "bestvideo+bestaudio/best" `
    --merge-output-format "mkv" `
    --embed-subs --embed-metadata --embed-thumbnail --embed-chapters `
    --sub-langs "all,-live_chat" `
    --convert-subs "srt" `
    -o "$downloadDir/%(upload_date)s - %(title)s [%(id)s].%(ext)s" `
    --ppa "Thumbnails:ffmpeg_i: -c:v copy -c:a copy" `
    "$inputUrl"

$exitCode = $LASTEXITCODE

Write-Output "Finished!"
Write-Output "Saved to: $downloadDir"

if (Test-Path $archiveFile) {
    Write-Output "Archive file created/updated (prevents re-downloading next run)"
}

# Only pause when manually run, not when launched by Electron
if ($IsInteractiveMode) {
    Write-Host "`nPress any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

exit $exitCode
