# Define file paths
$inputFilePath = "C:\Logs\application.log"  # Original XML log file
$outputFilePath = "C:\Logs\reformatted_application.log"  # Reformatted log file
$envVarName = "LAST_XML_WRITE_TIME"  # Environment variable to track the last write time

# Reformat-XML function (unchanged)
function Reformat-XML ($inputFilePath, $outputFilePath) {
    # Read the entire XML file content
    $fileContent = Get-Content -Path $inputFilePath -Raw

    # Use regex to match each <ACVS_T>...</ACVS_T> block
    $matches = [regex]::Matches($fileContent, "<ACVS_T>(.|\n)*?</ACVS_T>")

    # If no matches are found, inform the user and exit
    if ($matches.Count -eq 0) {
        Write-Host "No <ACVS_T> blocks found in the input file."
        return
    }

    # Process each match and write it on a single line to the output file
    foreach ($match in $matches) {
        # Remove newlines and extra whitespace within the block
        $singleLineBlock = $match.Value -replace '\s+', ' '

        # Append the reformatted block to the output file
        Add-Content -Path $outputFilePath -Value $singleLineBlock
    }

    Write-Host "Reformatted XML written to $outputFilePath."
}

# Check last write time and run Reformat-XML if needed
function Check-And-Reformat-XML ($inputFilePath, $outputFilePath, $envVarName) {
    # Get the current last write time of the XML log file
    $currentWriteTime = (Get-Item $inputFilePath).LastWriteTime

    # Get the last recorded write time from the environment variable
    $lastWriteTime = if ($env:$envVarName) {
        [datetime]$env:$envVarName
    } else {
        # If the env var doesn't exist, assume the file has never been processed
        [datetime]"1900-01-01"
    }

    # Compare the write times
    if ($currentWriteTime -gt $lastWriteTime) {
        Write-Host "File has been updated. Running Reformat-XML..."

        # Run the reformatting function
        Reformat-XML -inputFilePath $inputFilePath -outputFilePath $outputFilePath

        # Update the environment variable with the new last write time
        $env:$envVarName = $currentWriteTime

        Write-Host "Environment variable $envVarName updated to $currentWriteTime."
    } else {
        Write-Host "No updates detected. Skipping reformatting."
    }
}

# Call the function
Check-And-Reformat-XML -inputFilePath $inputFilePath -outputFilePath $outputFilePath -envVarName $envVarName
