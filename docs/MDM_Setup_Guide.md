# MDM Setup Guide for Spark for DOOH (Apple TV)

This guide explains how to configure Apple TVs for kiosk-mode deployment using MDM (Mobile Device Management).

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Option 1: Apple Configurator (Small Deployments)](#option-1-apple-configurator-small-deployments)
4. [Option 2: Apple Business Manager + MDM (Enterprise)](#option-2-apple-business-manager--mdm-enterprise)
5. [Single App Mode Configuration](#single-app-mode-configuration)
6. [Troubleshooting](#troubleshooting)

---

## Overview

### What This Achieves

| Feature | Description |
|---------|-------------|
| **Auto-launch on boot** | Spark for DOOH starts automatically when Apple TV powers on |
| **Kiosk mode** | Users cannot exit the app or access settings |
| **Remote management** | Update app and settings without physical access |
| **Crash recovery** | App automatically restarts if it crashes |

### Deployment Options

| Method | Best For | Requires Cable? |
|--------|----------|-----------------|
| Apple Configurator | 1-10 devices | Yes (initial setup) |
| Apple Business Manager + MDM | 10+ devices | No (after enrollment) |

---

## Prerequisites

### Hardware
- Apple TV 4K (2nd gen or later recommended)
- USB-C cable (for Apple Configurator method)
- Mac with macOS 12.0 or later

### Software
- [Apple Configurator 2](https://apps.apple.com/app/apple-configurator-2/id1037126344) (free from Mac App Store)
- Spark for DOOH app (IPA file for Ad Hoc/Enterprise distribution)

### Accounts
- Apple ID (for Apple Configurator)
- Apple Business Manager account (for enterprise MDM)

---

## Option 1: Apple Configurator (Small Deployments)

Best for: **1-10 Apple TVs**, one-time setup with physical access.

### Step 1: Install Apple Configurator 2

1. Open Mac App Store
2. Search for "Apple Configurator 2"
3. Download and install (free)

### Step 2: Connect Apple TV

1. **Power off** the Apple TV
2. Connect USB-C cable between Apple TV and Mac
3. **Power on** the Apple TV
4. Open Apple Configurator 2
5. Wait for Apple TV to appear in the device list

> **Troubleshooting:** If device doesn't appear:
> - Use a different USB-C cable (must support data, not just charging)
> - Connect directly to Mac (not through USB hub)
> - Try different USB port on Mac

### Step 3: Prepare the Apple TV

1. Select the Apple TV in Apple Configurator
2. Go to **Actions → Prepare**
3. Configure:
   - **Supervision:** Enable (required for Single App Mode)
   - **Organization:** Your organization name
   - **Skip Setup Assistant:** Yes
4. Click **Prepare**

### Step 4: Install Spark for DOOH App

1. Build the app in Xcode: **Product → Archive**
2. Export as **Ad Hoc** or **Enterprise** IPA
3. In Apple Configurator:
   - Select the Apple TV
   - **Actions → Add → Apps**
   - Choose the IPA file
4. Wait for installation to complete

### Step 5: Enable Single App Mode

1. Select the Apple TV in Apple Configurator
2. **Actions → Advanced → Start Single App Mode**
3. Select **Spark for DOOH** from the list
4. Click **Apply**

### Step 6: Deploy

1. Disconnect USB-C cable
2. Connect Apple TV to power and HDMI
3. Apple TV will boot directly into Spark for DOOH

---

## Option 2: Apple Business Manager + MDM (Enterprise)

Best for: **10+ devices**, remote management, over-the-air updates.

### Step 1: Enroll in Apple Business Manager

1. Go to [business.apple.com](https://business.apple.com)
2. Click **Enroll Now**
3. Requirements:
   - D-U-N-S number (business identifier)
   - Business email domain
   - Verification process (2-5 days)

### Step 2: Choose an MDM Solution

| MDM Provider | Pricing | Apple TV Support | Notes |
|--------------|---------|------------------|-------|
| [Jamf Pro](https://www.jamf.com) | $$$$ | Excellent | Industry standard |
| [Mosyle](https://mosyle.com) | $$$ | Good | Healthcare focus |
| [SimpleMDM](https://simplemdm.com) | $$ | Good | Easy to use |
| [Kandji](https://kandji.io) | $$$ | Good | Modern UI |
| [Hexnode](https://hexnode.com) | $$ | Good | Budget friendly |

### Step 3: Connect MDM to Apple Business Manager

1. In your MDM console, get the MDM server token
2. In Apple Business Manager:
   - Go to **Settings → Device Management Settings**
   - Add your MDM server
   - Upload the MDM server token

### Step 4: Add Apple TVs to Apple Business Manager

**Option A: Purchase through Apple or authorized reseller**
- Devices are automatically added to your organization

**Option B: Manually add existing devices**
1. Connect Apple TV to Mac via USB-C
2. Open Apple Configurator 2
3. **Actions → Assign to Organization**
4. Select your Apple Business Manager organization

### Step 5: Create Configuration Profile

In your MDM console, create a profile with:

```xml
<!-- Single App Mode Configuration -->
<key>PayloadType</key>
<string>com.apple.app.lock</string>

<key>App</key>
<dict>
    <key>Identifier</key>
    <string>com.doceree.SparkForDOOH</string>
</dict>

<!-- Disable sleep -->
<key>PayloadType</key>
<string>com.apple.tvOS.settings</string>
<key>sleepDisabled</key>
<true/>
```

### Step 6: Assign Profile to Devices

1. In MDM console, select your Apple TVs
2. Assign the configuration profile
3. Push the Spark for DOOH app
4. Devices will configure automatically

---

## Single App Mode Configuration

### What Single App Mode Does

- Locks device to Spark for DOOH app
- Hides Home button functionality
- Auto-restarts app on crash
- Prevents access to Settings
- Survives device restart

### Exiting Single App Mode

**Via Apple Configurator:**
1. Connect Apple TV to Mac via USB-C
2. Open Apple Configurator 2
3. Select device → **Actions → Advanced → Stop Single App Mode**

**Via MDM:**
1. Log into MDM console
2. Select device
3. Remove Single App Mode profile

### Updating the App in Single App Mode

**Via Apple Configurator:**
1. Connect Apple TV to Mac
2. Stop Single App Mode
3. Install new app version
4. Re-enable Single App Mode

**Via MDM:**
1. Upload new app version to MDM
2. Push update to devices
3. App updates automatically (no Single App Mode interruption)

---

## Troubleshooting

### Apple TV Not Appearing in Apple Configurator

| Issue | Solution |
|-------|----------|
| No device shown | Use data-capable USB-C cable, not charging-only |
| "Unable to prepare" | Reset Apple TV: Settings → System → Reset |
| "Device is in use" | Disconnect from any other MDM first |

### App Not Starting on Boot

| Issue | Solution |
|-------|----------|
| Shows Home Screen | Verify Single App Mode is enabled |
| Black screen | Check HDMI connection, try different port |
| Crash loop | Check app logs via Xcode, verify network connectivity |

### Network Issues

| Issue | Solution |
|-------|----------|
| Can't fetch ads | Verify Wi-Fi is configured in profile |
| Activation fails | Check firewall allows: qa-keen.doceree.com |
| Updates not working | Verify MDM server is reachable |

### Resetting a Device

**Factory Reset (loses all data):**
1. Connect to Mac via USB-C
2. Apple Configurator → **Actions → Restore**

**Remove from MDM:**
1. In MDM console, remove device from organization
2. Device will need to be re-enrolled

---

## Network Requirements

Ensure these domains are accessible from the Apple TV network:

| Domain | Purpose |
|--------|---------|
| `*.doceree.com` | Activation & Ad APIs |
| `*.apple.com` | MDM communication |
| `*.icloud.com` | Apple services |
| `simage.doceree.com` | Ad asset CDN |

### Firewall Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 443 | HTTPS | All API communication |
| 80 | HTTP | Asset downloads (redirects to HTTPS) |
| 5223 | TCP | Apple Push Notifications |

---

## Quick Reference Card

### For Field Technicians

```
1. CONNECT Apple TV to power + HDMI
2. VERIFY network connection
3. CONFIRM app launches automatically
4. CHECK ads are playing
5. REPORT screen ID to operations team
```

### Emergency Contacts

| Issue | Contact |
|-------|---------|
| App not working | [Your IT Support] |
| MDM issues | [Your MDM Provider Support] |
| Backend issues | [Doceree Support] |

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Dec 2025 | Initial document |

---

*Document created for Spark for DOOH tvOS deployment*

