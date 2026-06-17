#Requires -Version 7.0

function Get-GitHubCopilotChargeback {
    <#
    .SYNOPSIS
    Reports per-department GitHub Copilot AI-credit chargeback for a billing month.
    .DESCRIPTION
    For each enterprise cost center (plus an unattributed bucket), pulls the AI-credit usage
    report for the given period and returns the billed overage to charge back to that
    department, alongside total credits consumed and the pool-covered (free) portion.
    .PARAMETER Enterprise
    The GitHub Enterprise slug whose billing is reported.
    .PARAMETER Year
    Billing year. Default: current year.
    .PARAMETER Month
    Billing month (1-12). Default: current month.
    .PARAMETER GithubToken
    A GitHub token with enterprise billing permissions. Defaults to the GITHUB_TOKEN
    environment variable.
    .EXAMPLE
    Get-GitHubCopilotChargeback -Enterprise contoso -Year 2026 -Month 6 |
        Export-Csv chargeback-2026-06.csv -NoTypeInformation

    Produces a per-department chargeback table for June 2026 and exports it to CSV.
    .EXAMPLE
    Get-GitHubCopilotChargeback -Enterprise contoso |
        Sort-Object BilledChargeback -Descending

    Shows the current month's departments ranked by billed overage.
    .NOTES
    Bill on BilledChargeback (netAmount) - it reconciles to the single Azure invoice.
    CreditsUsed/PoolCovered are reported for transparency only. Requires the enterprise
    spending limit to be above $0 for any billed overage to exist.
    .LINK
    https://docs.github.com/en/enterprise-cloud@latest/rest/billing/usage
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Enterprise,

        [ValidateRange(2024, 2100)]
        [int]$Year = (Get-Date).Year,

        [ValidateRange(1, 12)]
        [int]$Month = (Get-Date).Month,

        [ValidateNotNullOrEmpty()]
        [string]$GithubToken = $env:GITHUB_TOKEN
    )

    if ([string]::IsNullOrWhiteSpace($GithubToken)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new(
                    'A GitHub token is required. Pass -GithubToken or set the GITHUB_TOKEN environment variable.'),
                'MissingGithubToken',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                'GithubToken'))
    }

    $headers = @{
        Authorization          = "Bearer $GithubToken"
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2026-03-10'
    }

    $costCenters = Get-CostCenter -Enterprise $Enterprise -Headers $headers
    $buckets = @($costCenters) + [pscustomobject]@{ id = 'none'; name = '(unattributed)' }
    $period = '{0:D4}-{1:D2}' -f $Year, $Month

    foreach ($cc in $buckets) {
        $params = @{
            Uri     = "https://api.github.com/enterprises/$Enterprise/settings/billing/ai_credit/usage?year=$Year&month=$Month&cost_center_id=$($cc.id)"
            Headers = $headers
        }
        try {
            $report = Invoke-RestMethod @params -ErrorAction Stop
        }
        catch {
            # Surface the failure but keep reporting the remaining cost centers.
            $PSCmdlet.WriteError($_)
            continue
        }

        # NOTE: confirm the line-item array name ('usageItems') and field names
        # (grossQuantity / discountAmount / netAmount) against a live response.
        $items = $report.usageItems

        [pscustomobject]@{
            Department       = $cc.name
            CostCenterId     = $cc.id
            Period           = $period
            CreditsUsed      = [decimal](($items | Measure-Object -Property grossQuantity  -Sum).Sum)
            PoolCovered      = [decimal](($items | Measure-Object -Property discountAmount -Sum).Sum)
            BilledChargeback = [decimal](($items | Measure-Object -Property netAmount      -Sum).Sum)
        }
    }
}

function Get-CostCenter {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Enterprise,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    $all = @()
    $page = 1
    do {
        $params = @{
            Uri     = "https://api.github.com/enterprises/$Enterprise/settings/billing/cost-centers?per_page=100&page=$page"
            Headers = $Headers
        }
        $res = Invoke-RestMethod @params
        # NOTE: confirm the array field name ('costCenters') against a live response.
        $batch = @($res.costCenters)
        $all += $batch
        $page++
    } while ($batch.Count -eq 100)

    $all | Select-Object -Property id, name
}

Export-ModuleMember -Function 'Get-GitHubCopilotChargeback'
