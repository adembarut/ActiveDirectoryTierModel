function Set-TierModelGpoComment {
    <#
    .SYNOPSIS
    Set GPO Comment (Description) in GPMC.
    
    .DESCRIPTION
    Sets the GPO Comment (Description) property in Active Directory via the GPMC COM API
    (GPMgmt.GPM) using exact GUID lookup so it is properly persisted and visible in the GPMC Details tab.
    
    .PARAMETER GpoName
    DisplayName of the Group Policy Object.
    
    .PARAMETER Comment
    The comment text to set on the GPO.
    
    .PARAMETER DomainController
    Preferred domain controller for operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GpoName,
        
        [Parameter(Mandatory)]
        [string]$Comment,
        
        [Parameter(Mandatory)]
        [string]$DomainController
    )
    
    if ([string]::IsNullOrWhiteSpace($Comment)) { return }
    
    try {
        # Find GPO using Get-GPO to get its exact GUID
        $gpo = Get-GPO -Name $GpoName -Server $DomainController -ErrorAction SilentlyContinue
        if (-not $gpo) {
            Write-TierModelLog -Level Warning -Message "Get-GPO could not find GPO '$GpoName'" | Out-Null
            return $false
        }
        
        $guidStr = '{' + $gpo.Id.ToString().ToUpper() + '}'
        
        $domain = Get-ADDomain -Server $DomainController
        $domainName = $domain.DNSRoot
        
        $gpm = New-Object -ComObject GPMgmt.GPM
        $gpmDomain = $gpm.GetDomain($domainName, "", 0)
        $gpmGpo = $gpmDomain.GetGPO($guidStr)
        
        if ($gpmGpo) {
            $gpmGpo.Description = $Comment
            Write-TierModelLog -Level Info -Message "Successfully set GPO Description for $GpoName ($guidStr)" | Out-Null
            return $true
        } else {
            Write-TierModelLog -Level Warning -Message "GPMC COM GetGPO returned null for GUID $guidStr" | Out-Null
            return $false
        }
    } catch {
        Write-TierModelLog -Level Warning -Message "Failed to set GPO Comment for ${GpoName}: $($_.Exception.Message)" | Out-Null
        return $false
    }
}
