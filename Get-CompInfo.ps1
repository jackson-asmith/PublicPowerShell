<#
.Synopsis
   Get-CompInfo collects basic information about one or more computers on a domain.
.DESCRIPTION
   Get-CompInfo collects Win32_OperatingSystem, LogicalDisk, and BIOS information from one or more computers
   on a domain. Get-CompInfo uses Get-CimInstance to retrieve information from the Win32_OperatingSystem,
   Win32_LogicalDisk, and Win32_BIOS ClassNames. Get-CompInfo also includes basic error handling and generates
   an appended log file called Get-CompInfoErrorLog.txt which includes a date, computer, and current error in
   your AdminFolder under Logs.
.PARAMETER ComputerName
   The computer name, or names, to query. Default: localhost set via $env:COMPUTERNAME.
.PARAMETER ErrorLog
   A switch for error logging.
.PARAMETER LogFile
   If ErrorLog is selected, errors are logged to C:\AdminFolder\Logs as Get-CompInfoErrorLog.txt
.EXAMPLE
   Get-CompInfo

   Retrieves Win32_OperatingSystem, Win32_LogicalDisk, and Win32_BIOS information from the local machine.
.EXAMPLE
   Get-CompInfo -ComputerName localhost, computer1, computer2, computer3 -ErrorLog

   Retrieves Win32_OperatingSystem, Win32_LogicalDisk, and Win32_BIOS information from the local machine as
   well as computers 1,2, and 3 and logs any errors.
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>
function Get-CompInfo {
   [CmdletBinding(DefaultParameterSetName = 'Parameter Set 1', 
      SupportsShouldProcess = $true, 
      PositionalBinding = $false,
      HelpUri = 'http://www.microsoft.com/',
      ConfirmImpact = 'Medium')]
   [Alias()]
   [OutputType([String])]
   Param
   (
      # Computer name or names to query
      [Parameter(Mandatory = $false, 
         ValueFromPipeline = $true,
         ValueFromPipelineByPropertyName = $true, 
         ValueFromRemainingArguments = $false, 
         Position = 0,
         ParameterSetName = 'Parameter Set 1',
         HelpMessage = "Enter computer name or names")]
      [ValidateNotNull()]
      [ValidateNotNullOrEmpty()]
      [ValidateCount(0, 15)]
      [ValidateScript( { Get-ADComputer -Filter * } )]
      [Alias("CN")]
      [String[]]
      $ComputerName = $env:COMPUTERNAME,

      # Switch to enable error logging
      [switch]
      $ErrorLog,

      # Destination for log file
      [String]
      $LogFile = "C:\AdminFolder\Logs\Errorlogs\Get-CompInfoErrorLog.txt"
   )

   Begin {
      If ($ErrorLog) {
         Write-Verbose "Error logging turned on"
      }
      Else {
         Write-Verbose "Error logging turned off"
      }
      Foreach ($C in $ComputerName) {
         Write-Verbose "Computer: $C"
      }
   }
   Process {
      If ($pscmdlet.ShouldProcess("Target", "Operation")) {
         Foreach ($C in $ComputerName) {
            Try {
               $CimParamHash = @{
                  ComputerName = $C
                  ClassName = "Win32_OperatingSystem"
                  ErrorAction = "Stop"
                  ErrorVariable = "CurrentError"
               }
               $OS = Get-CimInstance @CimParamHash
               $Disk = Get-CimInstance -ComputerName $C -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
               $BIOS = Get-CimInstance -ComputerName $C -ClassName Win32_BIOS

               #Creates an ordered hash table
               $Prop = [Ordered]@{
                  "ComputerName" = $C
                  "OS Name"      = $OS.Caption
                  "OS Build"     = $OS.BuildNumber
                  "BIOS Name"    = $BIOS.Name
                  "BIOS Version" = $BIOS.Version
                  "FreeSpace (GB)"    = $Disk.FreeSpace / 1gb -as [int]
               }
               $Obj = New-Object -TypeName PSObject -Property $Prop
               Write-Output $Obj
            }
            Catch {
               Write-Warning "Issue with $C"
               If ($ErrorLog) {
                  Get-Date | Out-File $LogFile -Append
                  $C | Out-File $LogFile -Append
                  $CurrentError | Out-File $LogFile -Append
               }
            }
         }
      }
   }
   End {
      Write-Verbose "Script complete"
   }
}