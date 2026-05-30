import SwiftUI

private struct ReaderPrimaryFontNameKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct ReaderMonospaceFontNameKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// User-chosen body font family (nil = system). Injected by the reader so
    /// deeply nested text views can pick it up without prop-drilling.
    var readerPrimaryFontName: String? {
        get { self[ReaderPrimaryFontNameKey.self] }
        set { self[ReaderPrimaryFontNameKey.self] = newValue }
    }

    /// User-chosen monospace font family (nil = system monospace).
    var readerMonospaceFontName: String? {
        get { self[ReaderMonospaceFontNameKey.self] }
        set { self[ReaderMonospaceFontNameKey.self] = newValue }
    }
}
