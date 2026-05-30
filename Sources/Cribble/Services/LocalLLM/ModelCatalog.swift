import Foundation

/// How a catalog entry is executed.
enum ModelKind: String, Hashable {
    /// On-device Apple MLX model (requires the Metal library; Xcode build).
    case localMLX
    /// Anthropic Claude via the local `claude` CLI (cloud).
    case claudeCLI
    /// OpenAI Codex via the local `codex` CLI (cloud).
    case codexCLI

    var isCloud: Bool { self != .localMLX }
}

/// A model the HUD can run — either an on-device MLX model or a cloud CLI
/// provider. Pure data (no MLX types), so this list is trivially editable and
/// safe to reference from any layer.
struct LocalModel: Identifiable, Hashable {
    /// Hugging Face repo id, e.g. `mlx-community/gemma-4-e4b-it-4bit`.
    /// Doubles as the stable identity used for download bookkeeping.
    let id: String
    /// Short display name shown in the model picker, e.g. "Gemma 4".
    let name: String
    /// One-word speed/size class surfaced as the input "Flash" chip.
    let speedLabel: String
    /// Human-readable approximate on-disk download size, e.g. "~2.0 GB".
    let approximateSize: String
    /// One-line description for the picker menu.
    let blurb: String
    /// Recommended minimum unified memory (GB). Drives a soft warning for the
    /// heavier models so users don't kick off an unusable download.
    let recommendedMemoryGB: Int
    /// Execution backend for this entry. Defaults to on-device MLX.
    var kind: ModelKind = .localMLX

    var huggingFaceRepo: String { id }
}

/// The curated set of models offered in the HUD. Ordering is the menu order.
/// Defaults favour small, fast Apple-Silicon-friendly models; the large Qwen
/// entry is opt-in and clearly flagged for its footprint.
enum ModelCatalog {
    static let all: [LocalModel] = [
        LocalModel(
            id: "mlx-community/gemma-4-e4b-it-4bit",
            name: "Gemma 4",
            speedLabel: "Balanced",
            approximateSize: "~2.0 GB",
            blurb: "Google Gemma 4 E4B — balanced default for notes and linking.",
            recommendedMemoryGB: 8
        ),
        LocalModel(
            id: "mlx-community/gemma-4-e2b-it-4bit",
            name: "Gemma 4 Flash",
            speedLabel: "Flash",
            approximateSize: "~1.2 GB",
            blurb: "Google Gemma 4 E2B — fastest, lightest, great on any Mac.",
            recommendedMemoryGB: 8
        ),
        LocalModel(
            id: "mlx-community/Qwen3.5-4B-MLX-4bit",
            name: "Qwen 3.5 4B",
            speedLabel: "Reasoning",
            approximateSize: "~2.9 GB",
            blurb: "Alibaba Qwen — strong logic and structured-edit reasoning.",
            recommendedMemoryGB: 12
        ),
        LocalModel(
            id: "cloud:claude",
            name: "Claude",
            speedLabel: "Cloud",
            approximateSize: "CLI",
            blurb: "Anthropic Claude via the local claude CLI. Needs claude installed.",
            recommendedMemoryGB: 0,
            kind: .claudeCLI
        ),
        LocalModel(
            id: "cloud:codex",
            name: "Codex",
            speedLabel: "Cloud",
            approximateSize: "CLI",
            blurb: "OpenAI Codex via the local codex CLI. Needs codex installed.",
            recommendedMemoryGB: 0,
            kind: .codexCLI
        )
    ]

    /// On-device MLX models (need the Metal library / Xcode build).
    static var localModels: [LocalModel] { all.filter { $0.kind == .localMLX } }
    /// Cloud CLI providers (work in any build with the CLI installed).
    static var cloudModels: [LocalModel] { all.filter { $0.kind.isCloud } }

    /// The model selected on first launch. Defaults to a cloud provider so the
    /// HUD works out of the box even in SwiftPM-CLI builds where MLX's Metal
    /// library isn't compiled; on-device models are one tap away in the picker.
    static var defaultModel: LocalModel { cloudModels.first ?? all[0] }

    static func model(withID id: String) -> LocalModel? {
        all.first { $0.id == id }
    }
}
