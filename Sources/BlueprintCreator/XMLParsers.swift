import Foundation

final class ProfileListParser: NSObject, XMLParserDelegate {
    private var results: [JamfProfile] = []
    private var stack: [String] = []
    private var text = ""
    private var profileID = ""
    private var profileName = ""
    private var profileDepth: Int?
    private let profileElements: Set<String> = [
        "configuration_profile", "os_x_configuration_profile",
        "osx_configuration_profile", "mobile_device_configuration_profile"
    ]

    func parse(_ data: Data) throws -> [JamfProfile] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? AppFailure.message("Unable to parse the Platform profile list.")
        }
        if results.isEmpty {
            // An empty list is valid; anything without a <size> element is not
            // a recognizable profile listing.
            guard String(decoding: data.prefix(4096), as: UTF8.self).contains("<size>") else {
                throw AppFailure.message("Platform profile gateway returned an unrecognized response.")
            }
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        stack.append(elementName)
        text = ""
        if profileElements.contains(elementName) {
            profileDepth = stack.count
            profileID = ""
            profileName = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if profileDepth != nil {
            if elementName == "id" && profileID.isEmpty { profileID = value }
            if elementName == "name" && profileName.isEmpty { profileName = value }
        }
        if profileElements.contains(elementName), profileDepth == stack.count {
            if !profileID.isEmpty {
                results.append(JamfProfile(
                    id: profileID,
                    name: profileName.isEmpty ? "Unnamed profile" : profileName
                ))
            }
            profileDepth = nil
        }
        if !stack.isEmpty { stack.removeLast() }
        text = ""
    }
}

final class ProfileDetailParser: NSObject, XMLParserDelegate {
    private var result = JamfProfile(id: "", name: "")
    private var stack: [String] = []
    private var text = ""
    private var descriptionText = ""
    private var payloadText = ""
    private var groupNames: [String] = []
    private var deviceCount = 0
    private var limitationCount = 0
    private var exclusionCount = 0
    private var otherTargetCount = 0
    private var allDevices = false

    func parse(_ data: Data, base: JamfProfile) throws -> JamfProfile {
        result = base
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? AppFailure.message("Unable to parse profile details.")
        }
        result.description = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        result.scope = ProfileScope(
            allDevices: allDevices,
            groupNames: Array(Set(groupNames)).sorted(),
            individualDeviceCount: deviceCount,
            limitationCount: limitationCount,
            exclusionCount: exclusionCount,
            otherTargetCount: otherTargetCount
        )
        parsePayloads()
        return result
    }

    private func parsePayloads() {
        let payload = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payload.data(using: .utf8), !payload.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any],
              let content = plist["PayloadContent"] as? [[String: Any]] else { return }
        result.payloads = content
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        stack.append(elementName)
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.dropLast().last ?? ""
        let inScope = stack.contains("scope")
        let inExclusions = stack.contains("exclusions")
        let inLimitations = stack.contains("limitations")

        if stack.contains("general") {
            if elementName == "description" { descriptionText += value }
            if elementName == "payloads" || elementName == "payload" { payloadText += value }
        }
        if inScope && (elementName == "all_computers" || elementName == "all_mobile_devices") {
            allDevices = value.lowercased() == "true"
        }
        if inScope && elementName == "name" && !value.isEmpty {
            if ["computer_group", "mobile_device_group"].contains(parent) {
                if inExclusions { exclusionCount += 1 }
                else if inLimitations { limitationCount += 1 }
                else { groupNames.append(value) }
            }
        }
        if inScope && elementName == "all_jss_users" && value.lowercased() == "true" {
            otherTargetCount += 1
        }
        if inScope && elementName == "name" && !value.isEmpty,
           ["building", "department", "user", "user_group", "jss_user", "jss_user_group", "network_segment"].contains(parent) {
            if inExclusions { exclusionCount += 1 }
            else if inLimitations { limitationCount += 1 }
            else { otherTargetCount += 1 }
        }
        if inScope && elementName == "id" && !value.isEmpty {
            if ["computer", "mobile_device"].contains(parent) {
                if inExclusions { exclusionCount += 1 }
                else if inLimitations { limitationCount += 1 }
                else { deviceCount += 1 }
            }
        }
        if !stack.isEmpty { stack.removeLast() }
        text = ""
    }
}
