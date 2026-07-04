import Foundation

enum Fixture {
    static func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CribbleTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// In-memory `UserDefaults` for tests. Persistent suites — even UUID-named
/// throwaways that call `removePersistentDomain` afterwards — leave empty
/// stub plists in ~/Library/Preferences, because cfprefsd flushes the domain
/// asynchronously after the test process exits (840 had accumulated). This
/// subclass keeps everything in a dictionary so cfprefsd is never involved.
final class EphemeralDefaults: UserDefaults, @unchecked Sendable {
    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    init() {
        // The superclass instance is never written to: every accessor the
        // code under test uses is overridden below.
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { storage[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock {
            if let value {
                storage[defaultName] = value
            } else {
                _ = storage.removeValue(forKey: defaultName)
            }
        }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { _ = storage.removeValue(forKey: defaultName) }
    }

    override func string(forKey defaultName: String) -> String? {
        object(forKey: defaultName) as? String
    }

    override func stringArray(forKey defaultName: String) -> [String]? {
        object(forKey: defaultName) as? [String]
    }

    override func array(forKey defaultName: String) -> [Any]? {
        object(forKey: defaultName) as? [Any]
    }

    override func data(forKey defaultName: String) -> Data? {
        object(forKey: defaultName) as? Data
    }

    override func bool(forKey defaultName: String) -> Bool {
        object(forKey: defaultName) as? Bool ?? false
    }

    override func integer(forKey defaultName: String) -> Int {
        object(forKey: defaultName) as? Int ?? 0
    }

    override func double(forKey defaultName: String) -> Double {
        object(forKey: defaultName) as? Double ?? 0
    }

    override func synchronize() -> Bool { true }
}
