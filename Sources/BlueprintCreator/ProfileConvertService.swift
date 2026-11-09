import Foundation

struct ConvertedComponent: Decodable {
    let identifier: String
    let configuration: JSONValue
    var dictionary: [String: Any] { ["identifier": identifier, "configuration": configuration.value] }
}

struct ConversionResponse: Decodable {
    let success: Bool
    let displayName: String?
    let components: [ConvertedComponent]?
    let warnings: [String]?
    let conversions: [String]?
    let error: String?
}

indirect enum JSONValue: Decodable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .number(Double(v)) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }

    var value: Any {
        switch self {
        case .object(let v): return v.mapValues(\.value)
        case .array(let v): return v.map(\.value)
        case .string(let v): return v
        case .number(let v): return v.rounded() == v ? NSNumber(value: Int64(v)) : NSNumber(value: v)
        case .bool(let v): return v
        case .null: return NSNull()
        }
    }
}

actor ProfileConvertService {
    func convert(_ profile: JamfProfile) async throws -> ConversionResponse {
        let helper = try ManagedToolRepository.validatedConverter()
        let plist: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": "com.jawheelr.blueprintcreator.\(profile.id)",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": profile.name,
            "PayloadContent": profile.payloads
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        // The profile can contain secrets: use a private directory and remove it.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlueprintConversion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("source.mobileconfig")
        try data.write(to: input, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)

        let output = try await ProcessRunner.run(helper, ["--input", input.path], timeout: 120)
        guard !output.stdout.isEmpty else {
            throw AppFailure.message("profileconvert returned no JSON. \(output.stderrText)")
        }
        let response = try JSONDecoder().decode(ConversionResponse.self, from: output.stdout)
        guard output.status == 0, response.success else {
            throw AppFailure.message(response.error ?? output.stderrText)
        }
        return response
    }
}
