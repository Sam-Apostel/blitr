import Foundation

// What differs between the operating systems the tool runs on: library file names, loader paths, how a
// library names itself, and where the running executable is. Everything else in the tool is the same on
// Linux and macOS, so platform checks belong here and nowhere else.
//
// macOS support is in progress (issue #19): the Darwin branches are written to be correct but have not
// been built or run on a Mac yet.

enum HostPlatform {
    /// The engine's library: the SwiftUI module and every shim module linked into one dynamic library
    /// (Package.swift's `SwiftUIScreenshotEngine` product). Its file name must not be mistaken for Apple's
    /// SwiftUI; the module itself stays `SwiftUI`.
    static let engineLibrary = "SwiftUIScreenshotEngine"

    #if canImport(Darwin)
    /// The host's spelling in `#if os(...)`.
    static let osName = "macOS"
    static let sharedLibraryExtension = "dylib"
    /// The minimum macOS the engine is built for (Package.swift's `platforms`). Every compile against it
    /// targets this version, so the modules load whatever the compiler would default to.
    static let deploymentTarget = "15.0"
    #else
    static let osName = "Linux"
    static let sharedLibraryExtension = "so"
    #endif

    /// `libName.so` on Linux, `libName.dylib` on macOS.
    static func sharedLibraryFile(_ module: String) -> String {
        "lib\(module).\(sharedLibraryExtension)"
    }

    /// The module name of a library file (`libFoo.so` -> `Foo`), or nil if `file` is not one.
    static func libraryName(fromFile file: String) -> String? {
        let suffix = "." + sharedLibraryExtension
        guard file.hasPrefix("lib"), file.hasSuffix(suffix), file.count > 3 + suffix.count else { return nil }
        return String(file.dropFirst(3).dropLast(suffix.count))
    }

    /// Linker flags that give a library built for `module` its identity: the SONAME on Linux, the install
    /// name on macOS. Dependents find it through their rpaths in both cases.
    static func libraryIdentityFlags(_ module: String) -> [String] {
        #if canImport(Darwin)
        return ["-Xlinker", "-install_name", "-Xlinker", "@rpath/" + sharedLibraryFile(module)]
        #else
        return ["-Xlinker", "-soname=" + sharedLibraryFile(module)]
        #endif
    }

    /// Flags every swiftc invocation of the tool gets ahead of its own: none on Linux; on macOS the
    /// deployment target the engine's modules were built for.
    static var compilerFlags: [String] {
        #if canImport(Darwin)
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return ["-target", "\(arch)-apple-macosx\(deploymentTarget)"]
        #else
        return []
        #endif
    }

    /// The running executable, with symbolic links resolved (an installed tool is usually reached through
    /// a link in a bin directory, and the SDK is found next to the real file).
    static var executablePath: String {
        #if canImport(Darwin)
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return CommandLine.arguments[0] }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
        #else
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe")) ?? CommandLine.arguments[0]
        #endif
    }
}
