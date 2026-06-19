import Foundation
import Testing
@testable import Sagasu

@MainActor
@Test
func windowCycleAdvancesFromCurrentFraction() {
    #expect(WindowManager.nextCycleFraction(current: 1.0 / 2.0) == 1.0 / 3.0)
    #expect(WindowManager.nextCycleFraction(current: 1.0 / 3.0) == 1.0 / 4.0)
    #expect(WindowManager.nextCycleFraction(current: 1.0 / 4.0) == 2.0 / 3.0)
    #expect(WindowManager.nextCycleFraction(current: 2.0 / 3.0) == 3.0 / 4.0)
    #expect(WindowManager.nextCycleFraction(current: 3.0 / 4.0) == 1.0 / 2.0)
}

@MainActor
@Test
func windowCycleStartsAtHalfForUnknownCurrentFraction() {
    #expect(WindowManager.nextCycleFraction(current: 0.61) == 1.0 / 2.0)
}

@MainActor
@Test
func windowCycleToleratesIntegralPixelRounding() {
    #expect(WindowManager.nextCycleFraction(current: 0.501) == 1.0 / 3.0)
    #expect(WindowManager.nextCycleFraction(current: 0.668) == 3.0 / 4.0)
}
