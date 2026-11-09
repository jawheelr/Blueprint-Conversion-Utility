import Foundation

enum ProfileInspectorHelp {
    static let inspector = "Profile Inspector analyzes the selected Configuration Profile against Apple's schema. It explains configured values, lifecycle state, migration risk, and the recommended destination treatment. The source profile remains read-only."
    static let recommendation = "The recommendation describes what BCU believes should happen to this setting during migration. Keep preserves a current value. Convert maps a structured setting. Edit Before Conversion requests an administrator decision. Replace indicates a deprecated setting or newer representation. Remove indicates an Apple-removed setting. Preserve as Legacy keeps vendor or wildcard content in a profile wrapper. Review means BCU cannot safely decide automatically. Metadata identifies the payload and normally should not be edited."
    static let timing = "When to edit describes the safest point for resolving the finding. Before Blueprint creation means the value should be confirmed before generating the final destination. During BCU review means choose the intended representation while reviewing the conversion. After Blueprint creation means Jamf-side validation or adjustment may be needed. Do not edit means identifiers or metadata should normally remain stable."
    static let applyDestination = "Apply to Destination records an administrator-approved destination override for the generated Blueprint. It does not alter the Jamf source Configuration Profile. A native mapped setting may become a Jamf Blueprint GUI field. A setting without a native DDM equivalent is retained in a configuration-profile wrapper and may require BCU, profile-content, or API editing later."
    static let keepSource = "Keep Source Value preserves the currently configured value using the best supported destination representation. If a native DDM mapping exists, BCU can use the native component. Otherwise, BCU preserves the value in a configuration-profile wrapper."
    static let reviewLater = "Review Later deliberately leaves the finding unresolved. Dry Run may continue, but Review should continue to show the outstanding decision. High-risk unresolved findings may block deployment in a future release safeguard."
    static let proposedValue = "This field records the proposed destination value or administrator instruction. The field does not modify the source profile. For Boolean settings use true or false. For settings without a native mapping, the text documents how the wrapped setting should be preserved or handled."
    static let nativeEditability = "Native Blueprint/DDM components may be editable in Jamf's Blueprint GUI when Jamf exposes that component and property. API acceptance alone does not guarantee a full GUI editor."
    static let wrapperEditability = "Configuration-profile wrapper means BCU preserves the legacy payload content inside the Blueprint instead of creating a native DDM field. The Blueprint remains visible, but the individual wrapped key may require BCU, profile-content replacement, or API editing."
    static let schemaMatch = "Exact means the key matched Apple's schema at the current payload and nested path. Wildcard means Apple permits arbitrary keys at this location but does not define the vendor-specific key. Unknown means no Apple definition matched and administrator review is recommended."
    static let confidence = "Confidence reflects how deterministic the recommendation is. High usually comes from explicit Apple lifecycle or exact schema evidence. Medium combines schema evidence with compatibility guidance. Low indicates incomplete or ambiguous information. Confidence is not a guarantee of Jamf GUI editability."
    static let evidence = "Evidence lists the schema lifecycle, match type, configured value, payload type, or rule that led to the recommendation. Use evidence to distinguish an Apple-defined requirement from BCU compatibility guidance."
    static let actionNeeded = "Action Needed filters to payloads whose highest-priority findings require Review, Edit Before Conversion, Replace, or Remove decisions."
    static func recommendation(_ value: SettingRecommendation) -> String {
        switch value {
        case .keep: return "Keep: The setting matches a current Apple schema property. BCU recommends preserving the configured behavior unless conversion analysis reports a destination-specific conflict."
        case .convert: return "Convert: The setting is a structured Apple-defined value that should be translated into the supported Blueprint destination while preserving its child relationships."
        case .edit: return "Edit Before Conversion: Confirm or change the intended destination value before final Blueprint creation. Use Resolve Before Continuing to record the administrator decision. The Jamf source profile is not modified."
        case .replace: return "Replace: Apple marks the source setting as deprecated or a newer destination representation is preferred. Replace does not automatically mean changing true to false. Review whether a native component exists; otherwise preserve the setting in a profile wrapper."
        case .remove: return "Remove: Apple marks the setting as removed or unsupported for the relevant destination. Do not carry it forward without identifying a supported replacement."
        case .legacy: return "Preserve as Legacy: Apple permits the content through a wildcard or legacy payload, but no native destination field is known. BCU should retain it in a configuration-profile wrapper. Wrapped values may require BCU, profile-content replacement, or API editing later."
        case .review: return "Review: BCU cannot safely choose the destination representation automatically. Review the source value, Apple definition, dry-run findings, target devices, and related payloads before continuing."
        case .metadata: return "Metadata: This field identifies or describes the payload. Preserve identifiers and UUIDs unless BCU rewrites every related reference together."
        }
    }

    static func decision(_ value: OverrideDecision) -> String {
        switch value {
        case .apply: return applyDestination
        case .keepSource: return keepSource
        case .reviewLater: return reviewLater
        }
    }

    static let openSchema = "Open Schema Definition opens Apple's reference definition for investigation. The Schema Browser is diagnostic and does not change the profile or generated Blueprint."
}
