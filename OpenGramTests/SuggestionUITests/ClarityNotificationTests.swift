import Testing
import Foundation
@testable import OpenGramLib

@Suite struct ClarityNotificationTests {
    @Test func clarityMasterDidChange_rawValue_isStable() {
        #expect(Notification.Name.clarityMasterDidChange.rawValue == "ClarityMasterDidChange")
    }
}
