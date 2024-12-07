# Define file paths
$inputFilePath = "C:\Logs\application.log"  # Original log file
$outputFilePath = "C:\Logs\reformatted_application.log"  # Reformatted log file
$trackingFilePath = "C:\Logs\last_processed.txt"  # Tracks last processed entry

# Function to reformat new entries
function Append-NewEntries ($inputFilePath, $outputFilePath, $trackingFilePath) {
    # Read the entire original log file
    $fileContent = Get-Content -Path $inputFilePath -Raw

    # Use regex to match each <ACVS_T>...</ACVS_T> block
    $matches = [regex]::Matches($fileContent, "<ACVS_T>(.|\n)*?</ACVS_T>")

    # If no matches are found, exit
    if ($matches.Count -eq 0) {
        Write-Host "No <ACVS_T> blocks found in the input file."
        return
    }

    # Read the last processed entry
    $lastProcessedEntry = if (Test-Path $trackingFilePath) {
        Get-Content -Path $trackingFilePath -Raw
    } else {
        ""
    }

    $newEntriesFound = $false

    # Process each block
    foreach ($match in $matches) {
        # Reformat the block
        $currentEntry = $match.Value -replace '\s+', ' '  # Single-line format

        # Skip if the block matches the last processed one
        if ($currentEntry -eq $lastProcessedEntry) {
            break
        }

        # Append the new entry to the reformatted file
        Add-Content -Path $outputFilePath -Value $currentEntry

        # Mark this entry as new
        $newEntriesFound = $true

        # Update the tracking file with the latest entry
        Set-Content -Path $trackingFilePath -Value $currentEntry
    }

    if ($newEntriesFound) {
        Write-Host "New entries appended to $outputFilePath."
    } else {
        Write-Host "No new entries found."
    }
}

# Call the function
Append-NewEntries -inputFilePath $inputFilePath -outputFilePath $outputFilePath -trackingFilePath $trackingFilePath
