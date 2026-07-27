<#
.SYNOPSIS
Unit tests for Get-TierModelConditionalGroupNames.

.DESCRIPTION
Comprehensive Pester v5 tests for the conditional group name resolution function.
Covers all condition types (adIntegratedDns, groupExists, domainType),
edge cases (missing section, unconditional entries, unknown types),
and error handling paths.

.NOTES
Author: TierModel Testing Team
Tags: Unit, ConditionalPrincipals, Group
#>

BeforeAll {
    # Import the TierModel module
    $modulePath = Join-Path $PSScriptRoot '..\modules\TierModel\TierModel.psd1'
    Import-Module $modulePath -Force

    # Set correlation ID for logging
    InModuleScope TierModel {
        $script:CorrelationId = 'test-conditional-' + (New-Guid).ToString()
    }
}

Describe "Get-TierModelConditionalGroupNames" -Tag "Unit", "ConditionalPrincipals" {

    BeforeAll {
        $script:TestDC     = "DC01.test.local"
        $script:TestDomainDN = "DC=test,DC=local"

        # ── Base mocks shared across all contexts ─────────────────────────
        InModuleScope TierModel {
            Mock Write-TierModelLog { }
            Mock Resolve-TierModelDomainDN { return "DC=test,DC=local" }
            Mock Get-ADDomain {
                return [PSCustomObject]@{
                    DistinguishedName = "DC=test,DC=local"
                    ParentDomain      = $null
                    DomainMode        = 7    # WinThreshold = modern
                }
            }
            # AD-Integrated DNS NOT present by default
            Mock Get-ADObject { return $null }
            Mock Get-ADGroup {
                param($Identity, $Server, $ErrorAction)
                if ($Identity -eq "DnsAdmins") {
                    return [PSCustomObject]@{ Name = "DnsAdmins" }
                }
                return $null
            }
        }

        # ── Config helpers ────────────────────────────────────────────────

        # Config WITHOUT conditionalPrincipals section
        $script:ConfigNoPrincipals = [PSCustomObject]@{
            organizationUnits = @()
            groups            = @()
        }

        # Config with unconditional entry (no condition property)
        $script:ConfigUnconditional = [PSCustomObject]@{
            conditionalPrincipals = @(
                [PSCustomObject]@{ name = "DnsAdmins" }     # no 'condition'
                [PSCustomObject]@{ name = "DnsUpdateProxy" } # no 'condition'
            )
        }

        # Config with adIntegratedDns condition (expects true)
        $script:ConfigDnsTrue = [PSCustomObject]@{
            conditionalPrincipals = @(
                [PSCustomObject]@{
                    name      = "DnsAdmins"
                    condition = [PSCustomObject]@{ type = "adIntegratedDns"; value = $true }
                }
            )
        }

        # Config with adIntegratedDns condition (expects false)
        $script:ConfigDnsFalse = [PSCustomObject]@{
            conditionalPrincipals = @(
                [PSCustomObject]@{
                    name      = "ExternalDnsGroup"
                    condition = [PSCustomObject]@{ type = "adIntegratedDns"; value = $false }
                }
            )
        }

        # Config with groupExists condition
        $script:ConfigGroupExists = [PSCustomObject]@{
            conditionalPrincipals = @(
                [PSCustomObject]@{
                    name      = "Tier0DNSAdmins"
                    condition = [PSCustomObject]@{ type = "groupExists"; groupName = "DnsAdmins" }
                }
            )
        }

        # Config with domainType condition
        $script:ConfigDomainType = [PSCustomObject]@{
            conditionalPrincipals = @(
                [PSCustomObject]@{
                    name      = "ModernDomainGroup"
                    condition = [PSCustomObject]@{ type = "domainType"; domainTypeValue = "modern" }
                }
            )
        }

        # Config with unknown condition type
        $script:ConfigUnknownType = [PSCustomObject]@{
            conditionalPrincipals = @(
                [PSCustomObject]@{
                    name      = "SomeGroup"
                    condition = [PSCustomObject]@{ type = "unsupportedConditionType" }
                }
            )
        }

        # Config with entry missing 'name'
        $script:ConfigMissingName = [PSCustomObject]@{
            conditionalPrincipals = @(
                [PSCustomObject]@{
                    # 'name' deliberately absent
                    condition = [PSCustomObject]@{ type = "adIntegratedDns"; value = $true }
                }
            )
        }

        # Config with mixed entries (some resolve, some don't)
        $script:ConfigMixed = [PSCustomObject]@{
            conditionalPrincipals = @(
                [PSCustomObject]@{ name = "AlwaysIncluded" }   # unconditional
                [PSCustomObject]@{
                    name      = "DnsAdmins"
                    condition = [PSCustomObject]@{ type = "adIntegratedDns"; value = $true }   # DNS not present → false
                }
                [PSCustomObject]@{
                    name      = "NoDnsGroup"
                    condition = [PSCustomObject]@{ type = "adIntegratedDns"; value = $false }  # DNS not present → true
                }
            )
        }
    }

    # =========================================================================
    Context "Output structure" {
    # =========================================================================

        It "Should return PSCustomObject with required properties" {
            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigNoPrincipals `
                          -DomainController $script:TestDC

            $result                              | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name     | Should -Contain 'GroupNames'
            $result.PSObject.Properties.Name     | Should -Contain 'ResolvedConditions'
            $result.PSObject.Properties.Name     | Should -Contain 'Warnings'
            $result.PSObject.Properties.Name     | Should -Contain 'Errors'
            $result.PSObject.Properties.Name     | Should -Contain 'TotalEvaluated'
            $result.PSObject.Properties.Name     | Should -Contain 'TotalResolved'
            $result.PSObject.Properties.Name     | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name     | Should -Contain 'CorrelationId'
        }

        It "Should return non-null DurationMs" {
            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigNoPrincipals `
                          -DomainController $script:TestDC
            $result.DurationMs | Should -BeGreaterOrEqual 0
        }

        It "Should accept and propagate custom CorrelationId" {
            $cid    = [System.Guid]::NewGuid().ToString()
            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigNoPrincipals `
                          -DomainController $script:TestDC -CorrelationId $cid
            $result.CorrelationId | Should -Be $cid
        }
    }

    # =========================================================================
    Context "No conditionalPrincipals section" {
    # =========================================================================

        It "Should return empty GroupNames when section is absent" {
            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigNoPrincipals `
                          -DomainController $script:TestDC
            $result.GroupNames     | Should -BeNullOrEmpty
            $result.TotalEvaluated | Should -Be 0
        }

        It "Should add a warning when section is absent" {
            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigNoPrincipals `
                          -DomainController $script:TestDC
            $result.Warnings | Should -Not -BeNullOrEmpty
            $result.Warnings[0] | Should -Match 'conditionalPrincipals'
        }
    }

    # =========================================================================
    Context "Unconditional principals (no condition property)" {
    # =========================================================================

        It "Should always include entries with no condition" {
            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigUnconditional `
                          -DomainController $script:TestDC

            $result.GroupNames       | Should -Contain "DnsAdmins"
            $result.GroupNames       | Should -Contain "DnsUpdateProxy"
            $result.TotalEvaluated   | Should -Be 2
            $result.TotalResolved    | Should -Be 2
        }

        It "Should set ConditionType to 'unconditional' in ResolvedConditions" {
            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigUnconditional `
                          -DomainController $script:TestDC

            $result.ResolvedConditions[0].ConditionType | Should -Be 'unconditional'
            $result.ResolvedConditions[0].Resolved      | Should -BeTrue
        }
    }

    # =========================================================================
    Context "Condition type: adIntegratedDns" {
    # =========================================================================

        It "Should resolve group when adIntegratedDns=true and DNS zones are present" {
            # Override: simulate AD-Integrated DNS present
            InModuleScope TierModel {
                Mock Get-ADObject {
                    return @([PSCustomObject]@{ Name = "_msdcs" })
                }
            }

            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigDnsTrue `
                          -DomainController $script:TestDC

            $result.GroupNames    | Should -Contain "DnsAdmins"
            $result.TotalResolved | Should -Be 1
        }

        It "Should NOT resolve group when adIntegratedDns=true but DNS zones are absent" {
            # Get-ADObject returns null → no AD-Integrated DNS
            InModuleScope TierModel {
                Mock Get-ADObject { return $null }
            }

            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigDnsTrue `
                          -DomainController $script:TestDC

            $result.GroupNames    | Should -Not -Contain "DnsAdmins"
            $result.TotalResolved | Should -Be 0
        }

        It "Should resolve group when adIntegratedDns=false and DNS zones are absent" {
            InModuleScope TierModel {
                Mock Get-ADObject { return $null }
            }

            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigDnsFalse `
                          -DomainController $script:TestDC

            $result.GroupNames    | Should -Contain "ExternalDnsGroup"
            $result.TotalResolved | Should -Be 1
        }

        It "Should add warning when DNS detection throws, and default to false" {
            InModuleScope TierModel {
                Mock Get-ADObject { throw "Access denied" }
            }

            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigDnsTrue `
                          -DomainController $script:TestDC

            $result.Warnings | Should -Not -BeNullOrEmpty
            # DNS = false by default, config expects true → not resolved
            $result.GroupNames | Should -Not -Contain "DnsAdmins"
        }
    }

    # =========================================================================
    Context "Condition type: groupExists" {
    # =========================================================================

        BeforeEach {
            InModuleScope TierModel {
                Mock Get-ADGroup {
                    return [PSCustomObject]@{ Name = "DnsAdmins"; DistinguishedName = "CN=DnsAdmins,DC=test,DC=local" }
                }
            }
        }

        It "Should resolve group when target group exists in AD" {
            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigGroupExists `
                          -DomainController $script:TestDC

            $result.GroupNames    | Should -Contain "Tier0DNSAdmins"
            $result.TotalResolved | Should -Be 1
        }

        It "Should NOT resolve group when target group does not exist in AD" {
            InModuleScope TierModel {
                Mock Get-ADGroup { return $null }
            }

            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigGroupExists `
                          -DomainController $script:TestDC

            $result.GroupNames    | Should -Not -Contain "Tier0DNSAdmins"
            $result.TotalResolved | Should -Be 0
        }

        It "Should add warning and skip when groupName property is missing" {
            $configMissingGroupName = [PSCustomObject]@{
                conditionalPrincipals = @(
                    [PSCustomObject]@{
                        name      = "SomeGroup"
                        condition = [PSCustomObject]@{ type = "groupExists" }  # no groupName
                    }
                )
            }

            $result = Get-TierModelConditionalGroupNames -Config $configMissingGroupName `
                          -DomainController $script:TestDC

            $result.Warnings      | Should -Not -BeNullOrEmpty
            $result.GroupNames    | Should -Not -Contain "SomeGroup"
        }
    }

    # =========================================================================
    Context "Condition type: domainType" {
    # =========================================================================

        It "Should resolve group when domainType matches current domain (modern)" {
            # Get-ADDomain mock already returns DomainMode=7, no ParentDomain → 'modern'
            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigDomainType `
                          -DomainController $script:TestDC

            $result.GroupNames    | Should -Contain "ModernDomainGroup"
            $result.TotalResolved | Should -Be 1
        }

        It "Should NOT resolve group when domainType does not match" {
            $configStandardType = [PSCustomObject]@{
                conditionalPrincipals = @(
                    [PSCustomObject]@{
                        name      = "StandardDomainGroup"
                        condition = [PSCustomObject]@{ type = "domainType"; domainTypeValue = "standard" }
                    }
                )
            }
            # Current mock returns 'modern' → 'standard' doesn't match
            $result = Get-TierModelConditionalGroupNames -Config $configStandardType `
                          -DomainController $script:TestDC

            $result.GroupNames    | Should -Not -Contain "StandardDomainGroup"
            $result.TotalResolved | Should -Be 0
        }
    }

    # =========================================================================
    Context "Unknown / unsupported condition type" {
    # =========================================================================

        It "Should add warning for unknown condition type and not include the group" {
            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigUnknownType `
                          -DomainController $script:TestDC

            $result.GroupNames    | Should -Not -Contain "SomeGroup"
            $result.Warnings      | Should -Not -BeNullOrEmpty
            $result.TotalResolved | Should -Be 0
        }
    }

    # =========================================================================
    Context "Entry missing 'name' property" {
    # =========================================================================

        It "Should add warning and skip entry when 'name' is absent" {
            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigMissingName `
                          -DomainController $script:TestDC

            $result.Warnings         | Should -Not -BeNullOrEmpty
            $result.GroupNames       | Should -BeNullOrEmpty
            $result.TotalEvaluated   | Should -Be 1
            $result.TotalResolved    | Should -Be 0
        }
    }

    # =========================================================================
    Context "Mixed entry scenario" {
    # =========================================================================

        It "Should correctly separate resolved from unresolved entries" {
            InModuleScope TierModel {
                Mock Get-ADObject { return $null }  # No AD-Integrated DNS
            }

            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigMixed `
                          -DomainController $script:TestDC

            # AlwaysIncluded: unconditional → resolved
            $result.GroupNames | Should -Contain "AlwaysIncluded"

            # DnsAdmins: expects DNS=true, actual DNS=false → NOT resolved
            $result.GroupNames | Should -Not -Contain "DnsAdmins"

            # NoDnsGroup: expects DNS=false, actual DNS=false → resolved
            $result.GroupNames | Should -Contain "NoDnsGroup"

            $result.TotalEvaluated | Should -Be 3
            $result.TotalResolved  | Should -Be 2
        }

        It "Should populate ResolvedConditions for every entry evaluated" {
            InModuleScope TierModel {
                Mock Get-ADObject { return $null }
            }

            $result = Get-TierModelConditionalGroupNames -Config $script:ConfigMixed `
                          -DomainController $script:TestDC

            $result.ResolvedConditions.Count | Should -Be 3

            $result.ResolvedConditions[0].Name          | Should -Be "AlwaysIncluded"
            $result.ResolvedConditions[0].ConditionType | Should -Be "unconditional"
            $result.ResolvedConditions[0].Resolved      | Should -BeTrue

            $result.ResolvedConditions[1].Name     | Should -Be "DnsAdmins"
            $result.ResolvedConditions[1].Resolved  | Should -BeFalse

            $result.ResolvedConditions[2].Name     | Should -Be "NoDnsGroup"
            $result.ResolvedConditions[2].Resolved  | Should -BeTrue
        }
    }
}
