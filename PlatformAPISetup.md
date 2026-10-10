# 🔑 Jamf Platform API Setup for Blueprint Conversion Utility

Blueprint Conversion Utility (BCU) uses the **Jamf Platform API** for Configuration Profile analysis, Platform Device Group discovery, Blueprint creation and deployment, deployment validation, and authorized source-profile lifecycle operations.

This document is the standalone Platform API reference for BCU. The main project README can link here instead of duplicating the full API setup instructions.

> 🔐 **Recommendation:** Create a dedicated Platform API OAuth Client for BCU and grant only the permissions required for the workflows your administrators will use.

---

## 📋 Required Information

BCU requires:

```text
Platform API URL
Client ID
Client Secret
Platform Environment ID
```

> ℹ️ **Tenant ID is not required by BCU.** BCU uses the Platform Environment ID for environment-scoped operations.

---

## 🏗️ 1. Create the Platform API Client

Sign in to Jamf with an account authorized to create and manage Platform API Clients.

Create a dedicated client for BCU. A descriptive name such as the following is recommended:

```text
Blueprint Conversion Utility
```

Configure the client at the:

```text
Platform Environment
```

level.

Recommended configuration:

```text
✅ Platform Environment
❌ Tenant
❌ Organization Management
```

Select the Platform Environment containing the Jamf environment BCU will manage and record its:

```text
Platform Environment ID
```

> ⚠️ Do not substitute a Tenant ID for the Platform Environment ID.

---

## 🔐 2. Configure API Permissions

BCU works with three primary Platform API resource areas:

```text
Configuration Profiles
Device Groups
Blueprints
```

Permissions should follow least privilege and match the BCU features you intend to use.

### 📱 Configuration Profiles

BCU requires Configuration Profile access to:

- Discover available Configuration Profiles
- Read the selected profile
- Analyze configuration and scope
- Compare source state during migration
- Perform an explicitly authorized source-profile lifecycle operation when applicable

For analysis, grant the current Jamf permissions corresponding to:

```text
Configuration Profiles
    Read
    List
```

For migration workflows that modify the source Configuration Profile, also grant the applicable mutation capability exposed by your Jamf environment:

```text
Configuration Profiles
    Update / Modify
```

Only grant mutation access when BCU will actually perform that operation.

### 👥 Device Groups

BCU reads Platform Device Groups for target selection, scope evaluation, and applicable Activation Conditions.

Grant permissions corresponding to:

```text
Device Groups
    Read
    List
```

BCU supports environments with large numbers of Device Groups by loading additional results incrementally, appending them to the existing results, and deduplicating entries.

### 🗺️ Blueprints

Depending on the enabled workflow, BCU may need capabilities corresponding to:

```text
Blueprints
    Read
    List
    Create
    Update
    Deploy / Assign
```

These allow BCU to:

- Read Blueprint information
- Create the converted Blueprint
- Configure Blueprint properties and components
- Request Blueprint deployment
- Read the resulting deployment state
- Validate deployment after creation

> ⚠️ Jamf may change permission names or granularity. Select the current permissions in your Jamf environment that correspond to the capabilities above rather than relying on an older user-interface label.

---

## 🔏 3. Recommended Least-Privilege Models

### Analysis / Dry Run

```text
Configuration Profiles: Read
Device Groups:          Read
Blueprints:             Read
```

Use this configuration when initially evaluating BCU or when administrators should only analyze Configuration Profiles.

### Create Only

```text
Configuration Profiles: Read
Device Groups:          Read
Blueprints:             Read + Create/Write
```

This permission model supports:

```text
Create Only
```

BCU can create the resulting Blueprint, but it cannot deploy it or modify the source Configuration Profile.

### Create and Deploy

```text
Configuration Profiles: Read
Device Groups:          Read
Blueprints:             Read + Create/Write + Deploy/Assign
```

This permission model supports:

```text
Create and Deploy
```

BCU can create the Blueprint, request deployment, and read deployment state for validation.

### Full Migration / Takeover

```text
Configuration Profiles: Read + required lifecycle/scope modification access
Device Groups:          Read
Blueprints:             Read + Create/Write + Deploy/Assign
```

This permission model supports BCU workflows that perform an authorized source Configuration Profile lifecycle action after Blueprint deployment is validated.

Start with read-only access when evaluating BCU, then add mutation capabilities only when required.

---

## 🪪 4. Generate the Credentials

After configuring the client and its permissions, save the API Client and record:

```text
Client ID
Client Secret
```

Treat the Client Secret like a password.

> 🔐 Do not commit the Client Secret to source control or expose it in documentation, screenshots, issue trackers, logs, or support material.

If Jamf displays the Client Secret only during creation, capture it at that time and store it using your organization's approved credential-management system.

---

## 🌐 5. Gather the BCU Connection Values

You should now have:

```text
Platform API URL
Client ID
Client Secret
Platform Environment ID
```

Example layout:

```text
Platform API URL:         https://<your-platform-api-host>
Client ID:                <client-id>
Client Secret:            <client-secret>
Platform Environment ID:  <environment-id>
```

BCU does not require a Tenant ID for its Platform Environment workflows.

---

## 🖥️ 6. Configure BCU

Open BCU's API configuration interface and enter:

```text
Platform API URL
Client ID
Client Secret
Platform Environment ID
```

Before saving, verify:

- The Platform API URL belongs to the intended environment
- The Client ID is correct
- The Client Secret is current
- The Platform Environment ID is correct
- No leading or trailing whitespace was pasted into any field

Save the configuration.

BCU should indicate that the required API configuration is present with:

```text
✅ API Configured
```

The configured indicator confirms that the required fields are present. It does not replace an actual connection test.

---

## ✅ 7. Test the Connection

Run BCU's API connection test.

Recommended validation sequence:

```text
Authenticate
    ↓
Load Configuration Profiles
    ↓
Load Device Groups
    ↓
Read Blueprint Resources
    ↓
Select Test Profile
    ↓
Run Analysis
    ↓
Dry Run
```

Only proceed to mutation testing after read-only validation succeeds.

---

## 🧪 8. Validate Permissions by Workflow

### Configuration Profiles Load

This confirms that authentication and the required Configuration Profile read access are functioning.

### Device Groups Load

This confirms that the client can read the Platform Device Groups needed for scope and target selection.

### Blueprint Reads Succeed

This confirms that Blueprint read access is functioning.

### Create Only Succeeds

This validates the Blueprint create/write capability without introducing deployment into the test.

Use a noncritical test Configuration Profile and inspect the resulting Blueprint directly in Jamf.

### Create and Deploy Succeeds

This validates:

- Blueprint creation
- Blueprint deployment or assignment
- Deployment-state read-back

BCU should validate the resulting deployment state rather than considering the initial Blueprint creation response sufficient proof of deployment.

### Source Lifecycle Operations Succeed

Only test source-profile modification after Blueprint creation and deployment are already validated.

This confirms the additional Configuration Profile mutation capability required for the migration workflow.

---

## 🔄 9. Deployment Validation

Deployment is asynchronous and may not be immediately reflected as complete.

An initial state such as:

```text
NOT_DEPLOYED
```

should be treated as nonterminal while validation is in progress.

Expected flow:

```text
Create Blueprint
      ↓
Request Deployment
      ↓
Read Deployment State
      ↓
NOT_DEPLOYED
      ↓
Wait / Poll
      ↓
Read Again
      ↓
Confirmed Deployment / Terminal Failure / Timeout
```

BCU should continue validation until:

- Deployment is confirmed
- Jamf reports a terminal failure
- Validation times out

A validation timeout is inconclusive. It is not confirmation of successful deployment.

Do not perform a destructive source Configuration Profile lifecycle action solely because Blueprint creation succeeded.

---

## 🛡️ 10. Security Recommendations

### Use a Dedicated Client

Use a dedicated OAuth client for BCU rather than sharing credentials with unrelated integrations.

A dedicated client provides:

- A cleaner security boundary
- Easier credential rotation
- Better auditability
- More predictable permissions
- Easier troubleshooting

### Follow Least Privilege

Grant only the permissions required for the intended BCU workflow.

An evaluation environment may require only read access.

Production migration workflows may also need:

- Blueprint creation
- Blueprint deployment
- Configuration Profile lifecycle modification

### Protect Secrets

Never place these values in public documentation or source control:

```text
Client Secret
OAuth Access Token
Authorization Header
```

Avoid exposing credentials in:

- Git repositories
- Screenshots
- Support tickets
- README files
- Application logs
- Shell history
- Troubleshooting attachments

### Rotate Secrets

Rotate the Client Secret according to your organization's credential policy and immediately after suspected exposure.

After rotation, update BCU and rerun the connection test before performing another migration.

---

## 🔄 11. Credential Rotation Procedure

When rotating the BCU Platform API Client Secret:

1. Generate or rotate the Client Secret in Jamf.
2. Securely record the new secret.
3. Open the API configuration interface in BCU.
4. Replace the old Client Secret.
5. Save the configuration.
6. Run the connection test.
7. Confirm Configuration Profiles load.
8. Confirm Device Groups load.
9. Confirm Blueprint reads succeed.
10. Run a Dry Run before the next production migration.

Routine Client Secret rotation should not normally require changing the Platform Environment ID.

---

## 🧪 12. Troubleshooting

### API Configured Does Not Appear

Verify all four required values are populated:

```text
Platform API URL
Client ID
Client Secret
Platform Environment ID
```

Do not use a Tenant ID in place of the Platform Environment ID.

### Authentication Fails

Check:

1. Client ID is correct.
2. Client Secret is current.
3. API Client is enabled.
4. Client belongs to the intended Platform Environment.
5. Platform API URL is correct.
6. Platform Environment ID is correct.
7. Credential fields contain no accidental whitespace.

If the Client Secret was recently regenerated, verify that BCU contains the new secret rather than the previous one.

### Configuration Profiles Do Not Load

Verify:

- Authentication succeeds
- Configuration Profile read permissions are granted
- Correct Platform Environment is configured
- Platform Environment ID is correct
- Platform API URL is correct

Review BCU's logs for the returned HTTP or API error.

### Configuration Profiles Load but Device Groups Do Not

Verify the API Client has Device Group read/list permissions.

Configuration Profile permissions and Device Group permissions are separate resource capabilities.

### Only Some Device Groups Appear

Allow BCU to load additional pages of Device Groups.

BCU loads Device Groups incrementally:

```text
Load initial results
        ↓
Request next page when needed
        ↓
Append results
        ↓
Remove duplicates
        ↓
Continue selection
```

If loading stops unexpectedly, review the application logs for an API or pagination error.

### Analysis Works but Blueprint Creation Fails

The client may have Blueprint read access without create/write access.

Review the Blueprint privileges assigned to the client.

### Blueprint Creates but Deployment Fails

Verify:

- Blueprint deployment or assignment capability
- Selected Device Group
- Target scope
- Activation Conditions
- Environment configuration
- API response in the application log

Blueprint creation does not prove successful deployment.

### Deployment Initially Reports `NOT_DEPLOYED`

Allow BCU's asynchronous deployment validation to continue.

An initial:

```text
NOT_DEPLOYED
```

response is not automatically a terminal failure.

Do not immediately modify or unscope the source Configuration Profile.

### Deployment Validation Times Out

If validation times out:

1. Leave the source Configuration Profile intact.
2. Review BCU's activity and logs.
3. Open the Blueprint directly in Jamf.
4. Verify the deployment target.
5. Verify the current deployment state.
6. Continue the source lifecycle workflow only after successful deployment is confirmed.

### Blueprint Deployment Works but Source Profile Modification Fails

The client may have sufficient Blueprint privileges but insufficient Configuration Profile mutation privileges.

Add only the specific lifecycle or scope modification capability required by the intended workflow.

Do not grant unrelated administrative privileges as a workaround.

---

## ✅ 13. Pre-Production Checklist

### API Client

- [ ] Dedicated BCU Platform API Client created
- [ ] Client scoped to the correct Platform Environment
- [ ] Platform Environment ID recorded
- [ ] Client ID recorded
- [ ] Client Secret securely stored
- [ ] Platform API URL verified

### Permissions

- [ ] Configuration Profile read access granted
- [ ] Device Group read access granted
- [ ] Blueprint read access granted
- [ ] Blueprint create/write access granted if needed
- [ ] Blueprint deploy/assign access granted if needed
- [ ] Configuration Profile mutation access granted only if needed

### BCU Configuration

- [ ] Platform API URL entered
- [ ] Client ID entered
- [ ] Client Secret entered
- [ ] Platform Environment ID entered
- [ ] BCU displays **API Configured**
- [ ] Connection test succeeds

### Read Validation

- [ ] Configuration Profiles load
- [ ] Device Groups load
- [ ] Additional Device Group pages load
- [ ] Blueprint reads succeed
- [ ] Profile analysis succeeds
- [ ] Dry Run succeeds

### Mutation Validation

- [ ] Create Only tested if applicable
- [ ] Created Blueprint reviewed in Jamf
- [ ] Create and Deploy tested if applicable
- [ ] Deployment read-back validation succeeds
- [ ] Source lifecycle operation tested only if applicable
- [ ] Application logs reviewed for unexpected API errors

---

## 🧾 14. Quick Reference

Required BCU API configuration:

```text
Platform API URL
Client ID
Client Secret
Platform Environment ID
```

Not required:

```text
Tenant ID
```

Primary Platform API resource areas:

```text
Configuration Profiles
Device Groups
Blueprints
```

Recommended setup progression:

```text
Create Platform Environment OAuth Client
                ↓
Grant Read Permissions
                ↓
Configure BCU
                ↓
Test Connection
                ↓
Validate Profiles / Groups / Blueprints
                ↓
Dry Run
                ↓
Add Create Permission if Needed
                ↓
Test Create Only
                ↓
Add Deployment Permission if Needed
                ↓
Test Create and Deploy
                ↓
Validate Deployment Read-Back
                ↓
Add Source Lifecycle Permission Only if Needed
```

---

## 🙌 Special Thanks

A special shoutout and sincere thanks to **Neil Martin**:

👉 **[github.com/neilmartin83](https://github.com/neilmartin83)**

for his help and assistance with **`jamf-cli`**.

His knowledge, feedback, and assistance with `jamf-cli` helped make its integration into Blueprint Conversion Utility possible and contributed to BCU's ability to provide administrators with better analysis and guidance when evaluating Configuration Profiles for migration to Jamf Platform Blueprints.

**Thank you, Neil!** 🎉

---

## 📚 15. Summary

BCU uses a **Platform Environment-level OAuth API Client**.

For a complete setup:

1. Create a dedicated Platform Environment API Client.
2. Select the correct Platform Environment.
3. Grant least-privilege access to Configuration Profiles, Device Groups, and Blueprints.
4. Record the Client ID and Client Secret securely.
5. Record the Platform Environment ID.
6. Enter the Platform API URL, Client ID, Client Secret, and Platform Environment ID in BCU.
7. Confirm **API Configured**.
8. Test authentication.
9. Validate Configuration Profile, Device Group, and Blueprint reads.
10. Run a Dry Run.
11. Add mutation permissions only for workflows that require them.
12. Validate deployment before permitting source-profile lifecycle changes.
13. Review BCU logs if any API stage fails.

The core security principle is:

```text
Start read-only.
Validate access.
Add only the permissions BCU needs.
Dry Run first.
Validate deployment.
Modify the source only after validation.
```
