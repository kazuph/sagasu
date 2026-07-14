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
func pixelAlignedFrameDoesNotExpandFractionalHalfFrames() {
    let left = WindowManager.pixelAlignedFrame(CGRect(x: 0, y: 0, width: 853.5, height: 100))
    let right = WindowManager.pixelAlignedFrame(CGRect(x: 853.5, y: 0, width: 853.5, height: 100))

    #expect(left.maxX == right.minX)
    #expect(left.intersection(right).isNull || left.intersection(right).width == 0)
    #expect(left == CGRect(x: 0, y: 0, width: 854, height: 100))
    #expect(right == CGRect(x: 854, y: 0, width: 853, height: 100))
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

@MainActor
@Test
func windowCommandDebugNamesRoundTrip() {
    let commands: [WindowManager.Command] = [
        .bottomHalf,
        .centerThird,
        .leftHalf,
        .maximize,
        .nextDisplay,
        .previousDisplay,
        .rightHalf,
        .topHalf
    ]

    for command in commands {
        #expect(WindowManager.Command.fromDebugName(command.debugName) == command)
    }
}

@MainActor
@Test
func windowCommandDebugNamesRejectUnknownValues() {
    #expect(WindowManager.Command.fromDebugName("") == nil)
    #expect(WindowManager.Command.fromDebugName("left") == nil)
}

@MainActor
@Test
func chromeEnhancedUserInterfaceGuardOnlyDisablesWhenOriginalValueIsTrue() {
    #expect(WindowManager.enhancedUserInterfaceGuardPlan(originalValue: true).shouldDisableBeforeOperation)
    #expect(WindowManager.enhancedUserInterfaceGuardPlan(originalValue: false).shouldDisableBeforeOperation == false)
    #expect(WindowManager.enhancedUserInterfaceGuardPlan(originalValue: nil).shouldDisableBeforeOperation == false)
}

@MainActor
@Test
func chromeEnhancedUserInterfaceRestoreRequiresOriginalTrueAndDisableSuccess() {
    #expect(WindowManager.shouldRestoreEnhancedUserInterface(originalValue: true, disableSucceeded: true))
    #expect(WindowManager.shouldRestoreEnhancedUserInterface(originalValue: true, disableSucceeded: false) == false)
    #expect(WindowManager.shouldRestoreEnhancedUserInterface(originalValue: false, disableSucceeded: true) == false)
    #expect(WindowManager.shouldRestoreEnhancedUserInterface(originalValue: nil, disableSucceeded: true) == false)
}

@MainActor
@Test
func chromeReadbackResultSeparatesMatchMismatchAndMissingReadback() {
    let target = CGRect(x: 10, y: 20, width: 300, height: 400)
    let withinTolerance = CGRect(x: 14, y: 24, width: 304, height: 396)
    let outsideTolerance = CGRect(x: 17, y: 20, width: 300, height: 400)

    #expect(
        WindowManager.chromeReadbackResult(
            targetFrame: target,
            actualFrame: withinTolerance
        ) == .matched(withinTolerance)
    )
    #expect(
        WindowManager.chromeReadbackResult(
            targetFrame: target,
            actualFrame: outsideTolerance
        ) == .mismatch(outsideTolerance)
    )
    #expect(
        WindowManager.chromeReadbackResult(
            targetFrame: target,
            actualFrame: nil
        ) == .mismatch(nil)
    )
}

@MainActor
@Test
func chromeReadbackResultAcceptsAnchoredMinimumSizeClamp() {
    let bottomTarget = CGRect(x: -589, y: -1790, width: 2560, height: 350)
    let bottomActual = CGRect(x: -589, y: -1909, width: 2560, height: 469)
    let rightTarget = CGRect(x: 691, y: -2489, width: 1280, height: 1049)
    let rightActual = CGRect(x: 491, y: -2489, width: 1480, height: 1049)

    #expect(
        WindowManager.chromeReadbackResult(
            targetFrame: bottomTarget,
            actualFrame: bottomActual,
            anchor: .bottom
        ) == .clamped(bottomActual)
    )
    #expect(
        WindowManager.chromeReadbackResult(
            targetFrame: rightTarget,
            actualFrame: rightActual,
            anchor: .right
        ) == .clamped(rightActual)
    )
    #expect(
        WindowManager.chromeReadbackResult(
            targetFrame: bottomTarget,
            actualFrame: bottomActual,
            anchor: nil
        ) == .mismatch(bottomActual)
    )
}

@MainActor
@Test
func chromeCorrectionOriginUsesMeasuredSizeForRightAndBottomAnchors() {
    let target = CGRect(x: 100, y: 200, width: 300, height: 400)

    #expect(
        WindowManager.correctionOrigin(
            targetFrame: target,
            measuredSize: CGSize(width: 360, height: 400),
            anchor: .right
        ) == CGPoint(x: 40, y: 200)
    )
    #expect(
        WindowManager.correctionOrigin(
            targetFrame: target,
            measuredSize: CGSize(width: 300, height: 480),
            anchor: .bottom
        ) == CGPoint(x: 100, y: 120)
    )
    #expect(
        WindowManager.correctionOrigin(
            targetFrame: target,
            measuredSize: CGSize(width: 360, height: 480),
            anchor: nil
        ) == target.origin
    )
}

@MainActor
@Test
func finderBundleIdentifierIsRecognizedWithoutMatchingOtherApps() {
    #expect(WindowManager.isFinderBundleIdentifier("com.apple.finder"))
    #expect(WindowManager.isFinderBundleIdentifier("com.google.Chrome") == false)
    #expect(WindowManager.isFinderBundleIdentifier(nil) == false)
}

@MainActor
@Test
func finderBoundsUsesFrameEdgesForAppleScriptBounds() {
    #expect(
        WindowManager.finderBounds(
            for: CGRect(x: 1971, y: -1945, width: 1920, height: 1049)
        ) == WindowManager.FinderBounds(
            left: 1971,
            top: -1945,
            right: 3891,
            bottom: -896
        )
    )
}

@MainActor
@Test
func finderFrameSettledAcceptsMinimumSizeClampOnlyAfterOriginMatches() {
    let target = CGRect(x: 2333, y: -1186, width: 486, height: 208)

    #expect(
        WindowManager.finderFrameSettled(
            targetFrame: target,
            actualFrame: CGRect(x: 2333, y: -1186, width: 495, height: 280)
        )
    )
    #expect(
        WindowManager.finderFrameSettled(
            targetFrame: target,
            actualFrame: CGRect(x: -106, y: -390, width: 495, height: 280)
        ) == false
    )
}

@MainActor
@Test
func finderFrameSettledRejectsMaximizeWhenFinderKeptOldWidth() {
    #expect(
        WindowManager.finderFrameSettled(
            targetFrame: CGRect(x: 1971, y: -1945, width: 1920, height: 1049),
            actualFrame: CGRect(x: 1971, y: -1945, width: 621, height: 1049)
        ) == false
    )
}
