import Foundation

/// Abstraction over `UserDefaults` for reading and writing settings values.
public protocol SettingsValueStore: AnyObject {
    /// Returns the object associated with the given key, or `nil`.
    func object(forKey defaultName: String) -> Any?
    /// Returns the string associated with the given key, or `nil`.
    func string(forKey defaultName: String) -> String?
    /// Returns the Boolean value associated with the given key.
    func bool(forKey defaultName: String) -> Bool
    /// Sets the value for the given key.
    func set(_ value: Any?, forKey defaultName: String)
    /// Removes the value associated with the given key.
    func removeObject(forKey defaultName: String)
}

/// Concrete ``SettingsValueStore`` backed by `UserDefaults`.
public final class UserDefaultsSettingsValueStore: SettingsValueStore {
    private let defaults: UserDefaults

    /// Creates a value store wrapping the given `UserDefaults` instance.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Returns the object for the given key from `UserDefaults`.
    public func object(forKey defaultName: String) -> Any? {
        defaults.object(forKey: defaultName)
    }

    /// Returns the string for the given key from `UserDefaults`.
    public func string(forKey defaultName: String) -> String? {
        defaults.string(forKey: defaultName)
    }

    /// Returns the Boolean value for the given key from `UserDefaults`.
    public func bool(forKey defaultName: String) -> Bool {
        defaults.bool(forKey: defaultName)
    }

    /// Sets the value for the given key in `UserDefaults`.
    public func set(_ value: Any?, forKey defaultName: String) {
        defaults.set(value, forKey: defaultName)
    }

    /// Removes the value for the given key in `UserDefaults`.
    public func removeObject(forKey defaultName: String) {
        defaults.removeObject(forKey: defaultName)
    }
}
