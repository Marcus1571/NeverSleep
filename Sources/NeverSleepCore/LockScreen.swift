import Foundation

/// Lock the session via SACLockScreenImmediate (private login.framework symbol,
/// same call NoSleep's kext used through its helper; here as a plain dynamic
/// load). Respects the "Require password on display opening" option.
enum LockScreen {
    static func lock() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY) else {
            Log.error("lock screen: login.framework could not be loaded")
            return
        }
        defer { dlclose(handle) }
        typealias Fn = @convention(c) () -> Void
        guard let sym = dlsym(handle, "SACLockScreenImmediate") else {
            Log.error("lock screen: SACLockScreenImmediate symbol not found — behavior on later macOS changed; open an issue")
            return
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        Log.info("locking screen (lid close + suppression active)")
        fn()
    }
}
