<#
.SYNOPSIS
Get-PnpIssues scans a computer or computers for plug and play device errors and status issues 
(degrated or unknown).
.DESCRIPTION
Get-PnpIssues scans one or more computers for errors and degraded or unknown status. Uses PowerShell
Remoting to get attached plug and play device status and presents data as a formatted table.
.PARAMETER ComputerName
The name of the computer or computers to query.
.EXAMPLE
Get-PnpIssues -ComputerName DESKTOP01

Returns any errors or status problems for connected plug and play device issues on DESKTOP01.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False,
        ValueFromPipeline = $True,
        ValueFromPipelineByPropertyName = $True,
        HelpMessage = "Enter the computer or computers to query.")]
    [String[]]
    $ComputerName = $env:COMPUTERNAME
)

Write-Verbose "Connecting to $ComputerName"
Write-Verbose "Scanning $ComputerName for problems with connected plug and play devices"

Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    Get-PnpDevice -PresentOnly -Status ERROR, DEGRADED, UNKNOWN | Format-Table -AutoSize
}

Write-Verbose "Scan complete"