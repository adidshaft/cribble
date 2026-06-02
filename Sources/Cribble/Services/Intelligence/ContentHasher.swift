import Foundation

/// Fast, dependency-free content hashing for incremental intelligence work.
///
/// We use 64-bit FNV-1a: it is not cryptographic, but content hashing here only
/// needs to answer "did these bytes change?" for cache invalidation and the
/// `inputHash` skip check in `JobQueue`. FNV-1a is tiny, allocation-free, and
/// streams a byte at a time, which keeps Tier-1 scanning cheap even on large
/// vaults. Output is a lowercase 16-char hex string.
enum ContentHasher {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    /// Hash raw bytes.
    static func hash(_ data: Data) -> String {
        var hash = offsetBasis
        data.withUnsafeBytes { raw in
            for byte in raw {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
        }
        return hex(hash)
    }

    /// Hash a UTF-8 string.
    static func hash(_ string: String) -> String {
        hash(Data(string.utf8))
    }

    /// Combine several already-computed hashes into one stable hash, independent
    /// of input order? No — order matters here (e.g. ordered file lists). Callers
    /// that need order-independence should sort first.
    static func combine(_ hashes: [String]) -> String {
        hash(hashes.joined(separator: "\u{1}"))
    }

    /// Hash the contents of a file. Returns nil if the file can't be read.
    static func hashFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return hash(data)
    }

    private static func hex(_ value: UInt64) -> String {
        String(format: "%016llx", value)
    }
}
