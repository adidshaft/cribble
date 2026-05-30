import SwiftUI

/// The model "chip" in the input bar. Opens a popover that groups on-device and
/// cloud models and shows each model's state with a light trailing icon:
/// download arrow (not downloaded), check (downloaded), cloud (cloud provider).
struct ModelPickerButton: View {
    @ObservedObject var viewModel: ChatHUDViewModel
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            chip
        }
        .buttonStyle(.plain)
        .help("Choose model")
        .pointingHandOnHover()
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            ModelPickerList(viewModel: viewModel) { showPopover = false }
        }
    }

    private var dotColor: Color {
        switch viewModel.selectedModel.kind {
        case .localMLX: .blue
        case .claudeCLI, .codexCLI: .green
        }
    }

    private var chip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
                .shadow(color: dotColor.opacity(0.6), radius: 2)
            Text(viewModel.selectedModel.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75) }
        .fixedSize()
    }
}

/// The list inside the picker popover.
struct ModelPickerList: View {
    @ObservedObject var viewModel: ChatHUDViewModel
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            section(title: "ON-DEVICE", models: ModelCatalog.localModels)
            if !ModelCatalog.cloudModels.isEmpty {
                Divider().padding(.vertical, 4)
                section(title: "CLOUD", models: ModelCatalog.cloudModels)
            }

            Divider().padding(.vertical, 4)
            Text("On-device models download once (~1–3 GB) the first time you use them. Cloud models run through your installed CLI.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .frame(width: 260, alignment: .leading)
        }
        .padding(8)
        .frame(width: 280)
    }

    private func section(title: String, models: [LocalModel]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)

            ForEach(models) { model in
                ModelRow(
                    model: model,
                    isSelected: model.id == viewModel.selectedModel.id,
                    availability: viewModel.availability(of: model)
                ) {
                    viewModel.selectModel(model)
                    onSelect()
                }
            }
        }
    }
}

private struct ModelRow: View {
    let model: LocalModel
    let isSelected: Bool
    let availability: ModelAvailability
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary.opacity(0.4))

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name)
                        .font(.system(size: 12, weight: .medium))
                    Text(model.kind.isCloud ? model.speedLabel : model.approximateSize)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                stateIcon
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .pointingHandOnHover()
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch availability {
        case .cloud:
            Image(systemName: "cloud")
                .foregroundStyle(.secondary)
                .help("Runs in the cloud")
        case .downloaded:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
                .help("Downloaded")
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.blue)
                .help("Downloads on first use")
        }
    }
}
