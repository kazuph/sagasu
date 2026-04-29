import Foundation

struct LaunchConfiguration {
    let showOnLaunch: Bool
    let snapshotPath: String?

    static let current = parse(CommandLine.arguments)

    private static func parse(_ arguments: [String]) -> LaunchConfiguration {
        var showOnLaunch = false
        var snapshotPath: String?

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--show-on-launch":
                showOnLaunch = true
            case "--snapshot":
                let nextIndex = index + 1
                if arguments.indices.contains(nextIndex) {
                    snapshotPath = arguments[nextIndex]
                    showOnLaunch = true
                    index += 1
                }
            default:
                break
            }
            index += 1
        }

        return LaunchConfiguration(showOnLaunch: showOnLaunch, snapshotPath: snapshotPath)
    }
}
