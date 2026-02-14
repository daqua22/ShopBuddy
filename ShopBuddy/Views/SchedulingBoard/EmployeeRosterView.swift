import SwiftUI

struct EmployeeRosterView: View {
    @ObservedObject var viewModel: ScheduleBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_1) {
            Text("Roster")
                .font(DesignSystem.Typography.headline)

            HStack(spacing: 8) {
                Label("Available Now", systemImage: viewModel.onlyAvailableNow ? "checkmark.circle.fill" : "circle")
                    .font(DesignSystem.Typography.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(viewModel.onlyAvailableNow ? DesignSystem.Colors.accent.opacity(0.2) : DesignSystem.Colors.surface.opacity(0.45))
                    .clipShape(Capsule())
                    .onTapGesture {
                        viewModel.onlyAvailableNow.toggle()
                    }

                Menu {
                    Button("All Roles") {
                        viewModel.roleFilter = nil
                    }
                    ForEach(EmployeeRole.allCases, id: \.self) { role in
                        Button(role.rawValue) {
                            viewModel.roleFilter = role
                        }
                    }
                } label: {
                    Label(viewModel.roleFilter?.rawValue ?? "All Roles", systemImage: "line.3.horizontal.decrease.circle")
                        .font(DesignSystem.Typography.caption)
                }
                .menuStyle(.borderlessButton)

                Spacer()
            }

            TextField("Search employees", text: $viewModel.rosterSearch)
                .textFieldStyle(.roundedBorder)

            if viewModel.filteredEmployees.isEmpty {
                EmptyStateView(
                    icon: "person.2.slash",
                    title: "No Employees",
                    message: "No active employees match the current filters."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredEmployees, id: \.id) { employee in
                            rosterRow(employee)
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_1)
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 280)
        .glassCard()
    }

    private func rosterRow(_ employee: Employee) -> some View {
        let minutes = viewModel.scheduledMinutesByEmployee[employee.id, default: 0]
        let hours = Double(minutes) / 60.0
        let availability = viewModel.availabilityStatus(for: employee.id)

        return HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(statusColor(for: availability))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(employee.name)
                    .font(DesignSystem.Typography.body)
                    .lineLimit(1)
                Text("\(employee.role.rawValue) · \(hours.formatted(.number.precision(.fractionLength(1))))h")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignSystem.Colors.surface.opacity(0.5))
        )
        .draggable(employee.id.uuidString)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(employee.name), \(employee.role.rawValue)")
    }

    private func statusColor(for status: EmployeeAvailabilityStatus) -> Color {
        switch status {
        case .available:
            return DesignSystem.Colors.success
        case .partial:
            return DesignSystem.Colors.warning
        case .unavailable:
            return DesignSystem.Colors.error
        }
    }
}
