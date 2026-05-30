import Foundation

enum ReaderFontSizePreset: String, CaseIterable, Identifiable {
    case xxs
    case xs
    case small
    case medium
    case large
    case xl
    case xxl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xxs: "XXS"
        case .xs: "XS"
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .xl: "XL"
        case .xxl: "XXL"
        }
    }

    var scale: Double {
        switch self {
        case .xxs: 0.55
        case .xs: 0.68
        case .small: 0.82
        case .medium: 1.0
        case .large: 1.1
        case .xl: 1.2
        case .xxl: 1.3
        }
    }

    static func closest(to scale: Double) -> Self {
        allCases.min { abs($0.scale - scale) < abs($1.scale - scale) } ?? .medium
    }
}
