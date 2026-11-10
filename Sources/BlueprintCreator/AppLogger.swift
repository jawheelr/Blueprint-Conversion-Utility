import Foundation
import OSLog

struct AppLogger {
    static let subsystem = "com.jawheelr.blueprintcreator"
    static let connections = Logger(subsystem: subsystem, category: "Connections")
    static let profiles = Logger(subsystem: subsystem, category: "Profiles")
    static let scope = Logger(subsystem: subsystem, category: "Scope")
    static let groups = Logger(subsystem: subsystem, category: "Groups")
    static let blueprint = Logger(subsystem: subsystem, category: "Blueprint")
    static let deployment = Logger(subsystem: subsystem, category: "Deployment")
    static let errors = Logger(subsystem: subsystem, category: "Errors")
    static let ai = Logger(subsystem: subsystem, category: "Advisor")
}
