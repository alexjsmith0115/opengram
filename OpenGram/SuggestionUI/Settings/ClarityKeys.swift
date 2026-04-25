import Foundation

/// Single source of truth for the Clarity-tab AppStorage keys and their
/// default values. Referenced by `ClaritySettingsView` (UI), `HarperService`
/// (severity filter), and `AppDelegate` (master-toggle observer).
///
/// `@AppStorage` property wrappers in `ClaritySettingsView` cannot reference
/// these constants directly (the wrapper requires compile-time literals), so
/// the literals are duplicated there and pinned by `ClaritySettingsViewTests`.
enum ClarityKeys {
    static let clarityEnabledKey = "clarityEnabled"
    static let clarityOpinionatedEnabledKey = "clarityOpinionatedEnabled"
    static let defaultClarityEnabled: Bool = true
    static let defaultClarityOpinionatedEnabled: Bool = false
}
