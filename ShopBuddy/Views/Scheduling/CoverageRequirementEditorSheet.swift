import SwiftUI

struct CoverageRequirementEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialRequirement: CoverageRequirement?
    let onSave: (_ dayOfWeek: Int, _ startMinutes: Int, _ endMinutes: Int, _ headcount: Int, _ role: EmployeeRole?, _ notes: String) -> Void

    @State private var dayOfWeek: Int
    @State private var startMinutes: Int
    @State private var endMinutes: Int
    @State private var headcount: Int
    @State private var roleRequirement: EmployeeRole?
    @State private var notes: String
    @State private var errorMessage: String?

    private let selectableMinutes = Array(stride(from: 0, through: 24 * 60, by: 15))

    init(
        title: String,
        initialRequirement: CoverageRequirement? = nil,
        onSave: @escaping (_ dayOfWeek: Int, _ startMinutes: Int, _ endMinutes: Int, _ headcount: Int, _ role: EmployeeRole?, _ notes: String) -> Void
    ) {
        self.title = title
        self.initialRequirement = initialRequirement
        self.onSave = onSave
        _dayOfWeek = State(initialValue: initialRequirement?.dayOfWeek ?? 2)
        _startMinutes = State(initialValue: initialRequirement?.startMinutes ?? 7 * 60)
        _endMinutes = State(initialValue: initialRequirement?.endMinutes ?? 15 * 60)
        _headcount = State(initialValue: max(1, initialRequirement?.headcount ?? 1))
        _roleRequirement = State(initialValue: initialRequirement?.roleRequirement)
        _notes = State(initialValue: initialRequirement?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.LiquidBackdrop()
                    .ignoresSafeArea()

                Form {
                    Section("Coverage Block") {
                        Picker("Day", selection: $dayOfWeek) {
                            ForEach(1...7, id: \.self) { day in
                                Text(ScheduleCalendarService.dayName(for: day)).tag(day)
                            }
                        }

                        Picker("Start", selection: $startMinutes) {
                            ForEach(selectableMinutes, id: \.self) { minute in
                                Text(ScheduleCalendarService.timeLabel(for: minute)).tag(minute)
                            }
                        }

                        Picker("End", selection: $endMinutes) {
                            ForEach(selectableMinutes, id: \.self) { minute in
                                Text(ScheduleCalendarService.timeLabel(for: minute)).tag(minute)
                            }
                        }

                        Stepper("Headcount: \(headcount)", value: $headcount, in: 1...20)
                    }

                    Section("Role Requirement") {
                        Picker("Role", selection: $roleRequirement) {
                            Text("Any Role").tag(nil as EmployeeRole?)
                            ForEach(EmployeeRole.allCases, id: \.self) { role in
                                Text(role.rawValue).tag(role as EmployeeRole?)
                            }
                        }
                    }

                    Section("Notes") {
                        TextField("Optional notes", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                    }

                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .liquidFormChrome()
                .tint(DesignSystem.Colors.accent)
                .safeAreaPadding(.horizontal, DesignSystem.Spacing.grid_1)
                .safeAreaPadding(.bottom, DesignSystem.Spacing.grid_1)
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func save() {
        guard endMinutes > startMinutes else {
            errorMessage = "End time must be after start time."
            return
        }

        onSave(dayOfWeek, startMinutes, endMinutes, headcount, roleRequirement, notes.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
