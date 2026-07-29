# 🏛️ Tier Model (Microsoft EAM & Zero Trust Architecture)

Declarative PowerShell framework to deploy, audit, and maintain an Active Directory Tier Model (OUs, Groups, Users, ACL Delegations, GPOs, ADMX, MSA/gMSA/dMSA Permissions, Windows LAPS, and Kerberos Authentication Policy Silos) from a single version-controlled JSON configuration file. Supports idempotent re-runs, drift detection, and reproducible builds via pinned dependency versions.

> 🏗️ **Built with the Specify Framework** - Test-driven development ensuring enterprise quality and reliability.

---

## 🎯 Key Goals & Security Baseline
- 🔒 **Safe, Repeatable Deployments:** WhatIf planning + convergent apply across all 6 deployment phases.
- 🛡️ **Zero Trust Protocol Enforcement:** Kerberos AuthSilos (TGT 240m lifetime + SDDL device claim restrictions).
- 📊 **Drift Auditing & Compliance:** 100% hash provenance, multi-format audit reporting (Text, JSON, HTML, NUnit XML).
- ⚙️ **Dual-Mode Architecture:** Deploys seamlessly directly under **Domain Root** or under a **Custom Parent OU** (e.g. `-ParentOU TierModel`).
- 🧩 **Modular & Test-First:** 1,400+ automated Pester unit/integration test cases passing.

---

## 🌟 Major Architecture Enhancements

### 1. 📂 Expanded EAM Workload & OU Hierarchy
Fully aligned with Microsoft Enterprise Access Model (EAM) workload separation:
* **Tier 0 Member Servers Sub-OUs:** `Identity`, `Virtualization`, `Management`
* **Tier 1 Member Servers Sub-OUs:** `Application`, `Database`, `Collaboration`, `Messaging`
* **Tier 2 End-User Devices Sub-OUs:** `Desktops`, `Laptops`, `Kiosks`
* **Tier 2 End-User Accounts Sub-OUs:** `Enabled End-Users Accounts`, `Disabled End-Users Accounts`
* **Group Containers:** Dedicated `Admins` and `Operators` sub-OUs across Tier 0, Tier 1, and Tier 2.

### 2. 🚨 Disaster Recovery & Emergency Access (`BreakGlassAdmin`)
* Integrated **`BreakGlassAdmin`** user account and **`Break Glass Admins`** security group under Tier 0.
* **Out-of-Band Resilience:** `BreakGlassAdmin` is automatically **excluded** from Kerberos AuthSilo (`msDS-AssignedAuthNPolicy`) and `Protected Users` enforcement, allowing administrators to recover the forest during PKI/ADFS outages using vault passwords.

### 3. 🛡️ Group-Based AuthSilo Exclusion Management
* Created dedicated security groups: **`Tier 0 AuthSilo Excluded Accounts`** and **`Tier 1 AuthSilo Excluded Accounts`**.
* Maintenance scripts (`Update-Tier0AuthSiloUsers.ps1`, `Update-Tier1AuthSiloUsers.ps1`) automatically skip members of these groups from TGT 240m restrictions, enabling dynamic exclusion management without code edits.

### 4. 📝 146 GPO GPMC Comment System & Advanced Auditing
* All 146 GPOs feature multi-section administrative documentation (`PURPOSE`, `PLACEMENT RATIONALE`, `KEY SETTINGS`, `⚠️ PLACEHOLDER GPO NOTICE`).
* Comments are injected directly into the GPMC Details tab via `Set-TierModelGpoComment.ps1`.
* Enforces PowerShell Script Block Logging (Event ID 4104), Advanced Audit Policy for DCs, AppLocker Audit Mode, and Windows Defender Firewall Audit Mode.

---

## 📚 Documentation Links

> 📖 **Full Documentation**: [Active Directory Tier Model Docs](https://microsoft.github.io/ActiveDirectoryTierModel)

* **[Quick Deployment Guide](docs/quick-deployment-guide.md)** - Fast-track deployment for experienced administrators
* **[Detailed Deployment Guide](docs/detailed-deployment-guide.md)** - Step-by-step deployment with dual-mode `-ParentOU` explanations
* **[AuthSilo Administration Guide](docs/auth-silos-guide.md)** - Complete Kerberos AuthSilo architecture, TGT 240m enforcement, and exclusion operations
* **[Hybrid Cloud Entra Sync Guide](docs/hybrid-cloud-entra-sync.md)** - Entra ID Connect (Azure AD) OU filtering rules
* **[Drift Detection Details](docs/drift-detection-details.md)** - Compliance auditing and drift remediation
* **[FAQ](docs/faq.md)** - Upgrades, troubleshooting, and Sentinel integration

---

## 🛠️ Deployment & Maintenance Scripts

| Script | Purpose | Key Parameters & Switches |
| :--- | :--- | :--- |
| `Deploy-TierModel.ps1` | 🚀 Primary deployment orchestrator | `-ParentOU <Name>`, `-FullDeployment`, `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa`, `-IncludeWinLaps`, `-IncludeAuthSilo`, `-AuthSiloTaskMode GPO\|LocalTask\|Both` |
| `Audit-TierModel.ps1` | 📊 Drift detection & compliance audit | `-ParentOU <Name>`, `-FullDeployment`, `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa`, `-IncludeWinLaps` |
| `Deploy-TierModelAuthSilo.ps1` | 🛡️ Deploys Kerberos AuthSilos | `-PreferredDC <DC>` (Configures TGT 240m & SDDL Device Claim Binding) |
| `Update-Tier0AuthSiloUsers.ps1` | ⚡ Syncs Tier 0 users to AuthSilo | `-ParentOU <Name>`, `-ExcludeGroupName "Tier 0 AuthSilo Excluded Accounts"`, `-ExcludeTieredUser` |
| `Update-Tier1AuthSiloUsers.ps1` | ⚡ Syncs Tier 1 users to AuthSilo | `-ParentOU <Name>`, `-ExcludeGroupName "Tier 1 AuthSilo Excluded Accounts"`, `-ExcludeTieredUser` |
| `Set-TierModelGpoComment.ps1` | 📝 Injects GPO documentation | `-PreferredDc <DC>` (Writes multi-section comments to GPMC Details tab) |

---

## 🚀 Quick Execution Guide

### 1. Full Tier Model Deployment
```powershell
# Deploy full Tier Model infrastructure under 'TierModel' parent OU
.\Deploy-TierModel.ps1 -PreferredDc "AD-DC-PRD-01.sec2trust.com" -FullDeployment -ConfirmApply -IncludeGmsa -IncludeMsa -IncludeDmsa -IncludeWinLaps -ParentOU "TierModel"
```

### 2. Full Compliance & Drift Audit
```powershell
# Audit entire Tier Model deployment against configuration baselines
.\Audit-TierModel.ps1 -PreferredDc "AD-DC-PRD-01.sec2trust.com" -FullDeployment -IncludeGmsa -IncludeMsa -IncludeDmsa -IncludeWinLaps -ParentOU "TierModel"
```

### 3. Integrated Full Deployment with Kerberos AuthSilos & GPO Task Scheduler
```powershell
# Perform full TierModel deployment + Kerberos AuthSilos + GPO Task Scheduler automation in a single command
.\Deploy-TierModel.ps1 -PreferredDc "AD-DC-PRD-01.sec2trust.com" `
                       -FullDeployment `
                       -ConfirmApply `
                       -IncludeGmsa -IncludeMsa -IncludeDmsa -IncludeWinLaps `
                       -IncludeAuthSilo `
                       -AuthSiloTaskMode GPO `
                       -ParentOU "TierModel"
```

---

## 🧪 Testing & Quality Assurance

**Current Test Status: ✅ ALL TESTS PASSING**

| Test Suite | Test Files | Test Cases | Status | Coverage |
| :--- | :---: | :---: | :---: | :---: |
| **Unit Tests** | 17 files | 1,122 tests | ✅ 100% Pass | **90.92%** |
| **Integration Tests** | 7 files | 279 tests | ✅ 100% Pass | **100%** |
| **Manual Integration Tests** | 1 file | 331 tests | ✅ 100% Pass | **100%** |
| **Total** | **25 files** | **1,732 tests** | ✅ **All Passing** | **90.92%** |

### Running Tests
```powershell
# Run all Pester unit and integration tests
.\tests\Invoke-AllTests.ps1
```

---

## 📋 Prerequisites

- **PowerShell**: 7.0+
- **Privileges**: Elevated Domain Admin / Enterprise Admin privileges
- **Target DC**: Active Directory Domain Controller with Web Services enabled
- **Modules**: `ActiveDirectory`, `GroupPolicy` (managed dynamically)

---

**Version**: 1.4.0 | **License**: MIT | **Status**: ✅ Production Ready & Verified