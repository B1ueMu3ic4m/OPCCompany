import Foundation

#if canImport(SwiftUI)
// Apple platforms: the real SwiftUI observation machinery is already in scope
// for every file that needs it (they `import SwiftUI` directly). This file
// intentionally provides nothing extra there.
#else

// ═══ Windows/Linux observation compatibility layer ═══
// The core layer only uses ObservableObject + @Published for declaration
// (objectWillChange is never called — verified by grep across the module).
// On Windows there is no SwiftUI; the Flutter UI learns about state changes
// through the FFI change bus below instead of Combine publishers.

/// Minimal stand-in for `Combine.ObservableObject`.
public protocol ObservableObject: AnyObject {}

/// Property wrapper mirroring the subset of `@Published` the core layer uses:
/// wrappedValue read/write. A mutation notifies the global bus; the Flutter
/// side re-reads the snapshot through FFI on any notification, so per-object
/// routing is unnecessary (and a property wrapper cannot know its owner).
@propertyWrapper
public final class Published<Value> {
    private var value: Value

    public init(wrappedValue: Value) {
        self.value = wrappedValue
    }

    public var wrappedValue: Value {
        get { value }
        set {
            value = newValue
            OPCObservationBus.shared.publish()
        }
    }
}

/// Process-wide change bus for the compat layer. Listeners are addressable
/// tokens (added/removed by handle) — the M3 FFI layer subscribes when a UI
/// client connects and MUST unsubscribe on disconnect, so a leaking closure
/// list is also a memory leak of whatever it captures.
public final class OPCObservationBus: @unchecked Sendable {
    /// Opaque handle returned by addListener; pass to removeListener.
    public struct Token: Hashable { let id: UInt64 }

    public static let shared = OPCObservationBus()
    private var listeners: [Token: () -> Void] = [:]
    private var nextID: UInt64 = 1
    private let lock = NSLock()

    @discardableResult
    public func addListener(_ listener: @escaping () -> Void) -> Token {
        lock.lock(); defer { lock.unlock() }
        let token = Token(id: nextID); nextID += 1
        listeners[token] = listener
        return token
    }

    public func removeListener(_ token: Token) {
        lock.lock(); listeners.removeValue(forKey: token); lock.unlock()
    }

    func publish() {
        lock.lock()
        let snapshot = Array(listeners.values)
        lock.unlock()
        for listener in snapshot { listener() }
    }
}

#endif
