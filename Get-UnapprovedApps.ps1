<# 
.SYNOPSIS
Get-UnapprovedApps retrieves a list of unapproved applications from one or more computers.
.DESCRIPTION
Get-UnapprovedApps tests whether one or more computers have a specified application installed in AppData\Local.
.PARAMETER ComputerName
The computer name, or names, to query. Default: localhost. Supports alias -CN.
.PARAMETER Site
The site you're searching.
.PARAMETER User
Specifies which user account to check. Default: current user.
.PARAMETER App
Specifies a single unapproved app to check for.
.EXAMPLE
Get-UnapprovedApps -App Slack

Checks local machine and current user profile for Slack.
.EXAMPLE
Get-UnapprovedApps -ComputerName (Get-Content -Path "C:\path\to\computers.txt") -App Chromium

Checks a list of computers for Chromium installed on your profile.
.EXAMPLE
Get-UnapprovedApps -ComputerName DESKTOP01 -User DJones -App VMware

Checks DESKTOP01 user DJones's profile for VMware.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $False, 
        Position = 1,
        ValueFromPipeline = $True,
        HelpMessage = "Enter a computer name or names to scan.")]
    [ValidateNotNullOrEmpty()]
    [Alias("CN")]
    [String[]]
    $ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $False, 
        HelpMessage = "Which OU are you scanning?")]
    [String]
    $Site,

    [Parameter(Mandatory = $False,
        Position = 2,
        HelpMessage = "Which userprofile would you like to check?")]
    [ValidateNotNullOrEmpty()]
    [String]
    $User = $env:USERNAME,
    
    [Parameter(Mandatory = $True,
        Position = 3,
        HelpMessage = "Enter an Application name.")]
    [ValidateNotNullOrEmpty()]
    [String]
    $App
)

Write-Verbose "Checking $ComputerName for $App"

$Test = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    Test-Path -Path "C:\Users\$using:User\AppData\Local\*" -Include *$using:App*
}

If ($Test -eq 'True') {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        Get-ChildItem -Path "C:\Users\$using:User\AppData\Local\" | 
        Select-Object -Property Name, PSComputerName | Where-Object -Property Name -Like *$using:App* 
    }
}

else {
    Write-Output "$App not detected"
}

Write-Verbose "Command finished"