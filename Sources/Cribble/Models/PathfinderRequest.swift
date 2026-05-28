import Foundation

/// A request to bridge two notes, raised by dragging one note onto another in
/// the sidebar. Drives the Pathfinder HUD.
struct PathfinderRequest: Identifiable, Equatable {
    let id = UUID()
    let source: URL
    let target: URL
}
