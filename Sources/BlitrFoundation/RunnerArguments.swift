import Foundation

/// The runner's own options. A render's command line is the rendered program's launch arguments (`--arg`, none
/// by default), so `ProcessInfo.processInfo.arguments` and `CommandLine.arguments` read what an app launched with
/// them would; the tool passes the runner's options as a JSON array in `BLITR_RUNNER_ARGUMENTS`, which
/// is removed from the environment once read. Without it (listing previews, `compare`) they are the command line.
public enum _RunnerArguments {
    public static let variable = "BLITR_RUNNER_ARGUMENTS"

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
