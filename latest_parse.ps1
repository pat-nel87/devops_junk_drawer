# Define input and output paths
$logFilePath = "C:\Logs\application.log"  # Path to the XML log file
$outputJsonFile = "C:\Logs\processed_logs.json"  # Path to the JSON output file
$trackingFile = "C:\Logs\last_processed.txt"  # File to store the last processed LogCreationTime

# Function to get the first <ACVS_T> block
function Get-LatestLogEntry ($filePath) {
    $xmlBlock = ""  # Initialize variable for the block
    $insideBlock = $false  # Track if inside <ACVS_T>

    Get-Content -Path $filePath | ForEach-Object {
        # Detect the start of the block
        if ($_ -match "<ACVS_T>") {
            $insideBlock = $true
            $xmlBlock = $_  # Start capturing the block
        }
        elseif ($insideBlock) {
            $xmlBlock += "`n" + $_  # Append lines to the block

            # Detect the end of the block
            if ($_ -match "</ACVS_T>") {
                return $xmlBlock  # Return the first complete block
            }
        }
    }

    return $null  # Return null if no block is found
}

# Read the last processed LogCreationTime
$lastProcessedTime = if (Test-Path $trackingFile) {
    Get-Content -Path $trackingFile
} else {
    $null
}

# Get the latest log entry
$latestEntry = Get-LatestLogEntry -filePath $logFilePath

if ($latestEntry) {
    try {
        # Parse the XML block
        $xmlObject = [xml]$latestEntry

        # Extract LogCreationTime
        $logCreationTime = $xmlObject.ACVS_T.ACVS_D

        # Check if this entry is new
        if ($logCreationTime -ne $lastProcessedTime) {
            # Convert the XML to a PowerShell object
            $logEntry = @{
                ApplicationVersion = $xmlObject.ACVS_T.ACVS_AV
                LogCreationTime = $logCreationTime
                Class = $xmlObject.ACVS_T.ACVS_C
                Message = $xmlObject.ACVS_T.ACVS_M
                Source = $xmlObject.ACVS_T.ACVS_S
                StackTrace = $xmlObject.ACVS_T.ACVS_ST
                ThreadInfo = $xmlObject.ACVS_T.ACVS_TI
                TraceLevel = $xmlObject.ACVS_T.ACVS_TL
                TraceVersion = $xmlObject.ACVS_T.ACVS_TV
            }

            # Convert the PowerShell object to JSON
            $jsonEntry = $logEntry | ConvertTo-Json -Depth 10 -Compress

            # Write the JSON to the output file (overwrite or append based on preference)
            Set-Content -Path $outputJsonFile -Value $jsonEntry

            # Update the tracking file with the latest LogCreationTime
            Set-Content -Path $trackingFile -Value $logCreationTime
        } else {
            Write-Host "No new entry found. Latest LogCreationTime: $logCreationTime"
        }
    } catch {
        Write-Host "Error processing XML block: $_"
    }
} else {
    Write-Host "No <ACVS_T> block found in the file."
}
