import SwiftUI
import SwiftData

struct CoverageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let shopId: String
    let weekStartDate: Date
    let timeZone: TimeZone

    @Query(sort: [SortDescriptor(\CoverageRequirement.dayOfWeek), SortDescriptor(\CoverageRequirement.startMinutes)])
    private var allRequirements: [CoverageRequirement]

    @State private var editingRequirement: CoverageRequirement?
    @State private var showingEditor = false

    private var scoped: [CoverageRequirement] {
        let normalizedWeek = ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: timeZone)
        return allRequirements.filter {
            $0.shopId == shopId &&
            ScheduleCalendarService.normalizedWeekStart($0.weekStartDate, in: timeZone) == normalizedWeek
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.LiquidBackdrop()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
                    HStack {
                        Button("Preset: Open–Close") {
                            applyOpenClosePreset()
                        }
                        .buttonStyle(.bordered)

                        Button("Preset: Morning Rush") {
                            applyMorningRushPreset()
                        }
                        .buttonStyle(.bordered)

                        Button("Preset: Afternoon") {
                            applyAfternoonPreset()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            editingRequirement = nil
                            showingEditor = true
                        } label: {
                            Label("Add Block", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if scoped.isEmpty {
                        EmptyStateView(
                            icon: "calendar.badge.plus",
                            title: "No Coverage Blocks",
                            message: "Add coverage windows for this week.",
                            actionTitle: "Add Coverage Block"
                        ) {
                            editingRequirement = nil
                            showingEditor = true
                        }
                    } else {
                        List {
                            ForEach(scoped) { requirement in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ScheduleDayMapper.shortName(for: requirement.dayIndex))
                                            .font(DesignSystem.Typography.body)
                                        Text("\(ScheduleCalendarService.timeLabel(for: requirement.startMinutes)) – \(ScheduleCalendarService.timeLabel(for: requirement.endMinutes))")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("x\(requirement.headcount)")
                                        .font(DesignSystem.Typography.headline)
                                        .monospacedDigit()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingRequirement = requirement
                                    showingEditor = true
                                }
                                .contextMenu {
                                    Button("Edit") {
                                        editingRequirement = requirement
                                        showingEditor = true
                                    }
                                    Button("Delete", role: .destructive) {
                                        delete(requirement)
                                    }
                                }
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    delete(scoped[index])
                                }
                            }
                        }
                        .listStyle(.inset)
                        .liquidListChrome()
                    }
                }
                .padding(DesignSystem.Spacing.grid_2)
                .safeAreaPadding(.horizontal, DesignSystem.Spacing.grid_1)
                .safeAreaPadding(.bottom, DesignSystem.Spacing.grid_1)
            }
            .navigationTitle("Coverage")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            CoverageRequirementEditorSheet(
                title: editingRequirement == nil ? "New Coverage Block" : "Edit Coverage Block",
                initialRequirement: editingRequirement
            ) { dayOfWeek, startMinutes, endMinutes, headcount, role, notes in
                save(
                    dayOfWeek: dayOfWeek,
                    startMinutes: startMinutes,
                    endMinutes: endMinutes,
                    headcount: headcount,
                    role: role,
                    notes: notes
                )
            }
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 560)
            #endif
        }
    }

    private func save(
        dayOfWeek: Int,
        startMinutes: Int,
        endMinutes: Int,
        headcount: Int,
        role: EmployeeRole?,
        notes: String
    ) {
        let normalizedWeek = ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: timeZone)

        if let existing = editingRequirement {
            existing.dayOfWeek = dayOfWeek
            existing.startMinutes = startMinutes
            existing.endMinutes = endMinutes
            existing.headcount = max(1, headcount)
            existing.roleRequirement = role
            existing.notes = notes.isEmpty ? nil : notes
        } else {
            modelContext.insert(
                CoverageRequirement(
                    shopId: shopId,
                    weekStartDate: normalizedWeek,
                    dayOfWeek: dayOfWeek,
                    startMinutes: startMinutes,
                    endMinutes: endMinutes,
                    headcount: headcount,
                    roleRequirement: role,
                    notes: notes.isEmpty ? nil : notes
                )
            )
        }

        do {
            try modelContext.save()
            editingRequirement = nil
        } catch {
            // Keep MVP resilient; non-blocking for current editing flow.
        }
    }

    private func delete(_ requirement: CoverageRequirement) {
        modelContext.delete(requirement)
        try? modelContext.save()
    }

    private func applyOpenClosePreset() {
        for day in [0, 1, 2, 3, 4] {
            modelContext.insert(
                CoverageRequirement(
                    shopId: shopId,
                    weekStartDate: ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: timeZone),
                    dayOfWeek: ScheduleDayMapper.weekday(fromDayIndex: day),
                    startMinutes: 7 * 60,
                    endMinutes: 15 * 60,
                    headcount: 2
                )
            )
        }
        try? modelContext.save()
    }

    private func applyMorningRushPreset() {
        for day in [0, 1, 2, 3, 4, 5, 6] {
            modelContext.insert(
                CoverageRequirement(
                    shopId: shopId,
                    weekStartDate: ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: timeZone),
                    dayOfWeek: ScheduleDayMapper.weekday(fromDayIndex: day),
                    startMinutes: 6 * 60 + 30,
                    endMinutes: 11 * 60,
                    headcount: 2
                )
            )
        }
        try? modelContext.save()
    }

    private func applyAfternoonPreset() {
        for day in [0, 1, 2, 3, 4, 5, 6] {
            modelContext.insert(
                CoverageRequirement(
                    shopId: shopId,
                    weekStartDate: ScheduleCalendarService.normalizedWeekStart(weekStartDate, in: timeZone),
                    dayOfWeek: ScheduleDayMapper.weekday(fromDayIndex: day),
                    startMinutes: 12 * 60,
                    endMinutes: 18 * 60,
                    headcount: 1
                )
            )
        }
        try? modelContext.save()
    }
}
