import Foundation

/// `swiftui-screenshot devices`: the table lives in the runtime module, so build (once, cached) a
/// trivial runner against it and ask it with `--list-devices`.
func listDevices(_ installation: Installation) -> Never {
    guard !installation.swiftc.isEmpty else { fail("swiftc not found. Install a Swift 6 toolchain and put it on PATH, or set SWIFTC.") }
    let moduleStamp = (try? FileManager.default.attributesOfItem(atPath: installation.sdk + "/libSwiftUI.so"))
        .map { "\($0[.size] ?? 0)-\(($0[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)" } ?? ""
    let cacheRoot = ProcessInfo.processInfo.environment["SWIFTUI_SCREENSHOT_CACHE"] ?? (NSHomeDirectory() + "/.cache/swiftui-screenshot")
    let work = cacheRoot + "/devices-" + hash(["devices", moduleStamp, installation.swiftc])
    let runner = work + "/runner"
    if !FileManager.default.isExecutableFile(atPath: runner) {
        try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        let main = work + "/main.swift"
        try? "import SwiftUI\n\nMainActor.assumeIsolated { SwiftUI._ScreenshotRunner.run([]) }\n".write(toFile: main, atomically: true, encoding: .utf8)
        let result = run(installation.swiftc, ["-swift-version", "5", "-Onone", "-module-name", "App", "-no-color-diagnostics",
                                               "-I", installation.sdk, "-L", installation.sdk, "-lSwiftUI", "-lCombine", "-lUIKit",
                                               "-Xlinker", "-rpath", "-Xlinker", installation.sdk, main, "-o", runner])
        guard result.status == 0 else {
            FileHandle.standardError.write(Data((result.stderr + result.stdout).utf8))
            fail("could not build the device listing runner")
        }
    }
    let listing = run(runner, ["--list-devices"])
    guard listing.status == 0 else { fail("device listing failed:\n\(listing.stderr)") }
    print(listing.stdout, terminator: "")
    exit(0)
}
