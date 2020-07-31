<#
.SYNOPSIS
Get-PrintDrivers scans a target computer or computers for a specified printer driver and lists them on the 
console.
.DESCRIPTION
Get-PrintDrivers scans a computer or group of computers for a specified printer driver by full or partial
driver name. Uses Invoke-Command to query target machines and requires WinRM and WSMAN configured. This sript
uses a wildcard search for $Driver which makes finding drivers easier but may result in multiple drivers
listed.
.PARAMETER ComputerName
The computer name or names to query.
.PARAMETER Driver
The driver you're scanning for.
.EXAMPLE
Get-PrintDrivers -ComputerName PRINTSERVER01 -Driver Ricoh

Returns all Ricoh drivers installed on computer PRINTSERVER01
.EXAMPLE
Get-PrintDrivers -ComputerName (Get-Content -Path C:\Computers.txt) -Driver HP LaserJet 500 Color M551 PLC6

Checks a list of computers for HP LaserJet 500 Color M551 PLC6 driver.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $True, HelpMessage = "Enter a computer name or names to scan.")]
    [String[]]
    $ComputerName,

    [Parameter(Mandatory = $True, HelpMessage = "Enter a name or partial name of the printer driver.")]
    [String]
    $Driver
)

Write-Verbose "Checking $ComputerName for $Driver"

Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    Get-PrinterDriver -Name "*$using:Driver*"
} | Select-Object PSComputerName, Name

Write-Verbose "Script complete"