# 🗺️ Blueprint Conversion Utility

Blueprint Conversion Utility (BCU) is a macOS application for analyzing Jamf Pro computer and mobile-device Configuration Profiles and converting or taking them over as Jamf Platform Blueprints.

BCU is designed to guide administrators through the conversion process rather than simply translating configuration data. It analyzes the selected Configuration Profile, evaluates available Blueprint-compatible settings, reviews scope, identifies potential migration concerns, and provides a controlled workflow for creating and deploying the resulting Blueprint.

---

## 👀 Overview

BCU helps administrators move Configuration Profile management toward Jamf Platform Blueprints while maintaining visibility into:

- Source Configuration Profile settings
- Scope and target groups
- Blueprint-compatible payloads and components
- Activation Conditions
- Unsupported or dropped configuration keys
- Recommended conversion or takeover strategy
- Blueprint creation
- Blueprint deployment
- Deployment validation
- Source-profile lifecycle actions
- Activity history and application logs

BCU also integrates `jamf-cli` analysis into the workflow to provide additional guidance before changes are made.

---

## 📋 Requirements

Before using BCU, make sure you have:

- A supported macOS system
- Access to your Jamf environment
- Jamf Platform API credentials with the permissions required for the operations you intend to perform
- Appropriate Jamf administrative permissions for the Configuration Profiles, groups, and Blueprints you will manage

Your environment may require additional permissions depending on whether you are only analyzing configurations or also creating, deploying, taking over, or unscoping Configuration Profiles.

---

## 🚀 Getting Started

Launch Blueprint Conversion Utility and configure the connection to your Jamf environment.

BCU provides a guided workflow that generally follows these steps:

1. 🔌 Configure and test the Jamf Platform API connection.
2. 💻 Select **Computers** or **Mobile Devices**.
3. 📄 Select a source Configuration Profile.
4. 🔍 Allow BCU to analyze the selected profile.
5. 🤖 Review the `jamf-cli` analysis and recommendation.
6. 🎯 Review the source profile's scope.
7. 👥 Select a compatible target group when required.
8. 🧩 Review Blueprint properties and editable values.
9. ⚙️ Review payloads, components, and Activation Conditions.
10. 🧪 Run a **Dry Run**.
11. ⚠️ Review warnings, dropped settings, and proposed changes.
12. ✅ Disable Dry Run when you are ready to make changes.
13. ▶️ Select the appropriate execution action.
14. 🔄 Review the resulting Blueprint and deployment status.
15. 🛡️ Perform any authorized source-profile lifecycle action.
16. 📜 Review Activity and application logs as needed.

---

# 🔌 Connecting to Jamf

BCU requires access to the Jamf APIs used by the application's analysis and Blueprint-management workflows.

Enter the requested Jamf environment and credential information in BCU and use the connection test before attempting a conversion.

A successful connection test confirms that BCU can authenticate to the configured environment. Individual operations may still require additional API permissions.

## 🔐 Credential Security

Treat Jamf API credentials as privileged administrative credentials.

Use credentials that:

- Follow the principle of least privilege
- Are dedicated to the required BCU operations when practical
- Can be rotated without affecting unrelated integrations

---

# 📄 Selecting a Configuration Profile

BCU supports workflows for both:

- 💻 Computer Configuration Profiles
- 📱 Mobile Device Configuration Profiles

Select the appropriate device category and then choose the Configuration Profile you want to analyze.

Changing the selected Configuration Profile starts a new profile-specific analysis.

BCU clears authorization and state associated with the previously selected profile so that an earlier profile's conversion or deployment state cannot accidentally authorize lifecycle operations against a newly selected profile.

---

# 🔍 Automatic Analysis

After selecting a Configuration Profile, BCU analyzes the profile before execution options are presented.

The analysis is intended to help determine whether the configuration can be represented by a Jamf Platform Blueprint and what migration approach is appropriate.

Depending on the selected profile, BCU may review:

- Configuration payloads
- Managed preferences
- Blueprint-compatible settings
- Unsupported configuration
- Scope
- Target groups
- Activation Conditions
- Existing Blueprint relationships
- Migration implications
- Potentially dropped configuration keys

The analysis should be allowed to complete before making conversion decisions.

---

# 🤖 `jamf-cli` Analysis

BCU integrates `jamf-cli` into the analysis process.

When a Configuration Profile is selected, BCU automatically attempts to locate the appropriate `jamf-cli` installation and uses it as part of its analysis when available.

The administrator should not need to manually run `jamf-cli` for the standard BCU workflow.

BCU uses the resulting information to help explain the recommended migration path in administrator-friendly terms.

## 🔄 Analysis Refresh

BCU keeps analysis associated with the currently selected Configuration Profile.

Selecting another profile triggers fresh analysis rather than reusing the previous profile's results.

This is particularly important when moving between profiles with different payloads, target groups, or deployment characteristics.

---

# 💡 Recommendations

BCU is designed to provide guidance rather than requiring administrators to interpret raw API information themselves.

After analysis, review the recommendation presented by BCU.

Depending on the configuration and current environment, BCU may indicate that the profile is suitable for:

- Creating a new Blueprint
- Creating and deploying a Blueprint
- A takeover workflow
- Additional review before migration

> ⚠️ **Important:** Warnings should be resolved or understood before proceeding.

---

# 🎯 Scope Review

Before deploying a Blueprint, carefully review the scope of the source Configuration Profile.

BCU displays the relevant scope information so that administrators can understand which devices or groups are currently receiving the configuration.

This step is important because Blueprint deployment and Configuration Profile scope are separate lifecycle decisions.

> **Creating a Blueprint does not automatically mean that the source Configuration Profile should be removed from scope.**

---

# 👥 Target Groups

When a Blueprint requires a target group, BCU allows you to select a compatible group from the Jamf environment.

Choose the target intentionally.

Do not assume that the source Configuration Profile's scope and the Blueprint target are automatically equivalent.

BCU's workflow keeps target selection visible so that administrators can review the destination before deployment.

---

# 🧩 Blueprint Configuration

Before execution, BCU presents the proposed Blueprint configuration for review.

Depending on the selected Configuration Profile and Blueprint type, this can include:

- Blueprint name
- Description
- Editable text values
- Selectable options
- Payloads
- Components
- Activation Conditions
- Target information

Editable values should be reviewed before running a Dry Run or creating the Blueprint.

---

# ⚙️ Payloads and Components

BCU translates supported Configuration Profile settings into Blueprint-compatible configuration.

Review the resulting payloads and components carefully.

Not every Configuration Profile setting necessarily has a direct Blueprint equivalent.

When possible, BCU identifies settings that cannot be represented so that the administrator can understand the difference between the source Configuration Profile and the resulting Blueprint.

---

# ⚠️ Dropped or Unsupported Keys

If configuration values cannot be represented in the resulting Blueprint, BCU exposes that information rather than silently treating the conversion as completely equivalent.

Review dropped or unsupported keys before deployment.

A Blueprint may be successfully created while still requiring administrator review because one or more source settings cannot be represented directly.

> ⚠️ **This distinction is especially important before removing the original Configuration Profile from scope.**

---

# ⚡ Activation Conditions

Activation Conditions determine when applicable Blueprint configuration should activate.

Review generated or proposed Activation Conditions before creating the Blueprint.

BCU keeps this information visible during the conversion workflow so that the administrator can verify that the resulting behavior matches the intended device configuration.

---

# 🧪 Dry Run

BCU provides a **Dry Run** mode so the proposed operation can be evaluated before Jamf is changed.

> ✅ **Running a Dry Run is strongly recommended.**

During a Dry Run, BCU can evaluate the requested workflow and highlight relevant configuration, scope, conversion, or lifecycle concerns without performing the final production operation.

A typical workflow is:

1. Select the source Configuration Profile.
2. Allow analysis to finish.
3. Review the recommendation.
4. Select the intended target.
5. Review the proposed Blueprint.
6. Enable **Dry Run**.
7. Execute the workflow.
8. Review the results.
9. Correct any problems or warnings.
10. Disable Dry Run.
11. Execute the production operation.

---

# ▶️ Execution Actions

Once analysis and review have been completed, BCU provides execution actions appropriate to the current workflow.

## 📝 Create Only

**Create Only** creates the Blueprint without requesting deployment.

The source Configuration Profile remains scoped.

Use this when you want to:

- Inspect the created Blueprint before deployment
- Perform additional Jamf-side review
- Separate Blueprint creation from deployment
- Preserve the source Configuration Profile while validating the result

---

## 🚀 Create and Deploy

**Create and Deploy** creates the Blueprint and requests deployment.

BCU retains the Blueprint identifier and validates deployment asynchronously through Jamf Platform API read-back rather than assuming that the immediate creation response represents the final deployment state.

Deployment is therefore treated as a process, not a single synchronous event.

An initial state indicating that the Blueprint has not yet deployed is not automatically considered a failure.

BCU continues checking the Blueprint deployment state until one of the following occurs:

- ✅ Deployment is confirmed
- ❌ Jamf reports a terminal failure
- ⏱️ Deployment validation times out
- ❓ The resulting state cannot be conclusively determined

---

# 🔄 Deployment Validation

Jamf may require time after a deployment request before the final deployment state is visible through the Platform API.

Because of this, BCU uses asynchronous read-back and polling.

Conceptually, the workflow is:

1. 🧩 Create the Blueprint.
2. 🚀 Request deployment.
3. 🆔 Retain the returned Blueprint ID.
4. 🔍 Read the Blueprint state through the Platform API.
5. 🔄 Continue polling while the state is nonterminal.
6. ✅ Stop when deployment is confirmed, a terminal error is returned, or validation reaches its timeout.
7. 📋 Report the resulting state accurately to the administrator.

This avoids incorrectly reporting a successful deployment as failed simply because Jamf had not finished processing it when the initial response was received.

---

# 🟡 Partial Completion

Blueprint creation and Blueprint deployment are separate outcomes.

For example, BCU may successfully create a Blueprint but be unable to conclusively validate the subsequent deployment within the expected validation period.

BCU treats this situation as **partial completion** rather than incorrectly reporting the entire operation as failed.

A partial-completion result indicates that some requested operations succeeded but administrator review is still required.

Review:

- Blueprint ID
- Creation result
- Deployment request result
- Latest Platform API deployment state
- Source Configuration Profile state
- Activity details
- Application logs

before retrying an operation.

> ⚠️ **Avoid immediately recreating a Blueprint simply because deployment validation was inconclusive.**

---

# 🛡️ Source Configuration Profile Lifecycle

Creating a Blueprint and removing the original Configuration Profile from scope are intentionally separate decisions.

BCU does not assume that successful Blueprint creation means the source profile should immediately be removed.

This helps prevent an incomplete migration from unintentionally removing configuration from managed devices.

---

# 🚫 Unscoping the Source Profile

When supported by the selected workflow, BCU can allow the administrator to remove the source Configuration Profile from scope.

This is an explicit lifecycle operation.

BCU requires confirmation before performing an unscope action.

The confirmation should make clear:

- Which Configuration Profile is being modified
- That its current scope will be removed
- That managed devices may stop receiving the Configuration Profile
- That the action is separate from Blueprint creation
- That Blueprint deployment should be verified before proceeding

> ⚠️ **Do not unscope the source profile merely because Blueprint creation succeeded.**

Confirm the resulting Blueprint configuration and deployment first.

---

# 🔁 Takeover Workflows

Some migrations may be handled as takeover operations rather than simple Blueprint creation.

A takeover workflow should be used only when the selected profile and Jamf environment support the operation and BCU's analysis recommends or permits it.

Before proceeding, review:

- Source Configuration Profile
- Current scope
- Proposed Blueprint
- Target group
- Conversion analysis
- Dropped keys
- Activation Conditions
- Deployment implications
- Source-profile lifecycle action

Run a Dry Run before executing a takeover.

---

# ✅ Completion Results

After execution, BCU presents the outcome of the operation.

The completion state may include information such as:

- Source Configuration Profile
- Source Configuration Profile ID
- Blueprint ID
- Blueprint creation result
- Deployment requested
- Current deployment state
- Deployment validation result
- Scope changes
- Dropped or unsupported settings
- Partial-completion warnings
- Recommended next action

> **Do not rely on a single success indicator.**

Review creation, deployment, configuration differences, and source-profile state together when determining whether the migration is complete.

---

# 📊 Activity

BCU provides activity information to make the conversion process easier to understand and troubleshoot.

Activity information can help identify:

- Analysis progress
- API operations
- Blueprint creation
- Deployment requests
- Deployment validation
- Polling state
- Lifecycle operations
- Errors and warnings

---

# 📜 Application Logs

For troubleshooting or validation, review the application logs.

Logs are particularly useful when:

- Analysis does not complete
- `jamf-cli` analysis does not update
- A Blueprint cannot be created
- Deployment remains pending
- Platform API validation fails
- Scope cannot be modified
- A group cannot be retrieved
- A lifecycle operation is rejected

When reporting an issue, preserve the relevant logs along with:

- Operation being performed
- Source Configuration Profile ID
- Blueprint ID, if available
- Approximate time of the operation
- Reported deployment state
- Any visible BCU error

> 🔐 **Security:** Do not include credentials, secrets, or authentication tokens in externally shared troubleshooting information.

---

# 🛣️ Recommended Migration Workflow

For production migrations, the safest general workflow is:

## 1. 🔌 Connect

Configure and test the Jamf connection.

## 2. 📄 Select

Choose **Computers** or **Mobile Devices**, then select the source Configuration Profile.

## 3. 🔍 Analyze

Wait for BCU and `jamf-cli` analysis to complete.

## 4. 💡 Review the Recommendation

Understand the recommended migration approach and any warnings.

## 5. 🎯 Review Scope

Confirm which devices or groups currently receive the source Configuration Profile.

## 6. 👥 Select the Blueprint Target

Select the intended compatible target group when required.

## 7. 🧩 Review the Blueprint

Verify:

- Name
- Description
- Editable values
- Payloads
- Components
- Activation Conditions
- Dropped or unsupported settings

## 8. 🧪 Run a Dry Run

Execute the workflow with Dry Run enabled.

Resolve unexpected results before continuing.

## 9. ▶️ Execute

Disable Dry Run and select the required production action.

For example:

- **Create Only**
- **Create and Deploy**
- **Takeover**, when supported

## 10. 🔄 Validate Deployment

If deployment was requested, allow BCU's asynchronous validation to complete.

Do not interpret a temporary non-deployed state as an immediate failure.

## 11. ✅ Review the Result

Confirm:

- Blueprint creation
- Blueprint ID
- Deployment result
- Dropped configuration
- Target
- Source Configuration Profile state

## 12. 🛡️ Unscope Only When Appropriate

If the migration has been validated and the source Configuration Profile is no longer required, explicitly authorize the unscope operation.

---

# 🛡️ Important Safety Principles

BCU is intentionally conservative around operations that can change device configuration.

The following principles should be followed during production use.

## 🔍 Analyze First

Allow profile analysis to complete before selecting an execution path.

## 🧪 Dry Run First

Use Dry Run before performing production changes whenever possible.

## 🧩 Treat Creation and Deployment Separately

A successfully created Blueprint is not necessarily a successfully deployed Blueprint.

## 🎯 Treat Deployment and Unscoping Separately

A deployment request does not automatically justify removing the source Configuration Profile.

## ✅ Verify Before Removing Existing Management

Confirm that the Blueprint contains the expected configuration and has reached the intended target before removing the original profile.

## ⚠️ Review Dropped Keys

Do not assume the Blueprint is functionally identical to the Configuration Profile if BCU reports unsupported or dropped settings.

## ⏱️ Do Not Assume an Immediate Deployment State Is Final

Jamf Platform processing can be asynchronous. Allow BCU's deployment validation workflow to reach its conclusion.

---

# 🛠️ Troubleshooting

## ⏳ Analysis Does Not Complete

If analysis appears to remain in progress:

1. Verify that the Jamf connection is still valid.
2. Confirm that the selected Configuration Profile can be retrieved.
3. Review `jamf-cli` status.
4. Review Activity.
5. Review the application logs.
6. Reselect the profile and allow a fresh analysis to run if appropriate.

---

## 🤖 `jamf-cli` Does Not Update

If the `jamf-cli` portion of analysis does not refresh after changing profiles:

1. Confirm the newly selected Configuration Profile is shown.
2. Give the current analysis time to complete.
3. Review Activity for discovery or execution errors.
4. Review application logs.
5. Verify that the analysis result belongs to the currently selected profile before continuing.

> ⚠️ Do not rely on an analysis result left over from another Configuration Profile.

---

## 🟡 Blueprint Was Created but Deployment Is Not Yet Confirmed

Do not immediately create another Blueprint.

Instead:

1. Note the Blueprint ID.
2. Allow BCU's deployment polling to continue.
3. Review the most recent Platform API state.
4. Review Activity.
5. Review logs.
6. If validation times out, inspect the Blueprint in Jamf before deciding whether another action is necessary.

The operation may have partially completed successfully.

---

## ⏱️ Deployment Shows a Temporary Non-Deployed State

A non-deployed state returned immediately after requesting deployment may be transitional.

BCU therefore polls the Jamf Platform API instead of treating that initial state as a terminal failure.

Allow validation to complete before retrying the operation.

---

## 👥 Target Group Is Missing

If an expected group does not appear:

1. Verify the selected device platform.
2. Confirm the group exists in Jamf.
3. Confirm that the configured credentials can retrieve it.
4. Refresh the relevant data.
5. Review Activity and logs for API or pagination errors.

---

## 🚫 Unscope Is Not Available

BCU intentionally restricts lifecycle operations when the current state does not justify them.

Verify that:

- The correct Configuration Profile is selected
- Analysis has completed
- The appropriate operation has completed
- The current Blueprint state is known
- The requested lifecycle operation is allowed for the current workflow

Do not bypass lifecycle safeguards simply to force the source profile out of scope.

---

# 🚦 Interpreting Results

BCU deliberately distinguishes between several outcomes.

### ✅ Successful

The requested operation completed and BCU was able to validate the resulting state.

### 🟡 Partial Completion

One portion of the requested operation completed, but another portion could not yet be conclusively validated.

For example:

- Blueprint creation succeeded
- Deployment was requested
- Final deployment state could not be confirmed before validation ended

### ❌ Failed

The requested operation encountered a terminal error and could not complete as intended.

### ⚠️ Requires Review

BCU found configuration differences, unsupported settings, ambiguous state, or another condition that should be reviewed by an administrator before continuing.

---

# ⭐ Operational Best Practices

For production use:

- 🧪 Test BCU against noncritical profiles first.
- 🔐 Use least-privilege Jamf API credentials.
- 🧪 Run a Dry Run before production migration.
- 🔍 Review the source profile's payloads and scope.
- ⚠️ Review dropped or unsupported settings.
- 🎯 Verify Blueprint targets.
- ⏱️ Wait for asynchronous deployment validation.
- 🆔 Record the Blueprint ID for production changes.
- ✅ Confirm deployment before unscoping the source profile.
- 📜 Keep application logs available while validating major migrations.
- 🚫 Avoid retrying creation blindly after partial completion.

---

# ⬆️ Updating BCU

BCU may evolve as Jamf Platform Blueprint capabilities and APIs change.

When updating BCU:

1. Review the release information accompanying the build.
2. Confirm that your Jamf API credentials still provide the necessary permissions.
3. Test important workflows before performing a production migration.
4. Re-run analysis for profiles that were evaluated using an older build if conversion behavior has changed.

This README intentionally avoids tying the workflow to a specific BCU release number so that the primary documentation remains useful across application updates.

Release-specific behavior, fixes, and upgrade information should be documented separately in release notes or a changelog.

---

# 🩺 Support and Diagnostics

When troubleshooting a BCU issue, collect as much of the following information as possible:

- BCU build/version
- macOS version
- Jamf environment type
- Computer or Mobile Device workflow
- Source Configuration Profile ID
- Blueprint ID, when available
- Operation selected
- Whether Dry Run was enabled
- Analysis status
- `jamf-cli` analysis status
- Deployment status
- Relevant Activity entries
- Relevant application logs

> 🔐 **Before sharing diagnostic information:** Remove credentials, secrets, tokens, and other sensitive information.

---

# ⚖️ Disclaimer

Blueprint Conversion Utility performs administrative operations that can affect configuration delivery to managed devices.

Administrators are responsible for reviewing generated Blueprints, deployment targets, unsupported configuration, scope changes, and lifecycle operations before applying them in a production environment.

> ⚠️ **The creator/owner is not responsible for disruptions to your environment resulting from the use of Blueprint Conversion Utility.**

Use **Dry Run** and nonproduction testing whenever practical, and verify Blueprint deployment before removing an existing Configuration Profile from scope.

---

# 🙌 Special Thanks

A special shoutout and sincere thanks to **Neil Martin**:

👉 **[github.com/neilmartin83](https://github.com/neilmartin83)**

for his help and assistance with **`jamf-cli`**.

His knowledge, feedback, and assistance with `jamf-cli` helped make its integration into Blueprint Conversion Utility possible and contributed to BCU's ability to provide administrators with better analysis and guidance when evaluating Configuration Profiles for migration to Jamf Platform Blueprints.

**Thank you, Neil!** 🎉

---
