param (
    [bool]$RedirectUsers = $false,
    [bool]$RedirectComputers = $false,
    [string]$ParentOU = "TierModel"
)

<#
.SYNOPSIS
    This script redirects default Computer and User containers to Tier Model specific OUs.

.DESCRIPTION
    Directs default User container to Enabled End-Users Accounts OU and default Computer 
    container to Tier Model Computer Quarantine OU under the specified ParentOU.

.PARAMETER RedirectUsers
    Redirect default User Container to Tier 2 Enabled End-Users Accounts OU.

.PARAMETER RedirectComputers
    Redirect default Computer Container to Tier Model Computer Quarantine OU.

.PARAMETER ParentOU
    Optional parent OU name under which TierModel OUs reside (e.g. 'TierModel').

.EXAMPLE
    .\Redirect-DefaultContainers.ps1 -RedirectUsers $true -RedirectComputers $true -ParentOU "TierModel"
#>

Import-Module ActiveDirectory

$Domain = Get-ADDomain
$DomainDN = $Domain.DistinguishedName

# Resolve Parent OU prefix
$ParentPrefix = if ($ParentOU -and $ParentOU.Trim()) { "OU=$ParentOU," } else { "" }

if ($RedirectUsers) {
    # Redirecting User Container to active end-user accounts OU
    $UserOU = "OU=Enabled End-Users Accounts,OU=Tier 2 End-User Accounts,${ParentPrefix}${DomainDN}"
    Write-Host "Redirecting default User container (redirusr) to: $UserOU" -ForegroundColor Cyan
    redirusr $UserOU
}

if ($RedirectComputers) {
    # Redirecting Computer Container to computer quarantine OU
    $ComputerOU = "OU=Tier Model Computer Quarantine,${ParentPrefix}${DomainDN}"
    Write-Host "Redirecting default Computer container (redircmp) to: $ComputerOU" -ForegroundColor Cyan
    redircmp $ComputerOU
}
