import Testing
import AppKit
@testable import OpenGramLib

@MainActor
@Suite("OverlayController.hideUnderlines / showUnderlines")
struct OverlayControllerHideUnderlinesTests {

    @Test func shouldHideUnderline_overlapDetection_positive() {
        let ctrl = OverlayController()
        ctrl.hiddenParagraphScalarRange = (scalarStart: 10, scalarLength: 20)
        #expect(ctrl.shouldHideUnderline(scalarStart: 12, scalarLength: 3) == true)   // inside
        #expect(ctrl.shouldHideUnderline(scalarStart: 5, scalarLength: 10) == true)   // left overlap
        #expect(ctrl.shouldHideUnderline(scalarStart: 25, scalarLength: 10) == true)  // right overlap
        #expect(ctrl.shouldHideUnderline(scalarStart: 10, scalarLength: 20) == true)  // identical
    }

    @Test func shouldHideUnderline_overlapDetection_negative() {
        let ctrl = OverlayController()
        ctrl.hiddenParagraphScalarRange = (scalarStart: 10, scalarLength: 20)
        #expect(ctrl.shouldHideUnderline(scalarStart: 0, scalarLength: 5) == false)    // left of
        #expect(ctrl.shouldHideUnderline(scalarStart: 30, scalarLength: 5) == false)   // right of
        #expect(ctrl.shouldHideUnderline(scalarStart: 0, scalarLength: 10) == false)   // abuts start
        #expect(ctrl.shouldHideUnderline(scalarStart: 30, scalarLength: 5) == false)   // abuts end
    }

    @Test func shouldHideUnderline_noStoredRange_returnsFalse() {
        let ctrl = OverlayController()
        ctrl.hiddenParagraphScalarRange = nil
        #expect(ctrl.shouldHideUnderline(scalarStart: 10, scalarLength: 5) == false)
    }

    @Test func hideUnderlines_storesRange_showUnderlines_clearsIt() {
        let ctrl = OverlayController()
        ctrl.hideUnderlines(inParagraphScalarRange: (scalarStart: 0, scalarLength: 100))
        #expect(ctrl.hiddenParagraphScalarRange != nil)
        ctrl.showUnderlines()
        #expect(ctrl.hiddenParagraphScalarRange == nil)
    }
}
