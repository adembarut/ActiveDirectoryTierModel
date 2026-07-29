param (
    [string]$DomainController,
    [string]$ParentOU = "TierModel"
)

# Required Modules
Import-Module ActiveDirectory

# Get current domain
$ADParams = @{}
if ($DomainController) { $ADParams['Server'] = $DomainController }
$Domain = Get-ADDomain @ADParams
$DomainDN = $Domain.DistinguishedName

$TargetDN = if ($ParentOU -and $ParentOU.Trim()) { "OU=$ParentOU,$DomainDN" } else { $DomainDN }

Write-Host "Applying SACL Audit Rules to: $TargetDN" -ForegroundColor Cyan

# Get current ACL
$ACL = Get-Acl "AD:$TargetDN"

# Define Auditing Permissions (excluding noise rights)
$AuditRights = [System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::Self -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::Delete -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::DeleteTree -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::WriteDacl -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::WriteOwner -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight

# Define Audit Rule
$AuditRule = New-Object System.DirectoryServices.ActiveDirectoryAuditRule(
    [System.Security.Principal.NTAccount]("Everyone"),
    $AuditRights,
    [System.DirectoryServices.ActiveDirectorySecurityInheritance]"All",
    [System.Security.AccessControl.AuditFlags]::Success
)

# Apply Audit Rule to the OU
$ACL.AddAuditRule($AuditRule)

# Set the new ACL
Set-Acl -Path "AD:$TargetDN" -AclObject $ACL
Write-Host "✅ Active Directory SACL auditing successfully applied to $TargetDN" -ForegroundColor Green