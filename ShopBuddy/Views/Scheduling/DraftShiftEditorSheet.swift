import SwiftUI

struct DraftShiftEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let weekStartDate: Date
    let shopId: String
    let timeZone: TimeZone
    let employees: [Employee]
    let availabilityContext: EmployeeAvailabilityContext
    let initialShift: DraftShift
    let onSave: (DraftShift) -> Void
    let onDelete: () -> Void

    @State private var selectedEmployeeID: UUID?
    @State private var dayOfWeek: Int
    @State private var startMinutes: Int
    @State private var endMinutes: Int
    @State private var notes: String
    @State private var errorMessage: String?

    private let selectableMinutes = Array(stride(from: 0, through: 24 * 60, by: 15))

    init(
        weekStartDate: Date,
        shopId: String,
        timeZone: TimeZone,
        employees: [Employee],
        availabilityContext: EmployeeAvailabilityContext,
        initialShift: DraftShift,
        onSave: @escaping (DraftShift) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.weekStartDate = weekStartDate
        self.shopId = shopId
        self.timeZone = timeZone
        self.employees = employees
        self.availabilityContext = availabilityContext
        self.initialShift = initialShift
        self.onSave = onSave
        self.onDelete = onDelete

        _selectedEmployeeID = State(initialValue: initialShift.employeeID)
        _dayOfWeek = State(initialValue: initialShift.dayOfWeek)
        _startMinutes = State(initialValue: initialShift.startMinutes)
        _endMinutes = State(initialValue: initialShift.endMinutes)
        _notes = State(initialValue: initialShift.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.LiquidBackdrop()
                    .ignoresSafeArea()

                Form {
                    Section("Assignment") {
                        Picker("Employee", selection: $selectedEmployeeID) {
                            Text("Unassigned").tag(nil as UUID?)
                            ForEach(employees) { employee in
                                Text(employeeLabel(for: employee))
                                    .tag(employee.id as UUID?)
                            }
                        }
                    }

                    Section("Shift Timing") {
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

                    Section {
                        Button("Delete Shift", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
                .liquidFormChrome()
                .tint(DesignSystem.Colors.accent)
                .safeAreaPadding(.horizontal, DesignSystem.Spacing.grid_1)
                .safeAreaPadding(.bottom, DesignSystem.Spacing.grid_1)
            }
            .navigationTitle("Edit Shift")
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
                        saveShift()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func saveShift() {
        guard endMinutes > startMinutes else {
            errorMessage = "End time must be after start time."
            return
        }

        var updated = initialShift
        updated.employeeID = selectedEmployeeID
        updated.dayOfWeek = dayOfWeek
        updated.startMinutes = startMinutes
        updated.endMinutes = endMinutes
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        onSave(updated)
        dismiss()
    }

    private func employeeLabel(for employee: Employee) -> String {
        let date = ScheduleCalendarService.date(for: weekStartDate, dayOfWeek: dayOfWeek, minutesFromMidnight: 0, in: timeZone)
        let available = EmployeeAvailabilityService.isAvailable(
            employeeID: employee.id,
            shopId: shopId,
            dayDate: date,
            dayOfWeek: dayOfWeek,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            context: availabilityContext,
            timeZone: timeZone
        )
        return available ? employee.name : "\(employee.name) • unavailable"
    }
}
