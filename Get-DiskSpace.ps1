<# 
.SYNOPSIS
Get-DiskSpace retrieves free space of a logical disk within a specified threshold from one or more computers.
.DESCRIPTION
Get-DiskInfo uses CIM to retrieve the Win32_LogicalDisk instances from one or more computers. It displays each 
disk's drive letter, free space, and total size.
.PARAMETER ComputerName
The computer name, or names, to query. Default: $env:computername.
.PARAMETER MinimumPercentFree
The minimum percent free diskspace. This is the threshold. The default value is 10. Enter a number between
1 and 100.
.PARAMETER DriveType
The drive type to query. See Win_32LogicalDisk documentation for values. 3 is a fixed disk, and is the
default.
.EXAMPLE
Get-DiskSpace -Minimum 20

Find all disks on the local computer with less than 20% free space.
.EXAMPLE
Get-DiskSpace -ComputerName server01 -MinimumPercentFree 25

Find all disks on server01 with less than 25% free space.
#>

[CmdletBinding()]
Param (
    [Parameter(ValueFromPipeline = $True, 
        HelpMessage = "Enter a computer name or names.")]
    [String[]]
    [Alias ("CN")]
    $ComputerName = "$env:COMPUTERNAME",

    [Parameter(HelpMessage = "Select drive type, options are 2 or 3.")]
    [Int]
    [ValidateSet(2, 3)]
    $DriveType = 3,
    
    [Parameter(HelpMessage = "Select a minimum percentage of available storage, default value 10%.")]
    [Int]
    [ValidateRange(0, 100)]
    [Alias("Min")]
    $MinimumPercentFree = 10
)
#Convert minimum percent free
$Threshold = $MinimumPercentFree / 100


Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $ComputerName -Filter "DriveType=$DriveType" |
Where-Object { ($_.FreeSpace / $_.Size) -lt $Threshold } | Select-Object -Property DeviceID, FreeSpace, Size