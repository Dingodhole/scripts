param(
    [string]$source = "",
    [string]$destination = "",
    [string]$sourceFormat = "avr",  # Default source format is .avr
    [string]$exportFormat = "mp4",  # Default export format is .mp4
    [string]$groupBy = "",          # Regex pattern to group files, if empty no grouping is applied
    [switch]$merge,                 # Add -merge to merge the files in each group
    [switch]$help
)

function Show-Help {
    Write-Host "Usage: .\Convert-MediaFiles.ps1 -source <source_directory> -destination <destination_directory> [-sourceFormat <format>] [-exportFormat <format>] [-groupBy <regex_pattern>] [-merge]"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -source        The directory containing the source files."
    Write-Host "  -destination   The directory where the output files will be saved."
    Write-Host "  -sourceFormat  The file format of the source files (default: 'avr')."
    Write-Host "  -exportFormat  The output file format after conversion (default: 'mp4')."
    Write-Host "  -groupBy       Optional regex pattern to group files (default: no grouping)."
    Write-Host "  -merge         Merge the converted files in each group."
    Write-Host "  -help          Display this help message."
    Write-Host ""
    Write-Host "Example:"
    Write-Host "  .\Convert-MediaFiles.ps1 -source 'C:\path\to\source' -destination 'C:\path\to\destination' -sourceFormat 'avr' -exportFormat 'mp4' -groupBy 'ch\\d+' -merge"
    exit
}

# Show help if -help is provided or if required params are missing
if ($help -or !$source -or !$destination) {
    Show-Help
}

# Ensure the source folder exists
if (-not (Test-Path -Path $source)) {
    Write-Host "Error: Source folder does not exist: $source"
    exit 1
}

# Check if FFmpeg is installed
$ffmpegPath = (Get-Command ffmpeg -ErrorAction SilentlyContinue)
if (-not $ffmpegPath) {
    Write-Host "Error: FFmpeg is not installed or not available in the system's PATH."
    Write-Host "Please install FFmpeg using the following command:"
    Write-Host "`winget install 'FFmpeg (Essentials Build)'`"
    exit 1
}

# Ensure the destination folder exists, if not, create it
if (-not (Test-Path -Path $destination)) {
    Write-Host "Destination folder does not exist. Creating $destination"
    New-Item -Path $destination -ItemType Directory
}

# Get all source files of the specified format
$files = Get-ChildItem -Path $source -Filter "*.$sourceFormat"

# Check if any source files are found
if ($files.Count -eq 0) {
    Write-Host "Error: No .$sourceFormat files found in the source folder: $source"
    exit 1
}

# Function to group files by regex or process all files together
function Group-Files {
    param(
        [Object[]]$files,
        [string]$groupBy
    )
    
    # If groupBy is not provided, treat all files as one group
    if (-not $groupBy) {
        return $files | Group-Object { "all_files" }  # No grouping, all files in one group
    }
    else {
        # Use the regex pattern to group files
        try {
            return $files | Group-Object { if ($_.Name -match $groupBy) { $matches[0] } else { "ungrouped" } }
        }
        catch {
            Write-Host "Error: Invalid regex pattern in -groupBy parameter."
            exit 1
        }
    }
}

# Group files based on the specified regex pattern or no grouping if none is provided
$groupedFiles = Group-Files -files $files -groupBy $groupBy

foreach ($group in $groupedFiles) {
    $groupName = $group.Name
    $outputFolder = "$destination\$groupName"
    
    # Create a folder for this group in the destination folder
    if (-not (Test-Path -Path $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory
    }

    # Convert source files to the specified export format
    $convertedFiles = @()
    foreach ($file in $group.Group) {
        $outputFile = "$outputFolder\$($file.BaseName).$exportFormat"
        $convertedFiles += $outputFile
        ffmpeg -i $file.FullName -c:v libx264 -c:a aac $outputFile
    }

    # If -merge is specified, merge the files in each group
    if ($merge -and $group.Group.Count -gt 1) {
        # Create a temporary file list for ffmpeg
        $fileListPath = "$destination\$groupName-files.txt"
        $convertedFiles | ForEach-Object { "file '$($_)'" } | Set-Content $fileListPath

        # Merge the converted files
        $mergedFile = "$destination\$groupName-merged.$exportFormat"
        ffmpeg -f concat -safe 0 -i $fileListPath -c copy $mergedFile

        # Remove the temporary file list
        Remove-Item $fileListPath
    }
}

Write-Host "Conversion complete! Merging was performed:" ($merge.IsPresent)
