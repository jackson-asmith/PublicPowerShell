#Requires -Version 7.0

function Set-GitHubCopilotBudget {
    <#
    .SYNOPSIS
    Synchronizes per-user GitHub Copilot AI-credit budgets for the members of a cost center.
    .DESCRIPTION
    Reads the members of a power-user cost center in a GitHub Enterprise account and ensures
    each one has a per-user AI-credit budget set to the requested amount. Existing budgets are
    updated in place; members without one have a budget created. Supports -WhatIf and -Confirm.
    .PARAMETER Enterprise
    The GitHub Enterprise slug whose billing settings are managed.
    .PARAMETER CostCenterId
    The GUID of the cost center that contains the power users. Obtain it from
    GET /enterprises/{enterprise}/settings/billing/cost-centers.
    .PARAMETER PowerUserBudget
    The AI-credit budget amount, in USD, to apply to each power user. Default: 100.
    .PARAMETER GithubToken
    A GitHub token with enterprise billing permissions. Defaults to the GITHUB_TOKEN
    environment variable.
    .PARAMETER PreventFurtherUsage
    When set, each user budget hard-stops the user once the amount is reached. Omitted
    (the default), the budget is a soft/tracking threshold and the user continues into
    billable overage - the model for power users who pay per use and are charged back.
    .EXAMPLE
    Set-GitHubCopilotBudget -Enterprise contoso -CostCenterId 1a2b3c -GithubToken $token

    Syncs every power user's Copilot budget to the $100 default. Users are not hard-stopped;
    overage beyond the budget remains billable (pay-per-use).
    .EXAMPLE
    Set-GitHubCopilotBudget -Enterprise contoso -CostCenterId 1a2b3c -PreventFurtherUsage

    Syncs budgets that hard-stop each user at the amount (rationing tier).
    .EXAMPLE
    Set-GitHubCopilotBudget -Enterprise contoso -CostCenterId 1a2b3c -PowerUserBudget 250 -WhatIf

    Previews the budget changes without calling the write endpoints.
    .NOTES
    Automated callers should pass -Confirm:$false so an unattended run never blocks on a
    confirmation prompt. There is a known API bug where migrated per-user (PRU) budgets may
    need to be deleted and recreated rather than patched.
    .LINK
    https://docs.github.com/en/rest/enterprise-admin/billing
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Enterprise,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CostCenterId,

        [ValidateRange(0, 1000000)]
        [decimal]$PowerUserBudget = 100,

        [ValidateNotNullOrEmpty()]
        [string]$GithubToken = $env:GITHUB_TOKEN,

        [switch]$PreventFurtherUsage
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

    $existingBudgets = Get-ExistingBudget -Enterprise $Enterprise -Headers $headers
    $powerUsers = Get-CostCenterMember -Enterprise $Enterprise -CostCenterId $CostCenterId -Headers $headers

    foreach ($user in $powerUsers) {
        $existingBudgetId = ($existingBudgets | Where-Object { $_.budget_entity_name -eq $user }).id

        $budgetParams = @{
            Username            = $user
            Enterprise          = $Enterprise
            Headers             = $headers
            BudgetAmount        = $PowerUserBudget
            ExistingBudgetId    = $existingBudgetId
            PreventFurtherUsage = [bool]$PreventFurtherUsage
        }
        Set-UserBudget @budgetParams
    }

    Write-Verbose "Done. $($powerUsers.Count) power user budgets synced."
}

function Get-ExistingBudget {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Enterprise,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    $budgets = @()
    $page = 1
    do {
        $params = @{
            Uri     = "https://api.github.com/enterprises/$Enterprise/settings/billing/budgets?per_page=10&page=$page"
            Headers = $Headers
        }
        $res = Invoke-RestMethod @params
        $budgets += $res.budgets
        $page++
    } while ($res.budgets.Count -eq 10)

    # Filter to individual user-scoped AI credit budgets only
    $budgets | Where-Object {
        $_.budget_scope -eq 'user' -and
        $_.budget_product_sku -eq 'ai_credits' -and
        $_.budget_entity_name -ne ''
    }
}

function Get-CostCenterMember {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Enterprise,

        [Parameter(Mandatory)]
        [string]$CostCenterId,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    # Returns GitHub logins for users in the power user cost center
    $params = @{
        Uri     = "https://api.github.com/enterprises/$Enterprise/settings/billing/cost-centers/$CostCenterId"
        Headers = $Headers
    }
    $res = Invoke-RestMethod @params
    $res.resources |
        Where-Object { $_.type -eq 'user' } |
        Select-Object -ExpandProperty name
}

function Set-UserBudget {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Enterprise,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [Parameter(Mandatory)]
        [decimal]$BudgetAmount,

        [string]$ExistingBudgetId,

        [bool]$PreventFurtherUsage = $false
    )

    $body = @{
        budget_amount         = $BudgetAmount
        prevent_further_usage = $PreventFurtherUsage
        budget_scope          = 'user'
        budget_entity_name    = ''
        budget_type           = 'BundlePricing'
        budget_product_sku    = 'ai_credits'
        budget_alerting       = @{ will_alert = $false; alert_recipients = @() }
        user                  = $Username
    } | ConvertTo-Json -Depth 5

    if ($ExistingBudgetId) {
        # Update - note: there's a known API bug where migrated PRU budgets may
        # need to be deleted and recreated rather than patched
        if ($PSCmdlet.ShouldProcess($Username, "Update Copilot budget (ID: $ExistingBudgetId)")) {
            Write-Verbose "Updating budget for $Username (ID: $ExistingBudgetId)"
            $params = @{
                Method      = 'Patch'
                Uri         = "https://api.github.com/enterprises/$Enterprise/settings/billing/budgets/$ExistingBudgetId"
                Headers     = $Headers
                Body        = $body
                ContentType = 'application/json'
            }
            Invoke-RestMethod @params
        }
    }
    else {
        if ($PSCmdlet.ShouldProcess($Username, 'Create Copilot budget')) {
            Write-Verbose "Creating budget for $Username"
            $params = @{
                Method      = 'Post'
                Uri         = "https://api.github.com/enterprises/$Enterprise/settings/billing/budgets"
                Headers     = $Headers
                Body        = $body
                ContentType = 'application/json'
            }
            Invoke-RestMethod @params
        }
    }
}

Export-ModuleMember -Function 'Set-GitHubCopilotBudget'