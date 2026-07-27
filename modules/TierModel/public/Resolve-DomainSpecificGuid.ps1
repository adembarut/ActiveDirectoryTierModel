function Resolve-DomainSpecificGuid {
    <#
    .SYNOPSIS
    Resolves domain-specific attribute or class GUIDs by querying the Active Directory schema.
    
    .DESCRIPTION
    Some attributes like BitLocker recovery passwords, LAPS passwords, or dMSA classes have GUIDs 
    that are specific to each domain/forest. This function queries the domain's schema to resolve 
    these attribute or class names to their actual GUIDs at runtime. Returns $null cleanly if not found.
    
    .PARAMETER AttributeName
    The schema attribute or class name to resolve (e.g., "msFVE-RecoveryPassword", "ms-Mcs-AdmPwd",
    "msDS-DelegatedManagedServiceAccount").
    
    .PARAMETER ConfigPath
    The configuration path, used to determine domain controller if needed.
    
    .PARAMETER DomainController
    Optional domain controller to use for the schema query. If not provided, will use 
    the default domain controller.
    
    .PARAMETER SchemaObjectClass
    The schema object class to search within. Default is 'attributeSchema'.
    Use 'classSchema' when resolving object class GUIDs (e.g., for dMSA).
    
    .OUTPUTS
    String representing the resolved GUID, or $null if attribute is not found in schema.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$AttributeName,
        
        [Parameter()]
        [string]$ConfigPath,
        
        [Parameter()]
        [string]$DomainController,
        
        [Parameter()]
        [ValidateSet('attributeSchema', 'classSchema')]
        [string]$SchemaObjectClass = 'attributeSchema'
    )
    
    try {
        if (-not $DomainController) {
            $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
            $DomainController = $domain.PdcRoleOwner.Name
        }
        
        $schemaDN = (Get-ADRootDSE -Server $DomainController -ErrorAction Stop).schemaNamingContext
        
        $searchFilter = "(&(objectClass=$SchemaObjectClass)(ldapDisplayName=$AttributeName))"
        $searcher = New-Object System.DirectoryServices.DirectorySearcher
        $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainController/$schemaDN")
        $searcher.Filter = $searchFilter
        $searcher.PropertiesToLoad.Add("schemaIDGUID") | Out-Null
        
        $result = $searcher.FindOne()
        
        if ($result -and $result.Properties["schemaIDGUID"] -and $result.Properties["schemaIDGUID"].Count -gt 0) {
            $guidBytes = $result.Properties["schemaIDGUID"][0]
            $guid = [System.Guid]::new($guidBytes)
            return $guid.ToString()
        }
        
        return $null
        
    } catch {
        Write-TierModelLog -Level Debug -Message "Failed to resolve domain-specific GUID for attribute $AttributeName" -Data @{
            AttributeName = $AttributeName
            Exception = $_.Exception.Message
        } | Out-Null
        return $null
    }
}