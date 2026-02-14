import SwiftUI

struct GenerateOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let options: [ScheduleDraftOption]
    let onSelect: (ScheduleDraftOption) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.LiquidBackdrop()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if options.isEmpty {
                            EmptyStateView(
                                icon: "sparkles",
                                title: "No Options",
                                message: "No schedule options could be generated."
                            )
                        } else {
                            ForEach(options) { option in
                                optionCard(option)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.grid_2)
                    .safeAreaPadding(.horizontal, DesignSystem.Spacing.grid_1)
                    .safeAreaPadding(.bottom, DesignSystem.Spacing.grid_1)
                }
            }
            .navigationTitle("Generated Options")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func optionCard(_ option: ScheduleDraftOption) -> some View {
        let critical = option.warnings.filter { $0.severity == .critical }.count
        let warning = option.warnings.filter { $0.severity == .warning }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(option.name)
                    .font(DesignSystem.Typography.headline)
                Spacer()
                Text("Score \(option.score)")
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.surface.opacity(0.6))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Label("\(option.shifts.count) shifts", systemImage: "calendar")
                Label("\(critical) critical", systemImage: "exclamationmark.triangle.fill")
                Label("\(warning) warnings", systemImage: "exclamationmark.circle")
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(.secondary)

            Button {
                onSelect(option)
                dismiss()
            } label: {
                Label("Use This Option", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.surface.opacity(0.5))
        )
    }
}
