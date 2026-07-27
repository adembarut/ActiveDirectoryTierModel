function Get-TierModelOu {
    <#
    .SYNOPSIS
    Generate ordered OU creation plan based on configuration.
    
    .DESCRIPTION
    Analyzes TierModel configuration to determine which OUs need to be created,
    applying parent-first ordering and existence checks. Returns structured plan
    without making any changes to Active Directory.
    
    .PARAMETER Config
    TierModel configuration object from Get-TierModelConfig.
    
    .PARAMETER DomainController
    Preferred domain controller for queries.
    
    .PARAMETER IncludeDetails
    Include detailed ordering information in output.
    
    .OUTPUTS
    PSCustomObject with Actions, Summary, Warnings, Errors, and optional Ordering.
    
    .EXAMPLE
    $config = Get-TierModelConfig
    $plan = Get-TierModelOu -Config $config -DomainController "DC01.contoso.com"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [switch]$IncludeDetails,
        
        [Parameter()]
        [string]$ParentOU
    )
    
    $CorrelationId = $script:CorrelationId
    Write-TierModelLog -Level Info -Message "OuPlanStart" -Data @{
        CorrelationId = $CorrelationId
        DomainController = $DomainController
        IncludeDetails = $IncludeDetails.IsPresent
        ParentOU = $ParentOU
    } | Out-Null
    
    $actions = @()
    $warnings = @()
    $errors = @()
    $ordering = @()
    
    try {
        # Resolve domain DN and effective base DN
        $domainDN = Resolve-TierModelDomainDN -DomainController $DomainController
        $effectiveBaseDN = Resolve-TierModelPlaceholder -Path '' -DomainDN $domainDN -ParentOU $ParentOU
        
        # If ParentOU is specified and is an OU (starts with OU=), ensure the Parent OU itself exists
        if (-not [string]::IsNullOrWhiteSpace($ParentOU) -and $effectiveBaseDN -ne $domainDN) {
            $parentExistence = Test-TierModelOuExists -DistinguishedName $effectiveBaseDN -DomainController $DomainController
            if (-not $parentExistence.Exists) {
                # Extract Parent OU name and target parent path
                $parentParts = $effectiveBaseDN -split ',', 2
                $parentName = $parentParts[0] -replace '^OU=', ''
                $parentTargetContainer = $parentParts[1]
                
                $parentOuData = [PSCustomObject]@{
                    name = $parentName
                    path = $parentTargetContainer
                    protectFromAccidentalDeletion = $true
                    disableInheritance = $false
                    blockGpoInheritance = $false
                    comment = "Parent OU for Tier Model"
                    correctedPath = $parentTargetContainer
                }
                
                $actions += [PSCustomObject]@{
                    Action = 'CreateOU'
                    ResourceType = 'OrganizationalUnit'
                    Name = $parentName
                    Path = $parentTargetContainer
                    Data = $parentOuData
                }
            }
        }
        
        # Check if organizationUnits exists in config
        if (-not $Config.PSObject.Properties['organizationUnits'] -or -not $Config.organizationUnits) {
            Write-TierModelLog -Level Warning -Message "No organizationUnits found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            $warnings += "No organizationUnits section found in configuration"
        } else {
            # Sort OUs by dependency order: root-level first, then by depth
            # This ensures parent OUs are created before child OUs
            $sortedOUs = $Config.organizationUnits | Sort-Object {
                $resolvedPath = Resolve-TierModelOuPath -OuPath $_.path -DomainDN $domainDN -ParentOU $ParentOU
                if ($resolvedPath -eq $effectiveBaseDN) {
                    0  # Base level OUs first
                } else {
                    ($resolvedPath -split ',').Count  # Sort by depth (comma count)
                }
            }
            
            $ordering = $sortedOUs | ForEach-Object {
                $resolvedPath = Resolve-TierModelOuPath -OuPath $_.path -DomainDN $domainDN -ParentOU $ParentOU
                [PSCustomObject]@{
                    Name = $_.name
                    OriginalPath = $_.path
                    ResolvedPath = $resolvedPath
                    DistinguishedName = "OU=$($_.name),$resolvedPath"
                    Depth = if ($resolvedPath -eq $effectiveBaseDN) { 0 } else { ($resolvedPath -split ',').Count }
                }
            }
            
            foreach ($ou in $sortedOUs) {
                try {
                    # Resolve path with placeholder replacement
                    $resolvedPath = Resolve-TierModelOuPath -OuPath $ou.path -DomainDN $domainDN -ParentOU $ParentOU
                    $ouDistinguishedName = "OU=$($ou.name),$resolvedPath"
                    
                    Write-TierModelLog -Level Debug -Message "OuExistCheck" -Data @{
                        Name = $ou.name
                        DistinguishedName = $ouDistinguishedName
                        ResolvedPath = $resolvedPath
                        CorrelationId = $CorrelationId
                    } | Out-Null
                    
                    # Test OU existence
                    $existenceTest = Test-TierModelOuExists -DistinguishedName $ouDistinguishedName -DomainController $DomainController
                    
                    if (-not $existenceTest.Exists) {
                        Write-TierModelLog -Level Info -Message "OuExistCheck" -Data @{
                            Name = $ou.name
                            DistinguishedName = $ouDistinguishedName
                            Exists = $false
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        
                        # Create a copy of the OU data with corrected path for AD operations
                        $ouDataForCreation = $ou.PSObject.Copy()
                        $ouDataForCreation | Add-Member -NotePropertyName 'correctedPath' -NotePropertyValue $resolvedPath -Force
                        
                        $actions += [PSCustomObject]@{
                            Action = 'CreateOU'
                            ResourceType = 'OrganizationalUnit'
                            Name = $ou.name
                            Path = $resolvedPath
                            Data = $ouDataForCreation
                        }
                    } else {
                        Write-TierModelLog -Level Info -Message "OuExistCheck" -Data @{
                            Name = $ou.name
                            DistinguishedName = $ouDistinguishedName
                            Exists = $true
                            CorrelationId = $CorrelationId
                        } | Out-Null
                        
                        # Check if existing OU requires GPO inheritance blocking configuration
                        if ($ou.PSObject.Properties['blockGpoInheritance'] -and $ou.blockGpoInheritance -eq $true) {
                            try {
                                $gpInherit = Get-GPInheritance -Target $ouDistinguishedName -Server $DomainController -ErrorAction SilentlyContinue
                                if ($gpInherit -and $gpInherit.GpoInheritanceBlocked -ne $true) {
                                    $ouDataForConfig = $ou.PSObject.Copy()
                                    $ouDataForConfig | Add-Member -NotePropertyName 'correctedPath' -NotePropertyValue $resolvedPath -Force
                                    $ouDataForConfig | Add-Member -NotePropertyName 'distinguishedName' -NotePropertyValue $ouDistinguishedName -Force
                                    
                                    $actions += [PSCustomObject]@{
                                        Action = 'ConfigureOU'
                                        ResourceType = 'OrganizationalUnit'
                                        Name = $ou.name
                                        Path = $resolvedPath
                                        Data = $ouDataForConfig
                                    }
                                }
                            } catch { }
                        }
                    }
                } catch {
                    $errorMsg = "Failed to analyze OU '$($ou.name)': $($_.Exception.Message)"
                    $errors += @{
                        Timestamp = Get-Date
                        Category = 'External'
                        Code = 'OuAnalysisFailed'
                        Message = $errorMsg
                        Context = @{
                            OUName = $ou.name
                            Exception = $_.Exception.Message
                        }
                    }
                    Write-TierModelLog -Level Error -Message "OU analysis failed" -Data @{
                        OUName = $ou.name
                        Exception = $_.Exception.Message
                        CorrelationId = $CorrelationId
                    }
                }
            }
        }
        
        # Build summary
        $totalInConfig = if ($Config.PSObject.Properties['organizationUnits'] -and $Config.organizationUnits) { 
            @($Config.organizationUnits).Count 
        } else { 
            0 
        }
        $toCreate = @($actions | Where-Object { $_.Action -eq 'CreateOU' }).Count
        $existingCount = $totalInConfig - $toCreate
        
        $summary = @{
            TotalInConfig = $totalInConfig
            ToCreate = $toCreate
            ExistingCount = $existingCount
        }
        
        Write-TierModelLog -Level Info -Message "OuPlanComplete" -Data @{
            Summary = $summary
            ActionCount = $actions.Count
            WarningCount = $warnings.Count
            ErrorCount = $errors.Count
            CorrelationId = $CorrelationId
        } | Out-Null
        
        $result = [PSCustomObject]@{
            Actions = $actions
            Summary = $summary
            Warnings = $warnings
            Errors = $errors
            CorrelationId = $CorrelationId
        }
        
        if ($IncludeDetails) {
            $result | Add-Member -NotePropertyName 'Ordering' -NotePropertyValue $ordering
        }
        
        return $result
        
    } catch {
        $errors += @{
            Timestamp = Get-Date
            Category = 'Execution'
            Code = 'OuPlanFailed'
            Message = "OU plan generation failed: $($_.Exception.Message)"
            Context = @{
                Exception = $_.Exception.Message
            }
        }
        Write-TierModelLog -Level Error -Message "OU plan generation failed" -Data @{
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        }
        
        return [PSCustomObject]@{
            Actions = @()
            Summary = @{ TotalInConfig = 0; ToCreate = 0; ExistingCount = 0 }
            Warnings = $warnings
            Errors = $errors
            CorrelationId = $CorrelationId
        }
    }
}