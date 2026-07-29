# Hybrid Cloud Identity Sync Guide (Entra ID / Azure AD Connect)

## Overview

In modern Enterprise Access Model (EAM) deployments, Active Directory acts as an identity provider alongside Microsoft Entra ID (formerly Azure AD). To maintain strong security boundaries, **Domain Controllers, Tier 0 Admin Accounts, and Tier 0/1 Infrastructure objects MUST NEVER be synchronized to the cloud**.

---

## OU Synchronization Rules

### 🚫 DO NOT SYNCHRONIZE (Exclude from Entra Connect):
- **`OU=_TierModel` -> `OU=Tier Model Administration`**
  - `OU=Tier 0` (Tier 0 Accounts, Groups, Devices, Service Accounts, BreakGlassAdmin)
  - `OU=Tier 1` (Tier 1 Accounts, Groups, Devices, Service Accounts)
  - `OU=PAW Staging`
- **`OU=Tier 0 Member Servers`** (Identity, Virtualization, Management, Staging)
- **`OU=Tier 1 Member Servers`** (Application, Database, Collaboration, Messaging, Staging)
- **`OU=Domain Controllers`** (Active Directory Domain Controllers)

### ✅ ALLOW SYNCHRONIZATION (Include in Entra Connect):
- **`OU=_TierModel` -> `OU=Tier 2 End-User Accounts`**
  - `OU=Enabled End-Users Accounts` (Standard employee accounts requiring cloud access, Office 365, Teams)
- **`OU=_TierModel` -> `OU=Tier 2 End-User Groups`**
  - `OU=Distribution Groups` (Email distribution lists)
  - `OU=Security Groups` (Non-privileged end-user security groups)
  - `OU=Contacts` (External mail contacts)
- **`OU=_TierModel` -> `OU=Tier Model Administration` -> `OU=PAW VPN Accounts`**
  - Optional: Synchronized to Entra ID solely for cloud-based Multi-Factor Authentication (MFA) enforcement on VPN endpoints.

---

## Break-Glass & Emergency Access Accounts

### On-Premises Active Directory:
- **`BreakGlassAdmin`** account resides in `OU=Tier 0 Accounts,OU=Tier 0,OU=Tier Model Administration`.
- Must remain **Disabled by default**.
- Must be **excluded from AuthSilo & Protected Users** to permit logon during ADFS/PKI service outages.
- Password stored in a physical vault/safe.

### Microsoft Entra ID (Cloud):
- Cloud emergency accounts must be **Cloud-Only (`*.onmicrosoft.com`)**, created directly in Entra ID portal.
- **NEVER sync on-premises emergency accounts to Entra ID**.
- FIDO2 / Passkey security key recommended for cloud emergency access.
