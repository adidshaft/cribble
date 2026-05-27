import CoreServices
import Foundation

/// Watches a set of root directories for filesystem changes and fires a
/// debounced callback on the main actor.
///
/// The previous implementation polled every 2 seconds by `stat`-ing every
/// markdown file in the tree to compute a signature, which is O(files) of
/// I/O work twice per second per second of inactivity. For a 5k-note vault
/// that's 2500 stat calls per second of idle, plus a 2-second lag on every
/// edit. FSEvents is kernel-driven: it costs effectively nothing while idle
/// and notifies us within sub-second when something actually changes.
@MainActor
final class FileChangeMonitor: @unchecked Sendable {

    private var stream: FSEventStreamRef?
    private var userCallback: (@MainActor @Sendable () -> Void)?
    private var debounceTask: Task<Void, Never>?
    private static let debounceInterval: Duration = .milliseconds(250)
    private static let latencySeconds: CFTimeInterval = 0.5

    func start(rootURL: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        start(rootURLs: [rootURL], onChange: onChange)
    }

    func start(rootURLs: [URL], onChange: @escaping @MainActor @Sendable () -> Void) {
        stop()
        guard !rootURLs.isEmpty else { return }

        userCallback = onChange

        let paths = rootURLs.map(\.path) as CFArray

        // We pass `self` to the FSEventStream via its `info` pointer. The
        // stream may deliver events after our owning object thinks it's done
        // (tests routinely drop the store without calling stop), so we wire
        // up CFRetain/CFRelease callbacks: the stream takes a +1 on start,
        // releases it on invalidate, and self stays alive long enough for
        // the final callbacks to drain.
        let retainCallback: CFAllocatorRetainCallBack = { ptr in
            guard let ptr else { return nil }
            _ = Unmanaged<FileChangeMonitor>.fromOpaque(ptr).retain()
            return ptr
        }
        let releaseCallback: CFAllocatorReleaseCallBack = { ptr in
            guard let ptr else { return }
            Unmanaged<FileChangeMonitor>.fromOpaque(ptr).release()
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: retainCallback,
            release: releaseCallback,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<FileChangeMonitor>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in
                monitor.scheduleDebouncedFire()
            }
        }

        // kFSEventStreamCreateFlagFileEvents: get per-file events instead of
        // coarse directory-changed events. Combined with the latency parameter
        // FSEvents already coalesces bursts; we add a 250ms debounce on top so
        // a save-storm (e.g. an editor that touches several files in sequence)
        // produces a single refresh.
        let flags: UInt32 = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latencySeconds,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        userCallback = nil

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleDebouncedFire() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard let self, !Task.isCancelled else { return }
            self.userCallback?()
        }
    }
}
