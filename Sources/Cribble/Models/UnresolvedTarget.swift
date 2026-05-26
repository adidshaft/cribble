import Foundation

struct UnresolvedTarget: Identifiable, Equatable {
    var id: String { targetName }
    let targetName: String
    let folderURL: URL
}
