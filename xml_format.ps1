# Define input and output file paths
$inputFilePath = "C:\Logs\application.log"  # Path to the original XML log file
$outputFilePath = "C:\Logs\reformatted_application.log"  # Path for the reformatted log file

# Function to reformat the XML
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
        # Each match represents one <ACVS_T>...</ACVS_T> block, including all child elements

        # Remove newlines and extra whitespace within the block
        $singleLineBlock = $match.Value -replace '\s+', ' '

        # Append the reformatted block to the output file
        Add-Content -Path $outputFilePath -Value $singleLineBlock
    }

    Write-Host "Reformatted XML written to $outputFilePath."
}

# Call the function
Reformat-XML -inputFilePath $inputFilePath -outputFilePath $outputFilePath
