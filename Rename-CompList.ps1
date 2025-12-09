<#
.SYNOPSIS
Renames multiple computers using a mapping defined in a CSV file.

.DESCRIPTION
This script reads a CSV file containing CurrentName and NewName columns and renames each computer
accordingly using the Rename-Computer cmdlet. It handles empty entries, trims whitespace, and 
provides per-computer error handling to ensure the loop continues even if a rename fails. 
The script is designed to be safe for batch operations and logs successes and failures for review.

.PARAMETER CsvPath
The path to the CSV file containing the computer rename mapping. The CSV must have headers:
CurrentName and NewName.

.PARAMETER Force
Optional switch to force the rename without prompting. Default is $true.

.EXAMPLE
.\Rename-ComputersFromCsv.ps1 -CsvPath "C:\Scripts\rename-map.csv"

Renames all computers listed in rename-map.csv, forcing the operation and logging results to the console.

.EXAMPLE
.\Rename-ComputersFromCsv.ps1 -CsvPath "C:\Scripts\rename-map.csv" -Force $false

Runs the rename process but prompts for confirmation for each computer rename.

.NOTES
- Ensure the account running the script has administrative privileges on all target machines.
- WinRM and network access must allow remote renaming if computers are not local.
- The CSV must be properly formatted; extra columns or duplicate headers may cause unexpected behavior.

#>

$RenameList = Import-Csv .\rename-map.csv

$CurrentNames = $csv[0].CurrentName
$NewNames     = $csv[0].NewName

# Loop over indices using ForEach-Object
0..($CurrentNames.Count - 1) | ForEach-Object {
    $Current = $currentNames[$_].Trim()
    $New     = $newNames[$_].Trim()

    if (-not [string]::IsNullOrWhiteSpace($Current) -and -not [string]::IsNullOrWhiteSpace($New)) {
        try {
            Rename-Computer -ComputerName $Current -NewName $new -Force -ErrorAction Stop
            Write-Host "Successfully renamed $Current to $New"
        }
        catch {
            Write-Warning "Failed to rename $Current to $New. Error: $_"
        }
    } else {
        Write-Host "Skipping empty entry at index $_"
    }
}