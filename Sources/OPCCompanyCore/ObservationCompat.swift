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

/// Process-wide change bus for the compat layer.
public final class OPCObservationBus: @unchecked Sendable {
    public static let shared = OPCObservationBus()
    private var listeners: [() -> Void] = []
    private let lock = NSLock()

    public func addListener(_ listener: @escaping () -> Void) {
        lock.lock(); listeners.append(listener); lock.unlock()
    }

    func publish() {
        lock.lock()
        let snapshot = listeners
        lock.unlock()
        for listener in snapshot { listener() }
    }
}

#endif
