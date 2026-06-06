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

    /// Compact label for the input-bar chip (keeps it narrow).
    var shortName: String {
        if speedLabel == "Flash" { return "Flash" }
        return name.split(separator: " ").first.map(String.init) ?? name
    }
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
            approximateSize: "~4.9 GB",
            blurb: "Google Gemma 4 E4B — balanced default for notes and linking.",
            recommendedMemoryGB: 8
        ),
        LocalModel(
            id: "mlx-community/gemma-4-e2b-it-4bit",
            name: "Gemma 4 Flash",
            speedLabel: "Flash",
            approximateSize: "~3.4 GB",
            blurb: "Google Gemma 4 E2B — fastest Gemma option, but still a multi-GB download.",
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
            // 4-bit MLX quant of google/gemma-4-12B-it — the on-device-runnable
            // form of Google's 12B Gemma. Heavy: gated behind the RAM check so it
            // won't load on Macs without enough unified memory.
            id: "mlx-community/gemma-4-12b-it-4bit",
            name: "Gemma 4 12B",
            speedLabel: "Deep",
            approximateSize: "~7.0 GB",
            blurb: "Google Gemma 4 12B — the most capable on-device option for deep analysis. Needs a high-memory Mac.",
            recommendedMemoryGB: 24
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

    /// Whether on-device (MLX) execution is even compiled into this build. False
    /// for plain `swift build` CLI/dev builds; true for the shipped App Store /
    /// DMG app. Drives whether the first-run chooser can default to local.
    static var isOnDeviceAvailable: Bool {
        #if canImport(MLXLLM)
        return true
        #else
        return false
        #endif
    }

    /// The local model we recommend for first-time on-device users — the
    /// fastest/smallest Gemma so the initial download is as light as possible.
    static var recommendedOnDevice: LocalModel? {
        localModels.first { $0.speedLabel == "Flash" } ?? localModels.first
    }

    /// The model selected on first launch before the user makes an explicit
    /// choice. Prefers on-device when this build supports it (local-first), and
    /// falls back to a cloud CLI provider in builds without MLX compiled so the
    /// HUD still works out of the box.
    static var defaultModel: LocalModel {
        if isOnDeviceAvailable, let local = recommendedOnDevice { return local }
        return cloudModels.first ?? all[0]
    }

    static func model(withID id: String) -> LocalModel? {
        all.first { $0.id == id }
    }
}
