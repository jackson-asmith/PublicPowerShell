<#
.SYNOPSIS
    Reports Microsoft Loop workspaces across one or more SharePoint Online tenants.

.DESCRIPTION
    Connects to one or more SharePoint Online admin centers and enumerates all Loop
    workspaces using Get-SPOContainer. For each workspace, resolves the owner's display
    name, UPN, department, and Microsoft 365 license status via the Graph API. Handles
    pagination for tenants with more than 200 workspaces.

    Outputs a combined CSV tagged by region and prints a per-region summary to the
    console. Intended for scheduled execution via Task Scheduler with Start-Transcript
    for logging.

    Workspaces with no individual owner are reported as group-owned. Workspaces whose
    owner has no assigned licenses are reported as Unlicensed with remaining fields blank.

.PARAMETER Tenants
    Hashtable mapping a short region label to its SharePoint Online admin URL.
    Defaults to the NAM and CAN tenants defined in the script. Override at runtime
    to target a subset of tenants or add additional regions without editing the script.

.EXAMPLE
    .\Report-LoopWorkspace.ps1

    Runs against the default NAM and CAN tenants defined in the param block.

.EXAMPLE
    .\Report-LoopWorkspace.ps1 -Tenants @{ NAM = 'https://contoso-admin.sharepoint.com' }

    Runs against a single tenant, useful for testing or targeted reporting.

.NOTES
    Prerequisites:
      - Microsoft.Graph PowerShell SDK with Directory.Read.All scope
      - Microsoft.Online.SharePoint.PowerShell module
      - SharePoint Administrator role in each target tenant

    All tenants are assumed to share a single Entra ID. If a tenant has a separate
    Entra ID, Get-MgUser calls will fail for users in that tenant. Contact your
    infrastructure team about configuring a Multi-Tenant Organization (MTO) in
    Entra ID to address cross-tenant user resolution.

    Output: C:\temp\LoopWorkspaces.csv
#>

param(
    [hashtable]$Tenants = @{
        NAM = 'https://contoso-admin.sharepoint.com'
        CAN = 'https://contoso-ca-admin.sharepoint.com'
    }
)

# --- Connections ---

Connect-MgGraph -NoWelcome -Scopes Directory.Read.All
Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell

# Build geo list from the Tenants parameter - sorted so output is consistent
[array]$Geos = $Tenants.GetEnumerator() | Sort-Object Key | ForEach-Object {
    [PSCustomObject]@{ GeoLocation = $_.Key; TenantAdminSiteUrl = $_.Value }
}
Write-Host ("Tenants to process: {0}" -f ($Geos.GeoLocation -join ', '))

# --- Constants ---

$LoopAppId = 'a187e399-0c36-4b98-8f04-1edc167a0996'
$LoopServicePlan = 'c4b8c31a-fb44-4c65-9837-a21f55fcabda'
$CSVOutputFile = 'C:\temp\LoopWorkspaces.csv'

$LoopValidLicenses = @{
    'f245ecc8-75af-4f8e-b61f-27d8114de5f3' = 'Microsoft 365 Business Standard'
    'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46' = 'Microsoft 365 Business Premium'
    '05e9a617-0261-4cee-bb44-138d3ef5d965' = 'Microsoft 365 E3'
    '0c21030a-7e60-4ec7-9a0f-0042e0e0211a' = 'Microsoft 365 E3 Hub Min 500'
    '06ebc4ee-1bb5-47dd-8120-11324bc54e06' = 'Microsoft 365 E5'
}

# --- Collect workspaces from every geo ---

$Report = [System.Collections.Generic.List[Object]]::new()
$TotalBytes = 0

ForEach ($Geo in $Geos) {
    Write-Host ("`n=== {0} ({1}) ===" -f $Geo.GeoLocation, $Geo.TenantAdminSiteUrl)

    Connect-SPOService -Url $Geo.TenantAdminSiteUrl
    If (-not (Get-SPOTenant)) {
        Write-Host ("Failed to connect to {0} - skipping" -f $Geo.TenantAdminSiteUrl) -ForegroundColor Red
        Continue
    }

    # Paginate Get-SPOContainer - returns max 200 items per call plus a token at index 200
    $ContainerSplat = @{ OwningApplicationID = $LoopAppId; Paged = $true }
    [array]$GeoWorkspaces = @()
    [array]$Page = Get-SPOContainer @ContainerSplat

    While ($Page) {
        $Token = $null
        If ($Page[200]) {
            $Token = $Page[200].Split(':')[1].Trim()
            $Page = $Page[0..199]
        }
        ElseIf ($Page[-1] -eq 'End of containers view.') {
            $Page = $Page[0..($Page.Count - 2)]
        }
        $GeoWorkspaces += $Page
        $Page = If ($Token) { Get-SPOContainer @ContainerSplat -PagingToken $Token } Else { $null }
    }

    Write-Host ("{0} workspace(s) in {1}" -f $GeoWorkspaces.Count, $Geo.GeoLocation)
    If (-not $GeoWorkspaces) { Continue }

    $i = 0
    ForEach ($Space in ($GeoWorkspaces | Sort-Object ContainerName)) {
        $i++
        Write-Host ("  [{0}] {1} ({2}/{3})" -f $Geo.GeoLocation, $Space.ContainerName, $i, $GeoWorkspaces.Count)

        $Details = Get-SPOContainer -Identity $Space.ContainerId

        # Owner + license - default to group-owned; individual owner loop overrides if present
        $OwnerName = 'Microsoft 365 Group'; $LicenseName = 'Microsoft 365 Group'
        $UserUPN = $null; $Dept = $null; $LicenseStatus = 'OK'

        ForEach ($Owner in $Details.Owners) {
            $MgUserSplat = @{
                UserId      = $Owner
                Property    = 'DisplayName', 'UserPrincipalName', 'Department'
                ErrorAction = 'Stop'
            }
            Try { $User = Get-MgUser @MgUserSplat } Catch { $User = $null }
            If (-not $User) {
                Write-Host ("Could not resolve owner {0} - skipping" -f $Owner) -ForegroundColor Yellow
                Continue
            }

            $OwnerName = $User.DisplayName
            $UserUPN = $User.UserPrincipalName
            $Dept = $User.Department
            $LicenseStatus = 'Unlicensed'

            [array]$Licenses = Get-MgUserLicenseDetail -UserId $Owner
            If (-not $Licenses) { Continue }

            $LoopPlan = $Licenses | Select-Object -ExpandProperty ServicePlans |
            Where-Object { $_.ServicePlanId -eq $LoopServicePlan } |
            Select-Object -ExpandProperty ProvisioningStatus

            If ($LoopPlan -in 'Success', 'PendingProvisioning') { $LicenseStatus = 'OK' }
            $LicenseName = $Licenses.SkuId |
            ForEach-Object { $LoopValidLicenses[$_] } |
            Where-Object { $_ } |
            Select-Object -Last 1
        }

        # Managers (workspace members)
        $MemberNames = ($Details.Managers | ForEach-Object {
                Try { (Get-MgUser -UserId $_ -ErrorAction Stop).DisplayName } Catch { }
            }) -join ', '

        $TotalBytes += $Details.StorageUsedInBytes

        $Report.Add([PSCustomObject]@{
                GeoLocation      = $Geo.GeoLocation
                ContainerId      = $Space.ContainerId
                App              = $Details.OwningApplicationName
                'Workspace Name' = $Space.ContainerName
                Description      = $Space.Description
                Owner            = $OwnerName
                UPN              = $UserUPN
                Department       = $Dept
                License          = $LicenseStatus
                Product          = $LicenseName
                Members          = $MemberNames
                Created          = $Details.CreatedOn
                SiteURL          = $Details.ContainerSiteUrl
                'Storage (MB)'   = '{0:N2}' -f ($Details.StorageUsedInBytes / 1MB)
            })
    }
}

# --- Output ---

$Report | Sort-Object GeoLocation, 'Workspace Name' | Export-Csv -NoTypeInformation -Path $CSVOutputFile

Write-Host "`n=== Summary by Region ==="
$Report | Group-Object GeoLocation | Select-Object Name,
@{N = 'Workspaces'; E = { $_.Count } },
@{N = 'Storage (GB)'; E = {
        $mb = ($_.Group | Measure-Object { [double]$_.'Storage (MB)' } -Sum).Sum
        '{0:N2}' -f ($mb / 1024)
    }
} |
Format-Table -AutoSize

Write-Host ("Total workspaces : {0}" -f $Report.Count)
Write-Host ("Total storage    : {0:N2} GB" -f ($TotalBytes / 1GB))
Write-Host ("CSV written to   : {0}" -f $CSVOutputFile)