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
        case .xxs: 0.65
        case .xs: 0.8
        case .small: 0.9
        case .medium: 1.0
        case .large: 1.15
        case .xl: 1.35
        case .xxl: 1.65
        }
    }

    static func closest(to scale: Double) -> Self {
        allCases.min { abs($0.scale - scale) < abs($1.scale - scale) } ?? .medium
    }
}
