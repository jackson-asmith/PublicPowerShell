<#
.SYNOPSIS
Get-CorruptProfiles tests a computer or group of computers for corrupt profiles.
.DESCRIPTION
Get-CorruptProfiles runs a Test-Path on C:\Users\* -Include *.domain* to check for user 
profiles with a .domain suffix. A .domain, .domain.000, or .domain.000.001 and so on 
typically indicate a corrupt profile on machines whose user profiles are deleted often.
If *.domain* profiles are found Get-CorruptProfiles runs Get-ChildItem on C:\Users\ 
selects Name and PSComputerName properties where Property Name is like .domain
allowing for easy export of data to Csv, JSON, txt, or other filetype of your choosing.
.PARAMETER ComputerName
Type the computer or computers to query. Default value: localhost.
.PARAMETER Domain
Enter the name of your domain--used to check for user.yourdomain. Default value: local domain
.EXAMPLE
Get-CorruptProfiles

Checks local machine for corrupt profiles.
.EXAMPLE
Get-CorruptProfiles -ComputerName desktop01 -Domain Contoso

Checks desktop01 for corrupt profiles.
.EXAMPLE
Get-CorruptProfiles -ComputerName (Get-Content -Path C:\Path\to\computers.txt) -Domain Contoso

Checks a text file computers.txt for corrupt profiles.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $False, HelpMessage = "Enter a computer name or names")]
    [String[]]
    [Alias("CN")]
    $ComputerName = $env:COMPUTERNAME,
    
    [Parameter(Mandatory = $False, HelpMessage = "Enter the name of your domain")]
    [String]
    $Domain = $env:USERDOMAIN
)

Write-Verbose "Scanning $ComputerName for corrupt profiles"

$Test = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    Test-Path -Path "C:\Users\*" -Include *.$using:Domain*
}

If ($Test -eq 'True') {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        Get-ChildItem -Path "C:\Users\"
    } | Select-Object -Property Name, PSComputerName | 
    Where-Object -Property Name -Like *.$Domain*
}

Else {
    Write-Output 'No corrupt profiles detected'
}

Write-Verbose "Script complete"