# Define input and output paths
$logFilePath = "C:\Logs\application.log"  # Path to the XML log file
$outputJsonFile = "C:\Logs\processed_logs.json"  # Path to the JSON output file
$trackingFile = "C:\Logs\last_processed.txt"  # File to store the last processed LogCreationTime

# Function to extract the first <ACVS_T> block using regex
function Get-FirstLogEntry ($filePath) {
    # Read the entire log file content
    $fileContent = Get-Content -Path $filePath -Raw

    # Extract the first <ACVS_T>...</ACVS_T> block using regex
    if ($fileContent -match "<ACVS_T>.*?</ACVS_T>") {
        return "<Root>$Matches[0]</Root>"  # Wrap in a root node and return
    }

    return $null  # Return null if no block is found
}

# Read the last processed LogCreationTime
$lastProcessedTime = if (Test-Path $trackingFile) {
    Get-Content -Path $trackingFile
} else {
    $null
}

# Get the first log entry
$latestEntry = Get-FirstLogEntry -filePath $logFilePath

if ($latestEntry) {
    try {
        # Parse the XML block
        $xmlObject = [xml]$latestEntry

        # Extract the first <ACVS_T> node
        $logNode = $xmlObject.Root.ACVS_T

        # Extract LogCreationTime
        $logCreationTime = $logNode.ACVS_D

        # Check if this entry is new
        if ($logCreationTime -ne $lastProcessedTime) {
            # Convert the XML to a PowerShell object
            $logEntry = @{
                ApplicationVersion = $logNode.ACVS_AV
                LogCreationTime = $logCreationTime
                Class = $logNode.ACVS_C
                Message = $logNode.ACVS_M
                Source = $logNode.ACVS_S
                StackTrace = $logNode.ACVS_ST
                ThreadInfo = $logNode.ACVS_TI
                TraceLevel = $logNode.ACVS_TL
                TraceVersion = $logNode.ACVS_TV
            }

            # Convert the PowerShell object to JSON
            $jsonEntry = $logEntry | ConvertTo-Json -Depth 10 -Compress

            # Write the JSON to the output file (overwrite or append based on preference)
            Set-Content -Path $outputJsonFile -Value $jsonEntry

            # Update the tracking file with the latest LogCreationTime
            Set-Content -Path $trackingFile -Value $logCreationTime

            Write-Host "Processed new log entry with LogCreationTime: $logCreationTime"
        } else {
            Write-Host "No new entry found. Latest LogCreationTime: $logCreationTime"
        }
    } catch {
        Write-Host "Error processing XML block: $_"
    }
} else {
    Write-Host "No <ACVS_T> block found in the file."
}

