function Resolve-TierModelPlaceholder {
    <#
    .SYNOPSIS
    Generic placeholder replacement for TierModel path resolution with ParentOU support.
    
    .DESCRIPTION
    Handles {{DOMAIN_DN}} and other common placeholder patterns used
    across different TierModel entity types (OUs, Groups, Users, etc.).
    Smartly prevents duplicate ParentOU nesting and handles built-in containers properly.
    
    .PARAMETER Path
    Original path from configuration that may contain placeholders.
    
    .PARAMETER DomainDN
    Resolved domain distinguished name for replacement.
    
    .PARAMETER ParentOU
    Optional parent OU name or path to prefix before domain DN.
    
    .OUTPUTS
    String containing the resolved path with placeholders replaced.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$DomainDN,
        
        [Parameter()]
        [string]$ParentOU
    )
    
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Trim() -ieq '{{DOMAIN_DN}}') {
        if (-not [string]::IsNullOrWhiteSpace($ParentOU)) {
            $parentName = ($ParentOU.Trim() -replace '^(OU|CN)=', '').Trim()
            return "OU=$parentName,$DomainDN"
        }
        return $DomainDN
    }
    
    # 1. Replace {{DOMAIN_DN}} with $DomainDN
    $workPath = $Path -replace '\{\{DOMAIN_DN\}\}', $DomainDN
    
    # 2. Check if Path refers to a built-in container (e.g. Domain Controllers, Users, Computers, Builtin)
    $isBuiltInContainer = ($workPath -match "(?i)^(OU=Domain Controllers|CN=Users|CN=Computers|CN=Builtin)\b")
    
    if ($isBuiltInContainer) {
        if ($workPath -match "(?i)^(OU=Domain Controllers|CN=Users|CN=Computers|CN=Builtin)") {
            $containerPart = $matches[0]
            return "$containerPart,$DomainDN"
        }
    }
    
    # 3. Handle ParentOU for non-builtin paths
    if (-not [string]::IsNullOrWhiteSpace($ParentOU)) {
        $trimmedParent = $ParentOU.Trim()
        $parentName = ($trimmedParent -replace '^(OU|CN)=', '').Trim()
        
        # If workPath contains hardcoded default 'OU=_TierModel', replace it with 'OU=<parentName>'
        if ($workPath -match '(?i)OU=_TierModel\b') {
            $workPath = $workPath -replace '(?i)OU=_TierModel\b', "OU=$parentName"
        } elseif ($workPath -notmatch "(?i)OU=$parentName\b") {
            # Append/insert OU=<parentName> if not already present
            if ($workPath -match "(?i),\s*$DomainDN`$") {
                $workPath = $workPath -replace "(?i),\s*$DomainDN`$", ",OU=$parentName,$DomainDN"
            } elseif ($workPath -notmatch 'DC=') {
                $workPath = "$workPath,OU=$parentName"
            }
        }
    } else {
        # ParentOU is empty - strip hardcoded 'OU=_TierModel' from path if present
        $workPath = $workPath -replace '(?i),?\s*OU=_TierModel\b', ''
    }
    
    # Clean up trailing commas and attach DomainDN if not present
    $workPath = $workPath.TrimEnd(',')
    if ($workPath -notmatch 'DC=') {
        $workPath = "$workPath,$DomainDN"
    }
    
    # Deduplicate consecutive ParentOU segments if any exist (e.g. OU=CustomOU,OU=CustomOU -> OU=CustomOU)
    if (-not [string]::IsNullOrWhiteSpace($ParentOU)) {
        $parentName = ($ParentOU.Trim() -replace '^(OU|CN)=', '').Trim()
        $dupPattern = "(?i)(OU=$parentName\s*,\s*)+OU=$parentName"
        $workPath = $workPath -replace $dupPattern, "OU=$parentName"
    }
    
    return $workPath
}