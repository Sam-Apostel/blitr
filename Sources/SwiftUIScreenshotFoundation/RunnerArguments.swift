import Foundation

/// The runner's own options. Normally they are its command line. With `--arg`, the rendered program's
/// command line is its launch arguments (so `ProcessInfo.processInfo.arguments` and `CommandLine.arguments`
/// read what an app launched with them would), and the tool passes the runner's options as a JSON array in
/// `SWIFTUI_SCREENSHOT_RUNNER_ARGUMENTS`, which is removed from the environment once read.
public enum _RunnerArguments {
    public static let variable = "SWIFTUI_SCREENSHOT_RUNNER_ARGUMENTS"

    /// The executable path followed by the runner's options, like `CommandLine.arguments`.
    public static let all: [String] = {
        let executable = CommandLine.arguments.first ?? "runner"
        guard let raw = getenv(variable) else { return CommandLine.arguments }
        let json = String(cString: raw)
        unsetenv(variable)
        guard let options = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String] else {
            return CommandLine.arguments
        }
        return [executable] + options
    }()
}
