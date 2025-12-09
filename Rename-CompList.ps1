function Rename-ComputerList {
<#
.SYNOPSIS
Renames multiple computers using specified current and new names.

.DESCRIPTION
This advanced function takes two string arrays—CurrentNames and NewNames—and renames each computer
accordingly using the Rename-Computer cmdlet. It handles empty entries, trims whitespace, and provides
per-computer error handling to ensure the loop continues even if a rename fails. Each element in CurrentNames
is matched with the corresponding element in NewNames by index.

.PARAMETER CurrentNames
A string array containing the current names of the computers to be renamed.

.PARAMETER NewNames
A string array containing the new names for the computers. Each element corresponds by index to the
CurrentNames array.

.PARAMETER Force
Optional switch to force the rename operation without prompting. Default is $true.

.EXAMPLE
Rename-Computers -CurrentNames @('PC01','PC02') -NewNames @('PC101','PC102')

Renames PC01 to PC101 and PC02 to PC102, forcing the operation and logging results to the console.

.EXAMPLE
Rename-Computers -CurrentNames @('PC01','PC02') -NewNames @('PC101','PC102') -Force $false

Renames the computers but prompts for confirmation for each rename.

.NOTES
- Ensure the account running the function has administrative privileges on all target machines.
- WinRM and network access must allow remote renaming if computers are not local.
- CurrentNames and NewNames arrays must be the same length; otherwise the extra elements are ignored.
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]] $CurrentNames,

        [Parameter(Mandatory=$true)]
        [string[]] $NewNames,

        [Parameter()]
        [switch] $Force = $true
    )

    # Determine the smaller count to prevent index errors
    $Count = [Math]::Min($CurrentNames.Count, $NewNames.Count)

    0..($Count - 1) | ForEach-Object {
        $Current = $CurrentNames[$_].Trim()
        $New     = $NewNames[$_].Trim()

        if (-not [string]::IsNullOrWhiteSpace($Current) -and -not [string]::IsNullOrWhiteSpace($New)) {
            try {
                Rename-Computer -ComputerName $Current -NewName $New -Force:$Force -ErrorAction Stop
                Write-Host "Successfully renamed $Current to $New"
            }
            catch {
                Write-Warning "Failed to rename $Current to $New. Error: $_"
            }
        }
        else {
            Write-Host "Skipping empty entry at index $_"
        }
    }
}