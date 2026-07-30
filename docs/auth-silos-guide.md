# 🛡️ Kerberos Authentication Policy Silos Architecture & Administration Guide

This guide provides a comprehensive technical overview of the **Kerberos Authentication Policy Silos** implemented in the Active Directory Tier Model framework, explaining its underlying architecture, security mechanisms, exclusion controls, dual-attribute policy assignments, and day-to-day administrative procedures.

---

## 🏛️ Architecture Overview & How It Works

Kerberos Authentication Policy Silos provide **protocol-level boundary enforcement** (Zero Trust) for privileged Active Directory accounts. Even if a Tier 0 or Tier 1 administrator's password is breached or typed on an untrusted device, Active Directory Domain Controllers (KDCs) will reject Kerberos ticket requests (TGT) unless authentication originates from a verified, authorized tier endpoint.

```
+-----------------------------------------------------------------------------------+
|                           Kerberos AuthSilo Protection                            |
|                                                                                   |
|  [ Tier 0 Admin Account ] --(1. Auth Request)--> [ Domain Controller KDC ]        |
|                                                          |                        |
|                                                (2. Evaluates SDDL)                |
|                                                          |                        |
|        +-------------------------------------------------+                        |
|        |                                                 |                        |
|  [ Authorized Endpoint ]                       [ Untrusted Endpoint ]             |
|  - Domain Controller                           - Tier 2 Workstation               |
|  - Tier 0 PAW Device                           - Personal Laptop / VPN            |
|  - Tier 0 Member Server                        - External Web Server              |
|        |                                                 |                        |
|        v                                                 v                        |
|  ✅ TGT Issued (240 mins)                       ❌ Authentication Blocked         |
|                                                   (Event ID 4818 in Audit Mode)   |
+-----------------------------------------------------------------------------------+
```

---

## 🔑 Key Architectural Components

### 1. Kerberos TGT Lifetime Restriction (240 Minutes / 4 Hours)
* Standard Kerberos ticket (TGT) validity in Active Directory is 10 hours.
* AuthSilo reduces TGT lifetime for Tier 0 and Tier 1 accounts to **240 minutes (4 hours)**.
* This drastically shortens the window of opportunity for Pass-the-Ticket (PtT) and Golden Ticket attacks.

### 2. Device Access Control via SDDL Claims
Authentication Policy SDDL rules enforce device binding:
* **Tier 0 AuthSilo Policy:** Users assigned to this policy can **ONLY** authenticate from:
  * `Enterprise Domain Controllers` (SID: `ED`)
  * `Tier 0 PAW Devices` (`SEC2TRUST\Tier0PAWDevices`)
  * `Tier 0 Member Servers` (`SEC2TRUST\Tier0MemberServers`)
* **Tier 1 AuthSilo Policy:** Users assigned to this policy can **ONLY** authenticate from:
  * `Tier 1 PAW Devices` (`SEC2TRUST\Tier1PAWDevices`)
  * `Tier 1 Member Servers` (`SEC2TRUST\Tier1MemberServers`)

### 3. Dual-Attribute Policy Assignment (ADAC Accounts Tab Visibility)
To ensure both User and Computer objects render cleanly inside the **Accounts** and **Permitted Accounts** tabs of Active Directory Administrative Center (ADAC):
* **`msDS-AssignedAuthNPolicySilo`**: Links the object to the Silo container.
* **`msDS-AssignedAuthNPolicy`**: Links the object to the Kerberos Authentication Policy.
* **`msDS-AuthNPolicySiloMembers`**: Added via `Grant-ADAuthenticationPolicySiloAccess`.

### 4. Safe Operating Modes: Audit Mode vs. Enforce Mode
* **Audit Mode (`Enforce = $false`):** Default deployment state. Domain Controllers evaluate AuthSilo policies and write Event Log entries (**Event ID 4818**) when unauthorized devices attempt authentication, without blocking real-time user logins.
* **Enforce Mode (`Enforce = $true`):** Active enforcement state. Domain Controllers actively reject TGT requests originating from non-authorized endpoints.

---

## 🛡️ Exclusion & Disaster Recovery Architecture

To prevent administrative lockout during emergencies or PKI/ADFS outages, a multi-layered exclusion architecture is built into the module:

### 1. Disaster Recovery Account Exclusion (`BreakGlassAdmin`)
* **`BreakGlassAdmin`** is explicitly excluded by default from AuthSilo assignment (`msDS-AssignedAuthNPolicy`) and the `Protected Users` group.
* **Why?** If PKI or SmartCard authentication services fail, administrators can retrieve the `BreakGlassAdmin` password from physical vault storage and log into Domain Controllers using NTLM/password fallback.

### 2. Group-Based Exclusion Management & Automatic Lifecycle
Dedicated security groups are provisioned in Active Directory to allow dynamic exclusion without modifying code:
* **`Tier 0 AuthSilo Excluded Accounts`** (`OU=Admins,OU=Tier 0 Groups...`)
* **`Tier 0 AuthSilo Excluded Devices`** (`OU=Admins,OU=Tier 0 Groups...`)
* **`Tier 1 AuthSilo Excluded Accounts`** (`OU=Admins,OU=Tier 1 Groups...`)
* **`Tier 1 AuthSilo Excluded Devices`** (`OU=Admins,OU=Tier 1 Groups...`)

#### Automatic Revocation & Re-Enforcement Lifecycle:
* **Exclusion Addition:** When an account or device is added to an exclusion group, the next maintenance script run automatically detects membership, **revokes Silo access (`Revoke-ADAuthenticationPolicySiloAccess`)**, and **clears policy links (`Set-ADAccountAuthenticationPolicySilo -Remove...`)**, immediately releasing the object from Silo TGT constraints.
* **Exclusion Removal:** When an object is removed from an exclusion group, the script automatically **re-enforces Silo membership, assigns policies, and restores full Tier protection.**

---

## 👨‍💼 Administrator Usage & Operations Guide

### Scenario 1: Onboarding a New Tier 0 Administrator

When a new Tier 0 administrator is hired or provisioned:

1. Create the user account inside `OU=Tier 0 Accounts,OU=Tier 0,OU=Tier Model Administration,OU=TierModel,DC=domain,DC=com`.
2. Add the user to the `Tier 0 Admins` security group.
3. Run the Tier 0 maintenance script (or wait for the 10-minute Task Scheduler job):
   ```powershell
   & "C:\Windows\SYSVOL\domain\scripts\TierModelAuthSilos\Update-Tier0AuthSiloUsers.ps1" -ParentOU "TierModel"
   ```
4. **Verification:** Confirm the user has `msDS-AssignedAuthNPolicy` set to `*- Tier 0 Authentication Silo`.

---

### Scenario 2: Excluding a User or Computer Object from AuthSilo Restrictions

If a user account or server within Tier 0 must be exempted from AuthSilo device restrictions during emergency maintenance:

1. Open **Active Directory Users and Computers (`dsa.msc`)** or **ADAC (`dsac.exe`)**.
2. Add the target user account to **`Tier 0 AuthSilo Excluded Accounts`** or target computer to **`Tier 0 AuthSilo Excluded Devices`**.
3. Run the maintenance script (or wait for Task Scheduler):
   ```powershell
   & "C:\Windows\SYSVOL\domain\scripts\TierModelAuthSilos\Update-Tier0AuthSiloUsers.ps1" -ParentOU "TierModel"
   & "C:\Windows\SYSVOL\domain\scripts\TierModelAuthSilos\Update-Tier0MemberServers.ps1" -ParentOU "TierModel"
   ```
4. **Result:** The script logs: `Skipping excluded user/computer CN=... from AuthSilo enforcement` and automatically revokes Silo policy links.

---

### Scenario 3: Disaster Recovery Procedure (`BreakGlassAdmin`)

In the event of a catastrophic PKI, ADFS, or AuthSilo outage:

1. Retrieve the physical vault password for **`BreakGlassAdmin`**.
2. Log into the Primary Domain Controller (`AD-DC-PRD-01`).
3. Since `BreakGlassAdmin` is excluded from AuthSilo policies, authentication succeeds directly via NTLM/Kerberos without device claims restriction.
4. Perform necessary break-fix operations.

---

### Scenario 4: Switching from Audit Mode to Enforce Mode

After reviewing Event Viewer logs (**Event ID 4818**) for 14-30 days and confirming no legitimate Tier 0/1 logins are being flagged as violations:

```powershell
# Switch Tier 0 AuthSilo to Enforce Mode
Set-ADAuthenticationPolicySilo -Identity "*- Tier 0 Authentication Silo" -Enforce $true -Server "AD-DC-PRD-01.sec2trust.com"

# Switch Tier 1 AuthSilo to Enforce Mode
Set-ADAuthenticationPolicySilo -Identity "*- Tier 1 Authentication Silo" -Enforce $true -Server "AD-DC-PRD-01.sec2trust.com"
```

---

### Scenario 5: Automated Maintenance via SYSVOL & Task Scheduler

Maintenance scripts are hosted directly in **SYSVOL** (`C:\Windows\SYSVOL\domain\scripts\TierModelAuthSilos\`) to ensure high-availability execution across all Domain Controllers:

```powershell
# Execute non-interactively via GPO Task Scheduler or direct PowerShell Task
powershell.exe -ExecutionPolicy Bypass -NoProfile -NonInteractive -File C:\Windows\SYSVOL\domain\scripts\TierModelAuthSilos\Update-Tier0AuthSiloUsers.ps1 -ParentOU TierModel
powershell.exe -ExecutionPolicy Bypass -NoProfile -NonInteractive -File C:\Windows\SYSVOL\domain\scripts\TierModelAuthSilos\Update-Tier0MemberServers.ps1 -ParentOU TierModel
```

---

## 📊 Summary Checklist for Administrators

| Task | Recommended Command / Action | Frequency |
| :--- | :--- | :--- |
| **Deploy AuthSilos** | `.\Deploy-TierModel.ps1 -IncludeAuthSilo -AuthSiloTaskMode GPO -ParentOU TierModel` | One-time post-deployment |
| **Sync Tier 0 Users** | `& C:\Windows\SYSVOL\domain\scripts\TierModelAuthSilos\Update-Tier0AuthSiloUsers.ps1 -ParentOU TierModel` | Automated (10 mins) |
| **Sync Tier 0 Computers**| `& C:\Windows\SYSVOL\domain\scripts\TierModelAuthSilos\Update-Tier0MemberServers.ps1 -ParentOU TierModel` | Automated (10 mins) |
| **Sync Tier 1 Users** | `& C:\Windows\SYSVOL\domain\scripts\TierModelAuthSilos\Update-Tier1AuthSiloUsers.ps1 -ParentOU TierModel` | Automated (10 mins) |
| **Sync Tier 1 Computers**| `& C:\Windows\SYSVOL\domain\scripts\TierModelAuthSilos\Update-Tier1MemberServers.ps1 -ParentOU TierModel` | Automated (10 mins) |
| **Audit Exclusions** | Check `msDS-AssignedAuthNPolicy` attribute on `BreakGlassAdmin` and Excluded Groups | Quarterly |
