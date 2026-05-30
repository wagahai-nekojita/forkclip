import OSLog

enum AppLogger {
    private static let subsystem = "com.user.forkclip"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let database = Logger(subsystem: subsystem, category: "database")
    static let security = Logger(subsystem: subsystem, category: "security")
    static let migration = Logger(subsystem: subsystem, category: "migration")
}
