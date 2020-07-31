<#
.DESCRIPTION
Remove-Package wraps Uninstall-Package in an Invoke-Command scriptblock for quick package removal on multiple 
computers.
.SYNOPSIS
Remove-Package uses Invoke-Command to remove a target package from one or more computers, includes the -Confirm 
option. Requires Nuget and PowerShell Remoting.
.PARAMETER ComputerName
Specifies which computer or computers to remove a target package from.
.PARAMETER Package
Specifies which package to remove from your list of computers.
.EXAMPLE
Remove-Package -ComputerName COMPUTER01, COMPUTER2 -Package "Microsoft Access database engine 2010 (English)"

Removes Access database engine 2010 from COMPUTER01 and COMPUTER02.
.EXAMPLE
Remove-Package -ComputerName (Get-Content -Path C:\servers.txt) -Package "Remote Desktop Connection Manager 2.7"

Removes Remote Desktop Connection Manager 2.7 from servers listed in servers.txt.
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $True, 
        HelpMessage = "Enter the computers you would like to remove a target package from")]
    [String[]]
    [Alias("CN")]
    $ComputerName,

    [Parameter(Mandatory = $True, HelpMessage = "Which package would you like to remove?")]
    [String]
    $Package
)

Write-Verbose "Connecting to $ComputerName"
Write-Verbose "Checking $ComputerName for $Package"

$Test = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    Get-Package -Name $using:Package
}

Write-Verbose "Attempting to Uninstall $Package"

If ($Test -eq "True") {
    Invoke-Command -ComputerName $ComputerName { 
        Uninstall-Package -Name $using:Package -Confirm
    }
}

Else {
    Write-Output "$Package not detected"
}

Write-Verbose "Script finished"