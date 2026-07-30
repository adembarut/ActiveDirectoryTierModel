[cmdletbinding(SupportsShouldProcess=$true)]
Param (
    [Parameter (Mandatory=$false)]
    [String]$TieredComputerGroupName  = "Tier1PAWDevices",

    [Parameter(Mandatory=$false)]
    [string]$ParentOU,

    [Parameter(Mandatory=$false)]
    [string]$TieredComputerOU,

    [Parameter(Mandatory=$false)]
    [string]$KerberosPolicyName = "*- Tier 1 Authentication Silo",

    [Parameter(Mandatory=$false)]
    [string]$ExcludeComputer = "",

    [Parameter(Mandatory=$false)]
    [string]$ExcludeGroupName = "Tier 1 AuthSilo Excluded Devices,Tier 1 AuthSilo Excluded Accounts",

    [Parameter (Mandatory=$false)]
    [bool]$MultiDomainForest = $false
)

<#
.Synopsis
    This scripts is meant to maintain the Tier 1 PAW Devices group membership in order to support Authentication Silo policies

.DESCRIPTION
    The script will get all computer objects under the Tier 1 PAW Devices OU and add them to the Tier1PawDevices group. The group is part of an authentication silo policy.

.EXAMPLE
	.\Update-Tier1PAWDevices.ps1

.EXAMPLE
	.\Update-Tier1PAWDevices.ps1 -MultiDomainForest $true
    
.PARAMETER Tier1ComputerGroupName
    Name of the Group that contains all Tier 1 Computers objects

.PARAMETER Tier1ComputerOU
    The relative DistinguishedName of the Tier 1 computer OU path

.PARAMETER MultiDomainForest
    If the value is $true, the script will search for the Tier 1 computer OU in all domains of the forest. If the value is $false, the script will search for the Tier 1 computer OU in the current domain only.    

.NOTES
    This sample script is not supported under any Microsoft standard support program or service. 
    The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims 
    all implied warranties including, without limitation, any implied warranties of merchantability 
    or of fitness for a particular purpose. The entire risk arising out of the use or performance of 
    the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, 
    or anyone else involved in the creation, production, or delivery of the scripts be liable for any 
    damages whatsoever (including, without limitation, damages for loss of business profits, business 
    interruption, loss of business information, or other pecuniary loss) arising out of the use of or 
    inability to use the sample scripts or documentation, even if Microsoft has been advised of the 
    possibility of such damages
#>

# Function to write to the Event Log
function Write-Log {
    param (
        [Parameter(Mandatory=$false)]
        [AllowEmptyString()]
        [string]
        $Message = "",
        
        [Parameter (Mandatory = $true)]
        [Validateset('Error', 'Warning', 'Information', 'Debug') ]
        $Severity
    )
    #Format the log message and write it to the log file
    $LogLine = "$(Get-Date -Format o), [$Severity], $Message"
    Add-Content -Path $LogFile -Value $LogLine 
    switch ($Severity) {
        'Error'   { 
            Write-Host $Message -ForegroundColor Red
            Add-Content -Path $LogFile -Value $Error[0].ScriptStackTrace  
        }
        'Warning' { Write-Host $Message -ForegroundColor Yellow}
        'Information' { Write-Host $Message }
    }
}

#######################################################
# Main Program starts here                            #
#######################################################

#region Manage log file
[int]$MaxLogFileSize = 1048576 #Maximum size of the log file
$LogFile = "$($env:LOCALAPPDATA)\$($MyInvocation.MyCommand).log" #Name and path of the log file
#rename existing log files to *.sav if the currentlog file exceed the size of $MaxLogFileSize
if (Test-Path $LogFile){
    if ((Get-Item $LogFile ).Length -gt $MaxLogFileSize){
        if (Test-Path "$LogFile.sav"){
            Remove-Item "$LogFile.sav"
        }
        Rename-Item -Path $LogFile -NewName "$logFile.sav"
    }
}
#endregion
if ([string]::IsNullOrWhiteSpace($MyInvocation.Line)) {
    Write-Log -Message "Executing $($MyInvocation.MyCommand.Name)" -Severity Debug
} else {
    Write-Log -Message $MyInvocation.Line -Severity Debug
}

# Dynamic ParentOU & Root OU Resolution
if ($PSBoundParameters.ContainsKey('ParentOU') -eq $false -and [string]::IsNullOrWhiteSpace($ParentOU)) {
    try {
        if ([bool](Get-ADOrganizationalUnit -Filter "Name -eq 'TierModel'")) {
            $ParentOU = "TierModel"
        } elseif ([bool](Get-ADOrganizationalUnit -Filter "Name -eq '_TierModel'")) {
            $ParentOU = "_TierModel"
        } else {
            $ParentOU = ""
        }
    } catch {
        $ParentOU = ""
    }
}

$ParentPrefix = if ([string]::IsNullOrWhiteSpace($ParentOU)) { "" } else { ",OU=$($ParentOU.Trim())" }

if ([string]::IsNullOrWhiteSpace($TieredComputerOU)) {
    $TieredComputerOU = "OU=Tier 1 PAW Devices,OU=Tier 1,OU=Tier Model Administration${ParentPrefix}"
}

#for compatibility reason the Domain component will be removed from the OU path
$aryTier1Computer = @()
Foreach ($T0OU in $TieredComputerOU.Split(";")){
    $aryTier1Computer += [regex]::Replace($T0OU,",DC=.+","")
}
#searching for the T0 computers group in all domains
try{
    $adoGroup = Get-ADObject -Filter {(SamaccountName -eq $TieredComputerGroupName) -and (Objectclass -eq "Group")} -Properties member
}
catch [Microsoft.ActiveDirectory.Management.ADServerDownException]{
    Write-Log "The AD web service is not available. The group $TieredComputerGroupName cannot be updates" -Severity Error
    Write-EventLog -LogName "Application" -source "Application" -EventId 0 -EntryType Error -Message "The AD web service is not available. The group $Tier1ComputerGorupName cannot be updates"
    exit 0x3E9
}
if ($null -eq $adoGroup){
    Write-Log "Tier 1 computer management: Can't find the group $TieredComputerGroupName in the current domain. Script aborted" -Severity Error
    Write-Eventlog -LogName "Application" -Source "Application" -EventId 0 -EntryType Error -Category 1 -Message "Tier 1 computer management: Can't find the group $TieredComputerGroupName in the current domain. Script aborted"
    exit 0x3E8
}

#on multi domain mode write all domains into the array otherwise us the current domain name
if ($MultiDomainForest -eq $false){
    $domains = (Get-ADDomain).DNSRoot
} else {
    $domains = (Get-ADForest).Domains
}
$bGroupMemberchanged = $false
Foreach ($OU in $aryTier1Computer){
    Foreach ($domain in $domains){
        #validate the Tier 1 OU path
        try {
            if ($null -eq (Get-ADObject "$OU,$((Get-ADDomain -Server $domain).DistinguishedName)" -Server $domain)){
                Write-Log "Missing the Tier 1 computer OU $OU,$((Get-ADDomain -Server $domain).DistinguishedName)" -Severity Warning
                Write-EventLog -LogName "Application" -source "Application" -EventId 0 -EntryType Error -Message "Missing the Tier 1 computer OU $OU,$((Get-ADDomain -Server $domain).DistinguishedName)"
            } else{
                $T0computers = @(Get-ADComputer -SearchBase "$OU,$((Get-ADDomain -Server $domain).DistinguishedName)" -Filter * -Properties msDS-AssignedAuthNPolicy,msDS-AssignedAuthNPolicySilo,MemberOf -SearchScope Subtree -Server $domain)
                #validate the computers in the Tier 1 OU are members of the Tier 1 computers group
                Write-Log -Message "Found $($T0computers.Count) Tier 1 computers in $domain" -Severity Debug
                Foreach ($T0Computer in $T0computers){
                    # Check if computer is explicitly excluded by name or group membership
                    $isExcluded = $false
                    if ($ExcludeComputer) {
                        foreach ($exName in ($ExcludeComputer -split ',')) {
                            if ($exName -and ($T0Computer.SamAccountName -ieq $exName.Trim() -or $T0Computer.Name -ieq $exName.Trim() -or $T0Computer.DistinguishedName -ilike "*$($exName.Trim())*")) {
                                $isExcluded = $true; break
                            }
                        }
                    }
                    if (-not $isExcluded -and $ExcludeGroupName -and $T0Computer.MemberOf) {
                        foreach ($exGroup in ($ExcludeGroupName -split ',')) {
                            if ($exGroup -and ($T0Computer.MemberOf -match "(?i)CN=$($exGroup.Trim()),")) {
                                $isExcluded = $true; break
                            }
                        }
                    }
                    if ($isExcluded) {
                        Write-Log "Skipping excluded computer $($T0Computer.DistinguishedName) from AuthSilo enforcement" -Severity Information
                        try {
                            Revoke-ADAuthenticationPolicySiloAccess -Identity $KerberosPolicyName -Account $T0Computer -Server $domain -ErrorAction SilentlyContinue | Out-Null
                            Set-ADComputer $T0Computer -AuthenticationPolicy $null -Server $domain -Confirm:$false -ErrorAction SilentlyContinue
                            Set-ADAccountAuthenticationPolicySilo -Identity $T0Computer.DistinguishedName -RemoveAuthenticationPolicySilo -Server $domain -Confirm:$false -ErrorAction SilentlyContinue
                        } catch { }
                        continue
                    }

                    if ($adoGroup.member -notcontains $T0Computer.DistinguishedName){
                        $adoGroup.member += $T0Computer.DistinguishedName
                        $bGroupMemberchanged = $true
                        Write-Log "Added $($T0Computer.Name) to $($adoGroup.Name)" -Severity Information
                        Write-EventLog -LogName "Application" -source "Application" -EventID 0 -EntryType information -Message "Added $($T0Computer.Name) to $($adoGroup.Name)"
                    }
                    # Grant Silo access (Permitted Accounts)
                    try {
                        Grant-ADAuthenticationPolicySiloAccess -Identity $KerberosPolicyName -Account $T0Computer.DistinguishedName -Server $domain -ErrorAction SilentlyContinue | Out-Null
                    } catch { }
                    # Assign Authentication Policy to the computer object (Required for ADAC Accounts tab visibility)
                    try {
                        $targetPolicyDN = (Get-ADAuthenticationPolicy -Identity $KerberosPolicyName -Server $domain).DistinguishedName
                        if ($T0Computer.'msDS-AssignedAuthNPolicy' -ne $targetPolicyDN) {
                            Set-ADComputer $T0Computer -AuthenticationPolicy $KerberosPolicyName -Server $domain -Confirm:$false
                            Write-Log "Assigned Kerberos AuthN Policy '$KerberosPolicyName' to $($T0Computer.Name)" -Severity Information
                        }
                    } catch {
                        Write-Log "Could not assign AuthN Policy to $($T0Computer.Name): $($_.Exception.Message)" -Severity Warning
                    }
                    # Assign Authentication Policy Silo to the computer object
                    try {
                        $targetSiloDN = (Get-ADAuthenticationPolicySilo -Identity $KerberosPolicyName -Server $domain).DistinguishedName
                        if ($T0Computer.'msDS-AssignedAuthNPolicySilo' -ne $targetSiloDN) {
                            Set-ADAccountAuthenticationPolicySilo -Identity $T0Computer.DistinguishedName -AuthenticationPolicySilo $KerberosPolicyName -Server $domain -Confirm:$false
                            Write-Log "Assigned AuthSilo '$KerberosPolicyName' to $($T0Computer.Name)" -Severity Information
                        }
                    } catch {
                        Write-Log "Could not assign AuthSilo to $($T0Computer.Name): $($_.Exception.Message)" -Severity Warning
                    }
                }
            }
        }
        catch [Microsoft.ActiveDirectory.Management.ADServerDownException]{
            Write-Log "The domain $domain WebService is down or not reachable" -Severity Error
            Write-EventLog -LogName "Application" -Source "Application" -EventID 0 -EntryType Warning -Message "The domain $domain WebService is down or not reachable"
        }
    }
}
try{
    if ($bGroupMemberchanged){
        Set-ADObject -Instance $adoGroup    
        Write-Log "Adding new computers to the Tier 1 computer group" -Severity Debug
        $bGroupMemberchanged = $false
    }
    #remove any object from Tier 1 computer group who is not member of the Tier 1 computers list
    $updatedGroupMembers = @()
    Foreach ($member in ($adoGroup.member)){
        $isMember = $false
        foreach ($ComputerOU in $aryTier1Computer){
            if ($member -like "*$ComputerOU*"){
                $isMember = $true
                break
            }
        }
        if ($isMember){
            $updatedGroupMembers += $member
        } else {
            Write-Log "Unexpected computer object $member removed from $($adoGroup.DistinguishedName)" -Severity Warning
            Write-EventLog -LogName "Application" -source "Application" -EventID 0 -EntryType Warning -Message "Unexpected computer object $member removed from $($adoGroup.DistinguishedName)"
            $bGroupMemberchanged = $true
            # Also revoke Silo access for computers removed from the OU scope
            try {
                Revoke-ADAuthenticationPolicySiloAccess -Identity $KerberosPolicyName -Account $member -ErrorAction SilentlyContinue | Out-Null
                Write-Log "Revoked AuthSilo access for $member" -Severity Information
            } catch { }
        }
    }
    if ($bGroupMemberchanged){
        $adoGroup.member = $updatedGroupMembers
        Set-ADObject -Instance $adoGroup
        Write-Log "Removing non-Tier 1 computers from the Tier 1 computer group" -Severity Debug
    }
}
catch [Microsoft.ActiveDirectory.Management.ADServerDownException]{
    Write-Log "The AD web service is not available. The group $adogroup cannot be updates"
    Write-EventLog -LogName "Application" -source "Application" -EventId 0 -EntryType Error -Message "The AD web service is not available. The group $adogroup cannot be updates"
    exit 0x3E9
}
