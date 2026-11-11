# Blueprint Conversion Utility 3.5.0 Complete
Includes the 2.1.1 connection-state fix, 2.1.2 Jamf profile parser fix, icon resources, Keychain storage, both required API tests, and app/PKG/DMG build. Build without sudo: `xattr -dr com.apple.quarantine . && /bin/bash ./build.sh`.

## Version 3.5.0 scope migration workflow

- Reads profile scope, limitations, exclusions, and individual-device counts.
- Preselects a Platform device group whose normalized name matches a scoped Jamf Pro group.
- Displays a scope banner and warns when exactly one computer or mobile device is directly scoped.
- Writes operational events to Apple Unified Logging under subsystem `com.jawheelr.blueprintcreator`.
- Includes a View Logs window with time and category predicates, copy, refresh, and export controls.
- Create Blueprint presents Create Only, Create and Deploy, and acknowledged Create/Deploy/Unscope choices.
- The destructive sequence creates the blueprint, deploys it, then unscopes the source profile.

## Hybrid Jamf backend in 3.5.0

The Jamf Pro backend can run in Automatic, Native API, or jamf-cli mode. Automatic is the default. The utility discovers jamf-cli at the configured path and standard Homebrew/local paths, validates the executable directly with `Process`, records its version in Unified Logging, and uses native API compatibility operations whenever structured profile scope XML or safe source-profile unscoping is required. Platform device groups, blueprint creation, and deployment remain native Platform API operations. No secret or token is placed in jamf-cli process arguments.


## Version 3.5.0 build correction

The jamf-cli command result now uses a dedicated `Sendable` result type rather than incompatible labeled and unlabeled tuple types. The subprocess runner executes inside the `JamfCLIService` actor, eliminating the concurrently-executed local continuation callback that produced the Swift 6 sendability warning.


## Version 3.5.0 build correction

The unified-log message in `JamfCLIService` is now a single `OSLogMessage` interpolation. Swift does not support concatenating two `OSLogMessage` values with `+`. The dedicated `Sendable` CLI result type and actor-isolated subprocess runner from 3.5.0 remain in place.


## Version 3.5.0 XML parser build correction

The complete `ProfileDetailParser` implementation has been restored. Version 2.3.8 accidentally truncated `XMLParsers.swift` immediately after assigning `result.payloads`, which removed the closing method/class braces and XML delegate methods. Version 3.5.0 preserves complete nested payload dictionaries while retaining all scope, description, and payload parsing callbacks.


## Version 3.5.0 deployment review and unscoping update

The deployment review has been redesigned with centered, full-width blue action buttons, paired source/target cards, clearer group status, and conditional unscoping controls. Jamf Pro unscoping now retrieves the actual profile XML, changes only nodes already present in the returned scope, tries a scope-only document using the actual root element, and retries with the complete modified profile XML. Both HTTP responses are reported if Jamf Pro rejects both update strategies.


## Version 3.5.0 distribution strategy

When a scoped source profile is migrated, the deployment review now offers Redistribute to Original and New Groups or Distribute to New Group Only. Redistribute scopes the blueprint to the automatically matched original Platform group plus the newly selected group, deploys the blueprint, and then unscopes the source profile. Distribute to New Group Only deploys only to the newly selected Platform group and then unscopes the source profile. Profiles that are already unscoped receive the normal Distribute to New Group action.


## Version 3.5.0 application-managed jamf-cli

Users can add a jamf-cli executable to the application context. The utility validates and copies it to `~/Library/Application Support/Blueprint Conversion Utility/CLI/jamf-cli`, gives the managed copy first discovery priority, and selects jamf-cli as the default blueprint-creation backend. Blueprint request JSON is passed through a temporary file, credentials are supplied through the subprocess environment rather than command-line arguments, and native Platform API creation is used automatically if the CLI command is unavailable or unsupported. Jamf Pro Classic API operations remain native for profile XML scope and unscoping compatibility.


## Version 3.5.0 title-bar and managed jamf-cli updater

The visible macOS window title text is hidden while preserving normal window controls and sidebar behavior. At launch, the utility queries the official Jamf-Concepts/jamf-cli latest-release metadata, chooses a macOS Apple Silicon or universal asset, downloads and extracts it, validates the executable with `--version`, and atomically installs it within the application-support context. The previous managed copy is restored if validation fails. The app also inspects `--help` for blueprint capability. Current CLI releases without blueprint commands are not invoked for blueprint creation; the working native Platform API backend remains active while the managed CLI is available for supported operations.


## Version 3.5.0 adaptive conversion planner

Each profile now receives a per-run payload compatibility plan. Verified legacy payloads are routed to the legacy configuration-profile component, payloads known to require a native component are blocked before submission, and unknown payloads are marked unverified rather than sent blindly. The mobile passcode payload is explicitly identified as requiring a verified native schema because the Platform rejected it in the legacy component. Platform groups retain computer/mobile/unknown family metadata and are filtered for the active workspace. Unknown-family groups remain visible with an explicit label. The three deployment actions and source-profile disposition popup remain phase protected.


## Version 3.5.0 jamf-cli diagnostics tab

Connections now includes a dedicated `jamf-cli` tab. The tab has one diagnostic action, **Test jamf-cli**, and a contained scrollable monospaced output window. The test prefers the managed executable at `~/.local/bin/jamf-cli`, falls back to the app-bundled executable, runs only `--version`, and records the exact executable, source, query, stdout, stderr, exit code, duration, timestamp, and pass/fail result. Copy Output and Clear support simplify troubleshooting; no credentials, tokens, environment values, installation controls, update controls, path controls, or backend settings appear in the tab.


## Version 3.5.0 Platform-only API architecture

All network operations use the Jamf Platform API hostname, Platform OAuth client credentials, and the Platform Environment scope header. Computer and mobile configuration-profile listing, detail retrieval, and XML updates now use the Platform-published `/proclassic/osxconfigurationprofiles` and `/proclassic/mobiledeviceconfigurationprofiles` resources. Blueprint groups, blueprint creation, and blueprint deployment continue through native Platform resources. The separate Jamf Pro URL, client ID, client secret, token cache, API connection test, and Connections tab have been removed. Existing Platform secrets are migrated from the prior Keychain payload when available. Source-profile unscoping performs a Platform gateway PUT followed by a Platform gateway GET and reports success only after read-back verifies the scope is empty.


## Version 3.5.0 build correction

Removed the final stale `cliAvailable` reference from Platform profile loading and made the detached jamf-cli diagnostic helper explicitly `nonisolated`, resolving the Xcode 27 actor-isolation diagnostic. Profile loading now logs the Platform `/proclassic` gateway directly.


### Version 3.5.0 disabled payload filtering

The bundled Jamf `profileconvert` helper now enables its Blueprints compatibility filter. Payload types that Jamf Blueprints explicitly disables, including `com.apple.security.root`, `com.apple.security.pkcs1`, and `com.apple.vpn.managed`, are removed from the legacy configuration-profile component before blueprint creation. Converter warnings remain available in the conversion plan so excluded payloads are visible to the operator. This release also retains semantic empty-scope verification from 3.0.3.


## Version 3.5.0 knowledge base and application updates

The in-app Knowledge Base now documents the Platform-only architecture, conversion phases, bundled jamf-cli/profileconvert integration, payload compatibility and filtering, device groups, deployment safety, semantic unscoping, troubleshooting, and support workflows. The app checks `https://api.github.com/repos/jawheelr/Blueprint-Conversion-Utility/releases/latest` during launch and compares the release tag with the installed semantic version. A newer release opens a review window with release notes and a button to the official GitHub release page. Manual checks are available from the application menu and Knowledge Base. Updates are never installed silently.


## Version 3.5.0 weekly application update checks

**Check for Updates...** is available under the Help menu alongside Knowledge Base and the GitHub project link. The application runs an automatic GitHub Releases check on first launch, then no more than once every seven days. The last-attempt date is stored in `UserDefaults` as `BlueprintCreator.LastAppUpdateCheck`. The attempt date is recorded before the request so an unavailable network does not cause requests on every launch. Manual checks remain available at any time and restart the seven-day schedule.


## Version 3.5.0 application identity migration

The application bundle identifier, installer package identifier, generated profile payload identifier prefix, Keychain service, and Unified Logging subsystem are now `com.jawheelr.blueprintcreator`. On first launch under the new identity, the app imports saved settings and the weekly update-check date from the former `com.jarredwheeler.blueprintcreator` preferences domain when the new domain has no settings. Platform credentials are read from the new Keychain service first, then migrated from the previous service or the older two-secret payload. Existing legacy entries are left intact as a non-destructive fallback.


## Version 3.5.0 sidebar and stable profile selection

The profile type label is now a separate `PROFILE TYPE` heading above a full-width segmented control with its picker label hidden. The sidebar has a 260-point minimum width to prevent vertical label wrapping while remaining resizable. Profile-list selection is now keyed by profile ID rather than the mutable profile object. The selected row remains highlighted while details and conversion data load, displays an inline spinner, and ignores stale asynchronous responses when the user quickly selects another profile.


## Version 3.5.0 family-aware group auto-selection

Platform device groups now load and filter before source profiles are evaluated, ensuring source scope matching can populate the Deployment picker. Mobile mode exposes only confirmed mobile/iOS/iPadOS/tvOS groups; computer mode exposes only confirmed computer/macOS groups. Matching first uses an exact case-insensitive source group name, then a punctuation- and whitespace-normalized name within the same device family. Group family detection recognizes additional Platform metadata fields. Logs record the source group, selected Platform group, family, and matching method.


## Version 3.5.0 resilient GitHub update checks

Update discovery now uses the public GitHub `releases/latest` redirect instead of the rate-limited REST API. The final versioned release URL supplies the release tag, so no GitHub token is required. Successful automatic checks are scheduled every seven days; transient failures retry after 24 hours. Manual checks always run immediately and show friendly availability messages without exposing raw GitHub rate-limit JSON. This release also includes the 3.1.6 Swift compiler corrections and the one-hour default Unified Logs query.


## Version 3.5.0 guided update installation

When a newer GitHub release is detected, the update window now offers **Download and Install**. The app derives the versioned PKG asset URL from the public release tag, downloads `Blueprint-Conversion-Utility-<version>.pkg`, verifies the XAR package header, stores the package with restricted permissions under `~/Library/Application Support/Blueprint Conversion Utility/Updates`, and opens the native macOS Installer. The user remains in control and completes Installer confirmation and any required administrator authorization. If the expected PKG asset is missing or invalid, no installer is opened and a clear error is shown.


## Version 3.5.0 single application title

Removed the duplicate application name in the window toolbar while retaining the branded in-content header with the app icon, title, and subtitle. The detail navigation title and subtitle are explicitly empty, and the AppKit window configuration continues hiding the native title and document icon.


### Version 3.5.0 deployment pane resizing

The Deployment pane no longer uses a fixed 320-point width. Both children of the horizontal split view now provide flexible minimum, ideal, and maximum widths, allowing the visible divider to resize the Deployment area as expected while preserving usable minimum widths for the generated Blueprint editor and Deployment controls.


## Version 3.5.0 update relaunch lifecycle

After **Download and Install** validates the versioned PKG and opens macOS Installer, the current app launches a detached relaunch monitor and exits. The monitor watches the installed app bundle for up to 30 minutes. When `CFBundleShortVersionString` changes from the running version, the monitor opens the updated application. If installation is canceled or does not complete, the monitor expires without reopening the old version. macOS Installer remains responsible for package validation, user confirmation, and administrator authorization.


## Version 3.5.0 Environment-only credentials and expiration reminder

Connections now requires a Platform API URL, Client ID, Client Secret, Platform Environment ID, and API Client expiration date. Tenant ID has been removed from the UI, settings model, request clients, validation, and Platform headers. All scoped requests use `X-Environment-Id`. The footer reports credential health using calendar-day calculations: green when the tested credentials expire beyond the configured warning period, yellow when the expiration date is within the warning period (30 days by default), red when expired or authentication fails, and gray when expiration metadata is not configured or has not yet been tested. The expiration date and warning period are non-secret preferences; the Client Secret remains in macOS Keychain.

### Required Platform API Client permissions

- Deployment → Configuration Profiles: Read, Update
- Inventory → Device Groups: Read, Update
- Deployment → Blueprints: Deploy, Create, Read, Update

Create the API Client at the **Platform Environment** level, select the appropriate Platform Environment, record the Client ID, save the Client Secret when it is shown, and copy the Platform Environment ID into Connections.


## Version 3.5.0 first-round CLI and Developer ID build support

The Swift package now produces a `bcu` terminal executable alongside the graphical app. The PKG installs `/usr/local/bin/bcu` as a symbolic link to the signed CLI inside the application bundle. Initial commands include version information, non-secret connection status and testing, credential expiration status, computer/mobile profile listing, strict family-filtered device-group listing, Unified Log viewing/streaming, opening the GUI, and checking the latest tagged GitHub release. Text and JSON output are supported for automation where applicable. The CLI reads the GUI's Platform settings and Keychain secret and never prints the Client Secret.

`build.sh` now accepts `--sign-app`, `--sign-installer`, `--notary-profile`, `--skip-notarization`, `--version`, and `--arch`. With no signing options, local ad hoc builds continue to work. Developer ID builds sign each nested executable, the main app, and the installer; optional notarization submits and staples the PKG and DMG.

### CLI examples

```bash
bcu version
bcu connection status
bcu connection test
bcu credentials status
bcu profiles list --type computer
bcu profiles list --type mobile --output json
bcu groups list --type computer
bcu logs show --last 1h
bcu logs stream --category Deployment
bcu app open
bcu app check-for-updates
```

### Signed build example

```bash
./build.sh \
  --sign-app "Developer ID Application: Your Name (TEAMID)" \
  --sign-installer "Developer ID Installer: Your Name (TEAMID)" \
  --notary-profile blueprint-notary
```

## 3.5.0 Profile Takeover and GUI Editing

This isolated fork detects `jamf-cli pro blueprints import-profile --help` at application launch. When the command and expected flags are available, the Deployment Review changes from the standard Create Blueprint interface to a dedicated Profile Takeover interface. Preview uses `--dry-run`; creation uses the default preserve-installed behavior unless Convert is selected. The takeover path never invokes source-profile unscoping.

The middle editor can switch between GUI and JSON. The GUI presents workflow, import mode, source-scope behavior, verdict, reasons, and strict import controls. JSON shows the generated standard Blueprint or the takeover command/result plan. The footer creator label is removed and API expiration remains at the far right.

## 3.5.0 GUI parity and usability

The takeover GUI now represents every non-global `import-profile` option exposed in the JSON/command plan. Each control displays its corresponding CLI flag and a plain-language explanation. Unsupported controls are disabled based on runtime capability detection. The GUI also shows source profile identity and scope, source profile disposition, the exact non-secret jamf-cli command, verdict, warnings, and dropped-key diagnostics.

## 3.5.0 Final GUI and Takeover Workflow

Version 3.5.0 uses the current public jamf-cli release, detected dynamically at runtime. If `pro blueprints import-profile` is available, selecting Profile Takeover changes the right pane to Blueprint Takeover and automatically evaluates the selected profile with a debounced `--dry-run`.

The GUI and JSON views share the same Blueprint data. End users can edit the Blueprint name, description, first step name, activation condition, and component inclusion through guided controls. Each takeover switch is selectable in the GUI, displays its CLI mapping, and includes tooltip help. Knowledge Base walkthroughs cover automatic takeover evaluation and GUI/JSON editing.

### Final signed and notarized release

```bash
./build.sh \
  --sign-app "9244D7B494B37C12617975132DFA97F1F8241BE4" \
  --sign-installer "Developer ID Installer: Jarred Wheeler (PU669FP3N7)" \
  --notary-profile "blueprint-notary" \
  2>&1 | tee release-build.log
```

The build succeeds only after the app, package, and disk image complete their configured signature and notarization checks.

## 3.5.0 Usability refinement

The GUI is divided into Setup, Blueprint, and Properties sections. Setup presents only the guided workflow and keeps advanced import switches collapsed. Blueprint provides text fields for the commonly edited Blueprint values. Properties provides searchable, path-aware editing for scalar JSON values: booleans use Enabled/Disabled dropdowns, strings and numbers use text fields, and null values are shown as Not configured. Changes are serialized back to the same JSON document.

## 3.5.0 Dry Run and Recommendation refinement

A Dry Run switch is displayed in the Blueprint Editor header. While enabled, profile takeover evaluation is automatic and always non-modifying. Creation actions remain disabled until Dry Run is turned off. BCU now uses the source profile scope and jamf-cli verdict to recommend the safest next action. Profiles without a group scope are directed to choose a target group before evaluation. Technical evaluation details are collapsed by default.

## Version 3.5.0 Apple Schema Browser

The Help menu and application header now expose an Apple Schema Browser backed by a compiled copy of Apple's complete Device Management schema. The browser supports search across friendly names, identifiers, raw keys, descriptions, and nested paths; family and lifecycle filtering; Workgroup Manager-style disclosure arrows; platform support; lifecycle badges; wildcard keys; recursive references; and copy actions. The project includes the schema compiler under `Tools/SchemaCompiler` and the compiled runtime catalog under `Resources/AppleSchema`.
