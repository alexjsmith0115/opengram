import Foundation

/// Discriminator for the global hotkey fire path. Routed by AppDelegate
/// to the appropriate coordinator (CheckCoordinator for `.check`,
/// RewriteCoordinator for `.rewrite`).
enum HotkeyAction: Sendable, Equatable {
    case check
    case rewrite
}
