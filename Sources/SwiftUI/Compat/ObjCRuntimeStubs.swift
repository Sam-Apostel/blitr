// Code written for Apple platforms can use Objective-C interop that Swift on Linux compiles but cannot link:
// a `@convention(block)` closure returning an object emits calls to the Objective-C runtime's autorelease
// entry points. There is no Objective-C runtime or autorelease pool here, so these return their argument;
// the object simply stays alive. The swizzling such code usually feeds (`class_replaceMethod`) is inert in
// the ObjectiveC shim, so the blocks are never called while a frame is rendered.
// On Darwin libobjc defines these symbols for real (and is always loaded), so the stubs compile out.

#if !canImport(Darwin)

@_cdecl("objc_autoreleaseReturnValue")
public func _objc_autoreleaseReturnValue(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { object }

@_cdecl("objc_retainAutoreleasedReturnValue")
public func _objc_retainAutoreleasedReturnValue(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { object }

@_cdecl("objc_retainAutoreleaseReturnValue")
public func _objc_retainAutoreleaseReturnValue(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { object }

@_cdecl("objc_autorelease")
public func _objc_autorelease(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { object }
#endif
