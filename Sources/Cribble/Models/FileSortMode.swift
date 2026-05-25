import Foundation

enum FileSortMode: String, CaseIterable, Identifiable {
    case name
    case created
    case modified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .created: "Created"
        case .modified: "Updated"
        }
    }
}
