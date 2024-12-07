# Define input and output paths
$logDirectory = "C:\Logs"  # Directory containing XML log files
$outputJsonFile = "C:\Logs\processed_logs.json"  # Path to the consolidated JSON output file

# Function to process a single log file
function Process-LogFile ($logFilePath) {
    $xmlBlock = ""  # Variable to hold the current XML block
    $insideBlock = $false  # Flag to track if we are inside a <ACVS_T> block

    Get-Content -Path $logFilePath -Wait | ForEach-Object {
        # Check for the start of a new block
        if ($_ -match "<ACVS_T>") {
            $insideBlock = $true
            $xmlBlock = $_  # Start a new XML block
        }
        elseif ($insideBlock) {
            $xmlBlock += "`n" + $_  # Append lines to the current block

            # Check for the end of the block
            if ($_ -match "</ACVS_T>") {
                $insideBlock = $false  # Close the block

                try {
                    # Parse the XML block
                    $xmlObject = [xml]$xmlBlock

                    # Convert the XML to a PowerShell object
                    $logEntry = @{
                        ApplicationVersion = $xmlObject.ACVS_T.ACVS_AV
                        LogCreationTime = $xmlObject.ACVS_T.ACVS_D
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

                    # Write the JSON entry to the output file
                    Add-Content -Path $outputJsonFile -Value $jsonEntry
                } catch {
                    Write-Host "Error processing XML block: $_"
                }

                # Clear the XML block for the next entry
                $xmlBlock = ""
            }
        }
    }
}

# Process all log files in the directory
Get-ChildItem -Path $logDirectory -Filter "*.log" | ForEach-Object {
    Process-LogFile $_.FullName
}
