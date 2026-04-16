import Foundation
import os.log

/// Centralized logging. Each module gets a category-scoped Logger via `Log.logger(for:)`.
/// Subsystem is always the app bundle identifier.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.opengram"

    static func logger(for category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
