# Report-LoopWorkSpaces.PS1
# Reports Loop workspaces across all SharePoint Online geo locations.
# V2.0 Multi-geo rewrite

# --- Connections ---

Connect-MgGraph -NoWelcome -Scopes Directory.Read.All

$TenantPrefix    = ((Get-MgOrganization).VerifiedDomains | Where-Object { $_.IsDefault }).Name.Split('.')[0]
$PrimaryAdminUrl = "https://$TenantPrefix-admin.sharepoint.com"

Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
Connect-SPOService -Url $PrimaryAdminUrl

# --- Discover all geo locations ---
# Get-SPOGeoStorageQuota returns one object per geo with GeoLocation (NAM/EUR/APC/etc.)
# and TenantAdminSiteUrl. Falls back to a single-geo array if the tenant isn't multi-geo.

[array]$Geos = Get-SPOGeoStorageQuota
If (-not $Geos) {
    $Geos = @([PSCustomObject]@{ GeoLocation = 'NAM'; TenantAdminSiteUrl = $PrimaryAdminUrl })
}
Write-Host ("Geo locations found: {0}" -f ($Geos.GeoLocation -join ', '))

# --- Constants ---

$LoopAppId       = 'a187e399-0c36-4b98-8f04-1edc167a0996'
$LoopServicePlan = 'c4b8c31a-fb44-4c65-9837-a21f55fcabda'
$CSVOutputFile   = 'C:\temp\LoopWorkspaces.csv'

$LoopValidLicenses = @{
    'f245ecc8-75af-4f8e-b61f-27d8114de5f3' = 'Microsoft 365 Business Standard'
    'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46' = 'Microsoft 365 Business Premium'
    '05e9a617-0261-4cee-bb44-138d3ef5d965' = 'Microsoft 365 E3'
    '0c21030a-7e60-4ec7-9a0f-0042e0e0211a' = 'Microsoft 365 E3 Hub Min 500'
    '06ebc4ee-1bb5-47dd-8120-11324bc54e06' = 'Microsoft 365 E5'
}

# --- Collect workspaces from every geo ---

$Report     = [System.Collections.Generic.List[Object]]::new()
$TotalBytes = 0

ForEach ($Geo in $Geos) {
    Write-Host ("`n=== {0} ({1}) ===" -f $Geo.GeoLocation, $Geo.TenantAdminSiteUrl)

    # Reconnect for each satellite geo (each has its own admin endpoint)
    If ($Geo.TenantAdminSiteUrl -ne $PrimaryAdminUrl) {
        Connect-SPOService -Url $Geo.TenantAdminSiteUrl
    }

    # Paginate Get-SPOContainer — returns max 200 items per call plus a token at index 200
    $ContainerSplat = @{ OwningApplicationID = $LoopAppId; Paged = $true }
    [array]$GeoWorkspaces = @()
    [array]$Page = Get-SPOContainer @ContainerSplat

    While ($Page) {
        $Token = $null
        If ($Page[200]) {
            $Token = $Page[200].Split(':')[1].Trim()
            $Page  = $Page[0..199]
        } ElseIf ($Page[-1] -eq 'End of containers view.') {
            $Page  = $Page[0..($Page.Count - 2)]
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

        # Owner + license — default to group-owned; individual owner loop overrides if present
        $OwnerName = 'Microsoft 365 Group'; $LicenseName = 'Microsoft 365 Group'
        $UserUPN = $null; $Dept = $null; $LicenseStatus = 'OK'

        ForEach ($Owner in $Details.Owners) {
            $MgUserSplat = @{
                UserId      = $Owner
                Property    = 'DisplayName', 'UserPrincipalName', 'Department'
                ErrorAction = 'Stop'
            }
            Try {
                $User = Get-MgUser @MgUserSplat
            } Catch {
                Write-Host ("  Could not resolve owner {0} — skipping" -f $Owner) -ForegroundColor Yellow
                Continue
            }

            $OwnerName     = $User.DisplayName
            $UserUPN       = $User.UserPrincipalName
            $Dept          = $User.Department
            $LicenseStatus = 'Unlicensed'

            [array]$Licenses = Get-MgUserLicenseDetail -UserId $Owner
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
            'Workspace Name' = $Space.ContainerName
            Owner            = $OwnerName
            UPN              = $UserUPN
            Department       = $Dept
            License          = $LicenseStatus
            Product          = $LicenseName
            Members          = $MemberNames
            Created          = $Details.CreatedOn
            SiteURL          = $Details.ContainerSiteUrl
            'Storage (MB)'   = '{0:N2}' -f ($Details.StorageUsedInBytes / 1MB)
            ContainerId      = $Space.ContainerId
        })
    }
}

# --- Output ---

$Report | Sort-Object GeoLocation, 'Workspace Name' | Out-GridView -Title 'Loop Workspaces — All Regions'
$Report | Export-Csv -NoTypeInformation -Path $CSVOutputFile

Write-Host "`n=== Summary by Region ==="
$Report | Group-Object GeoLocation | Select-Object Name,
    @{N='Workspaces'; E={ $_.Count }},
    @{N='Storage (GB)'; E={
        $mb = ($_.Group | Measure-Object { [double]$_.'Storage (MB)' } -Sum).Sum
        '{0:N2}' -f ($mb / 1024)
    }} |
    Format-Table -AutoSize

Write-Host ("Total workspaces : {0}"    -f $Report.Count)
Write-Host ("Total storage    : {0:N2} GB" -f ($TotalBytes / 1GB))
Write-Host ("CSV written to   : {0}"    -f $CSVOutputFile)