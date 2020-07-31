<#
.DESCRIPTION
Set-AutoLogon sets the registry value for automatic logon to either on or off.
.SYNOPSIS
Set-AutoLogon uses PowerShell remoting to set the registry entry for automatic log on for an
arbitrary list of computers. It sets a registry value of either 0 or 1 for "AutoAdminLogon" in
HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinLogon. 
.PARAMETER ComputerName
The name of the computer or computers to query.
.PARAMETER RegVal
The value of "AutoAdminLogon" registry entry, default value is 0 which is off. Accepts 0 or 1.
.EXAMPLE
Set-AutoLogon -ComputerName CONFPC01 -RegVal 0

Disables automatic logon for CONFPC01.
.EXAMPLE
Set-AutoLogon -ComputerName LAPTOP02 -RegVal 1

Enables automatic logon for LAPTOP02.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False,
    ValueFromPipeline = $True,
    HelpMessage = "Enter one or more computer names separated by commas.")]
    [String[]]
    $ComputerName,

    [Parameter(Mandatory = $False, HelpMessage = "Set value of AutoAdminLogon 0 = off 1 = on.")]
    [String]
    [ValidateSet("0", "1")]
    $RegVal = 0
)

Write-Verbose "Connecting to $ComputerName"
Write-Verbose "Setting registry value to $RegVal"

Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty $RegPath "AutoAdminLogon" -Value $using:RegVal -Type String
}

Write-Verbose "Script complete"