function Get-TierModelConditionalGroupNames {
    <#
    .SYNOPSIS
    Resolve conditional principal group names based on domain environment type or conditional group objects.

    .DESCRIPTION
    Evaluates conditional principals defined in the TierModel configuration or a single
    conditional group object and returns the resolved group names that apply to the current
    domain environment.

    Supports two modes:
    1. From Config: Get-TierModelConditionalGroupNames -Config $config -DomainController $dc
       Evaluates $Config.conditionalPrincipals and returns structured PSCustomObject result.
    2. From Object: Get-TierModelConditionalGroupNames -ConditionalGroup $groupObj -DomainController $dc
       Evaluates a single conditionalGroup entry (from userRightsAssignments / restrictedGroups)
       and returns a string array [string[]] of resolved group names.

    .PARAMETER Config
    TierModel configuration object containing a conditionalPrincipals section.

    .PARAMETER ConditionalGroup
    A single conditional group object with 'names' and optional 'conditions'.

    .PARAMETER DomainController
    The domain controller to use for Active Directory queries.

    .PARAMETER ParentOU
    Optional parent OU path.

    .PARAMETER CorrelationId
    Optional correlation ID for logging.

    .OUTPUTS
    PSCustomObject when called with -Config, or [string[]] when called with -ConditionalGroup.
    #>
    [CmdletBinding(DefaultParameterSetName = 'FromConfig')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'FromConfig')]
        [object]$Config,

        [Parameter(Mandatory, ParameterSetName = 'FromGroup')]
        [PSCustomObject]$ConditionalGroup,

        [Parameter(Mandatory)]
        [string]$DomainController,

        [Parameter()]
        [string]$ParentOU,

        [Parameter()]
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )

    $startTime = Get-Date

    # ── Mode 2: From Single ConditionalGroup Object (used by New-TierModelGptTmplContent) ──
    if ($PSCmdlet.ParameterSetName -eq 'FromGroup' -or $null -ne $ConditionalGroup) {
        $resolvedNames = @()

        if (-not $ConditionalGroup.PSObject.Properties['names'] -or -not $ConditionalGroup.names) {
            return $resolvedNames
        }

        # No conditions defined — return all names unconditionally (backwards compatible)
        if (-not $ConditionalGroup.PSObject.Properties['conditions'] -or
            -not $ConditionalGroup.conditions -or
            @($ConditionalGroup.conditions).Count -eq 0) {
            return @($ConditionalGroup.names)
        }

        foreach ($name in $ConditionalGroup.names) {
            $include = $true
            foreach ($condition in $ConditionalGroup.conditions) {
                if ($condition.type -eq 'groupExists' -and $condition.operator -eq 'exists') {
                    try {
                        $adGroup = Get-ADGroup -Identity $name -Server $DomainController -ErrorAction Stop
                    } catch {
                        $adGroup = $null
                    }
                    if (-not $adGroup) {
                        Write-Verbose "Conditional group '$name' not found in AD — skipping"
                        $include = $false
                        break
                    }
                }
            }
            if ($include) {
                $resolvedNames += $name
            }
        }
        return @($resolvedNames)
    }

    # ── Mode 1: From Configuration Object (Full ConditionalPrincipals Resolution) ──
    Write-TierModelLog -Level Info -Message "ConditionalGroupNamesStart" -Data @{
        DomainController = $DomainController
        CorrelationId    = $CorrelationId
        ParentOU         = $ParentOU
    } | Out-Null

    $groupNames         = [System.Collections.Generic.List[string]]::new()
    $resolvedConditions = [System.Collections.Generic.List[object]]::new()
    $warnings           = @()
    $errors             = @()
    $totalEvaluated     = 0
    $totalResolved      = 0

    try {
        if (-not $Config.PSObject.Properties['conditionalPrincipals'] -or
            -not $Config.conditionalPrincipals) {

            Write-TierModelLog -Level Warning -Message "No conditionalPrincipals section found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            $warnings += "No conditionalPrincipals section found in configuration. " +
                         "Add a 'conditionalPrincipals' array to your TierModel config to use environment-conditional group resolution."

            return [PSCustomObject]@{
                GroupNames         = @()
                ResolvedConditions = @()
                Warnings           = $warnings
                Errors             = $errors
                TotalEvaluated     = 0
                TotalResolved      = 0
                DurationMs         = ((Get-Date) - $startTime).TotalMilliseconds
                CorrelationId      = $CorrelationId
            }
        }

        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController

        # Detect AD-Integrated DNS once
        $adIntegratedDnsDetected = $false
        try {
            $dnsZones = Get-ADObject -Filter { objectClass -eq 'dnsZone' } `
                            -SearchBase "CN=MicrosoftDNS,DC=DomainDnsZones,$domainDN" `
                            -Server $DomainController `
                            -ErrorAction SilentlyContinue
            $adIntegratedDnsDetected = ($null -ne $dnsZones -and @($dnsZones).Count -gt 0)
        } catch {
            Write-TierModelLog -Level Warning -Message "AD-Integrated DNS detection failed, assuming false" -Data @{
                DomainController = $DomainController
                Exception        = $_.Exception.Message
                CorrelationId    = $CorrelationId
            } | Out-Null
            $warnings += "Could not detect AD-Integrated DNS status: $($_.Exception.Message). Defaulting to false."
        }

        foreach ($entry in $Config.conditionalPrincipals) {
            $totalEvaluated++

            $hasName = ($entry.PSObject.Properties.Name -contains 'name') -and
                       -not [string]::IsNullOrWhiteSpace($entry.name)
            $hasCondition = ($entry.PSObject.Properties.Name -contains 'condition') -and $null -ne $entry.condition

            if (-not $hasName) {
                $warnings += "ConditionalPrincipal entry #$totalEvaluated is missing 'name' property — skipped."
                $resolvedConditions.Add([PSCustomObject]@{
                    EntryIndex    = $totalEvaluated
                    Name          = '<unnamed>'
                    ConditionType = 'unknown'
                    Resolved      = $false
                    Reason        = "Missing 'name' property"
                })
                continue
            }

            $entryName = $entry.name

            if (-not $hasCondition) {
                $groupNames.Add($entryName)
                $totalResolved++
                $resolvedConditions.Add([PSCustomObject]@{
                    EntryIndex    = $totalEvaluated
                    Name          = $entryName
                    ConditionType = 'unconditional'
                    Resolved      = $true
                    Reason        = "No condition specified — always included"
                })
                continue
            }

            $condition     = $entry.condition
            $conditionType = if ($condition.PSObject.Properties.Name -contains 'type') { $condition.type } else { 'unknown' }

            $conditionMet = $false
            $reason       = ''

            switch ($conditionType) {
                'adIntegratedDns' {
                    $expectedValue = $true
                    if ($condition.PSObject.Properties.Name -contains 'value') {
                        $expectedValue = [bool]$condition.value
                    }
                    $conditionMet = ($adIntegratedDnsDetected -eq $expectedValue)
                    $reason = "AD-Integrated DNS detected=$adIntegratedDnsDetected, expected=$expectedValue"
                }

                'groupExists' {
                    if (-not ($condition.PSObject.Properties.Name -contains 'groupName') -or
                        [string]::IsNullOrWhiteSpace($condition.groupName)) {
                        $warnings += "Condition 'groupExists' for '$entryName' missing 'groupName' — skipped."
                        $reason = "Missing groupName in condition"
                        break
                    }
                    $targetGroup = $condition.groupName
                    try {
                        $found = Get-ADGroup -Identity $targetGroup `
                                     -Server $DomainController `
                                     -ErrorAction SilentlyContinue
                        $conditionMet = ($null -ne $found)
                        $reason = "Group '$targetGroup' $(if($conditionMet){'exists'}else{'not found'}) in AD"
                    } catch {
                        $conditionMet = $false
                        $reason = "Error checking group '$targetGroup': $($_.Exception.Message)"
                        $warnings += "Could not check group existence for '$entryName': $($_.Exception.Message)"
                    }
                }

                'domainType' {
                    $expectedType = if ($condition.PSObject.Properties.Name -contains 'domainTypeValue') {
                        $condition.domainTypeValue
                    } else { 'standard' }

                    $currentDomainType = 'standard'
                    try {
                        $domain = Get-ADDomain -Server $DomainController -ErrorAction Stop
                        if ($domain.ParentDomain) {
                            $currentDomainType = 'child'
                        } elseif ($domain.DomainMode -ge 7) {
                            $currentDomainType = 'modern'
                        } else {
                            $currentDomainType = 'standard'
                        }
                    } catch {
                        $warnings += "Could not determine domain type for '$entryName': $($_.Exception.Message)"
                        $reason = "Domain type detection failed: $($_.Exception.Message)"
                        break
                    }
                    $conditionMet = ($currentDomainType -eq $expectedType)
                    $reason = "Domain type is '$currentDomainType', condition expects '$expectedType'"
                }

                default {
                    $warnings += "Unknown condition type '$conditionType' for entry '$entryName' — skipped."
                    $reason = "Unsupported condition type: $conditionType"
                }
            }

            $resolvedConditions.Add([PSCustomObject]@{
                EntryIndex    = $totalEvaluated
                Name          = $entryName
                ConditionType = $conditionType
                Resolved      = $conditionMet
                Reason        = $reason
            })

            if ($conditionMet) {
                $groupNames.Add($entryName)
                $totalResolved++
            }
        }

        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds

        return [PSCustomObject]@{
            GroupNames         = @($groupNames)
            ResolvedConditions = @($resolvedConditions)
            Warnings           = $warnings
            Errors             = $errors
            TotalEvaluated     = $totalEvaluated
            TotalResolved      = $totalResolved
            DurationMs         = $durationMs
            CorrelationId      = $CorrelationId
        }

    } catch {
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        $errors += @{
            Timestamp = Get-Date
            Category  = 'Execution'
            Code      = 'ConditionalGroupNamesFailed'
            Message   = "Get-TierModelConditionalGroupNames failed: $($_.Exception.Message)"
            Context   = @{ Exception = $_.Exception.Message; CorrelationId = $CorrelationId }
        }

        return [PSCustomObject]@{
            GroupNames         = @()
            ResolvedConditions = @()
            Warnings           = $warnings
            Errors             = $errors
            TotalEvaluated     = $totalEvaluated
            TotalResolved      = 0
            DurationMs         = $durationMs
            CorrelationId      = $CorrelationId
        }
    }
}
