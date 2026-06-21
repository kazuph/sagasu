import Foundation
import Carbon
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

@MainActor
@Test
func windowCycleUsesPreviousAppliedFractionWhenAppAdjustsFrame() {
    #expect(
        WindowManager.nextCycleFraction(
            current: 0.61,
            previous: 1.0 / 4.0,
            isStillOnSameEdge: true
        ) == 2.0 / 3.0
    )
    #expect(
        WindowManager.nextCycleFraction(
            current: 0.61,
            previous: 2.0 / 3.0,
            isStillOnSameEdge: true
        ) == 3.0 / 4.0
    )
}

@MainActor
@Test
func windowCycleIgnoresPreviousFractionWhenCurrentWindowIsFullWidth() {
    #expect(
        WindowManager.nextCycleFraction(
            current: 1.0,
            previous: 2.0 / 3.0,
            isStillOnSameEdge: true
        ) == 1.0 / 2.0
    )
}

@MainActor
@Test
func windowCycleIgnoresPreviousFractionAfterManualMove() {
    #expect(
        WindowManager.nextCycleFraction(
            current: 0.61,
            previous: 2.0 / 3.0,
            isStillOnSameEdge: false
        ) == 1.0 / 2.0
    )
}

@MainActor
@Test
func appleScriptBoundsListUsesLeftTopRightBottom() {
    let frame = CGRect(x: 2430, y: -1409, width: 960, height: 1049)

    #expect(WindowManager.appleScriptBoundsList(for: frame) == "{2430, -1409, 3390, -360}")
}

@MainActor
@Test
func axVisibleFrameUsesPrimaryScreenTopForStackedDisplays() {
    let primaryFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)

    let mainVisible = WindowManager.axVisibleFrame(
        screenFrame: primaryFrame,
        visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 922),
        primaryScreenFrame: primaryFrame
    )
    #expect(mainVisible == CGRect(x: 0, y: 34, width: 1470, height: 922))

    let upperVisible = WindowManager.axVisibleFrame(
        screenFrame: CGRect(x: -1090, y: 956, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -1090, y: 956, width: 2560, height: 1440),
        primaryScreenFrame: primaryFrame
    )
    #expect(upperVisible == CGRect(x: -1090, y: -1440, width: 2560, height: 1440))

    let topVisible = WindowManager.axVisibleFrame(
        screenFrame: CGRect(x: -1090, y: 2396, width: 2560, height: 1080),
        visibleFrame: CGRect(x: -1090, y: 2396, width: 2560, height: 1080),
        primaryScreenFrame: primaryFrame
    )
    #expect(topVisible == CGRect(x: -1090, y: -2520, width: 2560, height: 1080))
}

@MainActor
@Test
func windowUsableFrameAvoidsUnsafeSecondaryDisplayTopEdge() {
    let primaryFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)
    let secondaryFrame = CGRect(x: 1470, y: 1316, width: 1920, height: 1080)

    let usable = WindowManager.windowUsableFrame(
        screenFrame: secondaryFrame,
        visibleFrame: secondaryFrame,
        primaryScreenFrame: primaryFrame
    )

    #expect(usable == CGRect(x: 1470, y: -1409, width: 1920, height: 1049))
}

@MainActor
@Test
func windowUsableFrameKeepsAlreadyInsetPrimaryDisplayVisibleFrame() {
    let primaryFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)
    let primaryVisible = CGRect(x: 0, y: 0, width: 1470, height: 922)

    let usable = WindowManager.windowUsableFrame(
        screenFrame: primaryFrame,
        visibleFrame: primaryVisible,
        primaryScreenFrame: primaryFrame
    )

    #expect(usable == CGRect(x: 0, y: 34, width: 1470, height: 922))
}

@MainActor
@Test
func bestScreenIndexUsesLargestIntersection() {
    let visibleFrames = [
        CGRect(x: 0, y: 0, width: 1000, height: 800),
        CGRect(x: 900, y: 0, width: 1000, height: 800)
    ]
    let mostlySecondScreen = CGRect(x: 880, y: 100, width: 800, height: 500)

    #expect(WindowManager.bestScreenIndex(for: mostlySecondScreen, in: visibleFrames) == 1)
}

@MainActor
@Test
func translatedFramePreservesRightHalfOnDestinationDisplay() {
    let source = CGRect(x: 1470, y: -1409, width: 1920, height: 1049)
    let destination = CGRect(x: 0, y: 34, width: 1470, height: 922)
    let rightHalf = CGRect(x: 2430, y: -1409, width: 960, height: 1049)

    let translated = WindowManager.translatedFrame(rightHalf, from: source, to: destination)

    #expect(translated == CGRect(x: 735, y: 34, width: 735, height: 922))
}

@MainActor
@Test
func translatedFramePreservesMaximizedWindowOnDestinationDisplay() {
    let source = CGRect(x: 1470, y: -1440, width: 1920, height: 1080)
    let destination = CGRect(x: -1090, y: -2520, width: 2560, height: 1080)
    let maximized = source

    let translated = WindowManager.translatedFrame(maximized, from: source, to: destination)

    #expect(translated == destination)
}

@MainActor
@Test
func translatedFramePreservesBottomHalfOnDestinationDisplay() {
    let source = CGRect(x: 1470, y: -1440, width: 1920, height: 1080)
    let destination = CGRect(x: -1090, y: -1440, width: 2560, height: 1440)
    let bottomHalf = CGRect(x: 1470, y: -900, width: 1920, height: 540)

    let translated = WindowManager.translatedFrame(bottomHalf, from: source, to: destination)

    #expect(translated == CGRect(x: -1090, y: -720, width: 2560, height: 720))
}

@MainActor
@Test
func windowHotKeyMonitorMapsHLIWithoutMixingCommands() {
    let flags: CGEventFlags = [.maskCommand, .maskControl, .maskShift]

    #expect(WindowHotKeyMonitor.command(keyCode: UInt32(kVK_ANSI_H), flags: flags) == .leftHalf)
    #expect(WindowHotKeyMonitor.command(keyCode: UInt32(kVK_ANSI_L), flags: flags) == .rightHalf)
    #expect(WindowHotKeyMonitor.command(keyCode: UInt32(kVK_ANSI_I), flags: flags) == .centerThird)
}
