import Foundation

/// Something the Platform API client may be allowed or refused to do.
enum PlatformCapability: String, CaseIterable, Identifiable, Sendable {
    case token, profilesRead, groupsRead, blueprintsRead
    case profilesUpdate, blueprintsCreate, blueprintsUpdate, blueprintsDeploy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .token: return "Access token"
        case .profilesRead: return "Configuration profiles (read)"
        case .groupsRead: return "Device groups (read)"
        case .blueprintsRead: return "Blueprints (read)"
        case .profilesUpdate: return "Configuration profiles (update scope)"
        case .blueprintsCreate: return "Blueprints (create)"
        case .blueprintsUpdate: return "Blueprints (update)"
        case .blueprintsDeploy: return "Blueprints (deploy and undeploy)"
        }
    }

    /// The permission to grant in the Jamf Platform API client.
    var grant: String {
        switch self {
        case .token: return "a valid Client ID and Client Secret"
        case .profilesRead: return "Deployment > Configuration Profiles: Read"
        case .groupsRead: return "Inventory > Device Groups: Read"
        case .blueprintsRead: return "Deployment > Blueprints: Read"
        case .profilesUpdate: return "Deployment > Configuration Profiles: Update"
        case .blueprintsCreate: return "Deployment > Blueprints: Create"
        case .blueprintsUpdate: return "Deployment > Blueprints: Update"
        case .blueprintsDeploy: return "Deployment > Blueprints: Deploy"
        }
    }

    /// Cannot be checked without changing something in Jamf, so it is checked when used.
    var checkedWhenUsed: Bool {
        switch self {
        case .profilesUpdate, .blueprintsCreate, .blueprintsUpdate, .blueprintsDeploy: return true
        default: return false
        }
    }

    var usedFor: String {
        switch self {
        case .token: return "Signing in to the Platform API"
        case .profilesRead: return "Listing and analyzing source profiles"
        case .groupsRead: return "Choosing a target group"
        case .blueprintsRead: return "Blueprints Explorer and deployment checks"
        case .profilesUpdate: return "Removing the source profile's scope (unscope)"
        case .blueprintsCreate: return "Creating Blueprints"
        case .blueprintsUpdate: return "Saving edits in the Blueprints Explorer"
        case .blueprintsDeploy: return "Deploying and undeploying Blueprints"
        }
    }
}

/// A Platform API failure in plain language, with what to do about it.
struct PlatformIssue: Sendable, Equatable {
    let capability: PlatformCapability?
    let status: Int
    let title: String
    let fix: String
    let raw: String

    var message: String {
        var text = "\(title) \(fix)"
        if status > 0 { text += " (HTTP \(status))" }
        return text
    }

    /// Full text including Jamf's own response, for Copy Details.
    var details: String {
        raw.isEmpty ? message : message + "\n\nJamf response:\n" + raw
    }

    static func capability(path: String, method: String) -> PlatformCapability? {
        let lower = path.lowercased()
        let verb = method.uppercased()
        if lower.contains("proclassic") { return verb == "GET" ? .profilesRead : .profilesUpdate }
        if lower.contains("device-groups") { return .groupsRead }
        if lower.contains("blueprint-components") { return .blueprintsRead }
        if lower.contains("blueprints") {
            if lower.hasSuffix("/deploy") || lower.hasSuffix("/undeploy") { return .blueprintsDeploy }
            switch verb {
            case "POST": return .blueprintsCreate
            case "PATCH", "PUT", "DELETE": return .blueprintsUpdate
            default: return .blueprintsRead
            }
        }
        return nil
    }

    static func classify(status: Int, body: String, path: String, method: String, isTokenRequest: Bool) -> PlatformIssue {
        let raw = String(body.prefix(500))
        let lowerBody = body.lowercased()
        func issue(_ capability: PlatformCapability?, _ title: String, _ fix: String) -> PlatformIssue {
            PlatformIssue(capability: capability, status: status, title: title, fix: fix, raw: raw)
        }
        if isTokenRequest {
            switch status {
            case 400, 401:
                return issue(.token, "Jamf did not issue an access token.",
                             "Check the Client ID and Client Secret. The secret is shown only once when the API client is created, so create a new one if it was lost. Also check the client is enabled and has not expired.")
            case 403:
                return issue(.token, "Jamf refused to issue a token to this API client.", "Check that the API client is enabled and allowed for this environment.")
            case 404:
                return issue(.token, "The Platform URL looks wrong.", "Use the regional URL from the Jamf Platform API client, for example https://us.apple.api.jamf.com.")
            default: break
            }
        }
        switch status {
        case 401:
            return issue(.token, "Jamf rejected the access token.", "Run Test Platform API again. If it keeps failing, the API client may be disabled or expired.")
        case 403:
            if let capability = capability(path: path, method: method) {
                return issue(capability, "This API client is not allowed to use \(capability.title.lowercased()).",
                             "In Jamf, edit the API client and grant \(capability.grant), then run Test Platform API again.")
            }
            return issue(nil, "This API client is not allowed to do that.", "Review the API client's permissions in Jamf against the list in the Knowledge Base.")
        case 404:
            return issue(nil, "Jamf could not find that resource.", "Check the Platform Environment ID and the Platform URL for this connection.")
        case 409:
            return issue(nil, "Jamf refused the change because of the Blueprint's current state.", "Reload it and try again. A Blueprint assigned to a division cannot be changed here.")
        case 429:
            return issue(nil, "Jamf is limiting requests.", "Wait a minute and try again.")
        case 500...599:
            return issue(nil, "Jamf had a problem handling the request.", "Try again shortly. If it continues, check Jamf's status page.")
        default:
            let hint = lowerBody.contains("invalid_client") ? " Jamf reports an invalid client." : ""
            return issue(capability(path: path, method: method), "The Platform request failed.\(hint)", raw.isEmpty ? "" : "Jamf said: \(raw)")
        }
    }
}

/// Result of one read-only access check.
struct PermissionCheck: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case ok
        case denied(PlatformIssue)
        case failed(String)
        case notChecked(String)
    }

    let capability: PlatformCapability
    let state: State
    var id: String { capability.rawValue }

    var isOK: Bool { state == .ok }

    var problem: String? {
        switch state {
        case .denied(let issue): return issue.message
        case .failed(let text): return text
        default: return nil
        }
    }

    static func result(_ capability: PlatformCapability, error: Error) -> PermissionCheck {
        if case AppFailure.platform(let issue) = error { return PermissionCheck(capability: capability, state: .denied(issue)) }
        if let urlError = error as? URLError {
            return PermissionCheck(capability: capability, state: .failed("Cannot reach Jamf (\(urlError.localizedDescription)). Check the Platform URL and your network."))
        }
        return PermissionCheck(capability: capability, state: .failed(error.localizedDescription))
    }
}
