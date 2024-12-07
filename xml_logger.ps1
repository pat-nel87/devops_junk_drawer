# Define input and output paths
$logDirectory = "C:\Logs"  # Directory containing XML log files
$outputJsonFile = "C:\Logs\processed_logs.json"  # Path to consolidated JSON output

# Function to process a single log file
function Process-LogFile ($logFilePath) {
    Get-Content -Path $logFilePath -Wait -Tail 0 | ForEach-Object {
        if ($_ -match "<ACVS_T>") {
            # Initialize the XML block
            $xmlBlock = $_
            while ($xmlBlock -notmatch "</ACVS_T>") {
                $xmlBlock += "`n" + (Read-Host)  # Append subsequent lines
            }

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
        }
    }
}

# Process all log files in the directory
Get-ChildItem -Path $logDirectory -Filter "*.log" | ForEach-Object {
    Process-LogFile $_.FullName
}
