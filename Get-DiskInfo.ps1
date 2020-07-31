<# 
.SYNOPSIS
Get-DiskInfo retrieves logical disk information from one or more computers.
.DESCRIPTION
Get-DiskInfo uses CIM to retrieve the Win32_LogicalDisk instances from one or more computers. It displays each
disk's drive letter, free space, total size, percentage of free space, and the computers hostname.
.PARAMETER ComputerName
The computer name, or names, to query. Default: localhost.
.PARAMETER DriveType
The drive type to query. See Win_32LogicalDisk documentation for values. 3 is a fixed disk, and is the default.
.EXAMPLE
Get-DiskInfo -ComputerName SERVER01 -DriveType 3
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $True, HelpMessage = "Enter a computer name to query")]
    [String[]]
    $ComputerName,

    [Parameter(Mandatory = $True, HelpMessage = "Select a drive type")]
    [ValidateSet(2, 3)]
    [int]$DriveType = 3
)

Write-Verbose "Connecting to $ComputerName"
Write-Verbose "Looking for the drive type $DriveType"

Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=$using:DriveType"
} | 
Sort-Object -Property DeviceID, PSComputerName | 
Select-Object -Property PSComputerName, DeviceID, 
    @{label = 'FreeSpace (MB)'; expression = { $_.FreeSpace / 1MB -as [int] } }, 
    @{label = 'Size (GB)'; expression = { $_.Size / 1GB -as [int] } }, 
    @{label = '%Free'; expression = { $_.FreeSpace / $_.Size * 100 -as [int] } }
    
Write-Verbose "Finished running Command"