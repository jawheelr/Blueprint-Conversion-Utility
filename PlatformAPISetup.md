# 🔑 Jamf Platform API Setup for Blueprint Conversion Utility

Blueprint Conversion Utility (BCU) uses the **Jamf Platform API** to analyze Configuration Profiles, work with Platform Device Groups, create and deploy Blueprints, validate deployment state, and perform explicitly authorized source-profile lifecycle operations.

This guide consolidates the complete Platform API setup into a single procedure, from creating the API Client through validating it in BCU.

> 🔐 **Recommended:** Create a dedicated API Client for BCU and grant only the permissions required for the functions you plan to use.

---

## 📋 What You Need

Before beginning, make sure you have:

- Administrative access to the Jamf environment
- Access to Jamf Platform API Client management
- Permission to create a **Platform Environment-level** API Client
- The Platform Environment that contains the Jamf Pro environment BCU will manage
- BCU installed on a supported macOS system

BCU requires these four values:

```text
Platform API URL
Client ID
Client Secret
Platform Environment ID
