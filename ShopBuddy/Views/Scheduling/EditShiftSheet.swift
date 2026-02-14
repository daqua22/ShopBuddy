import SwiftUI

struct EditShiftSheet: View {
    @Environment(\.dismiss) private var dismiss

    let employees: [Employee]
    let shift: WeekScheduledShift
    let onSave: (WeekScheduledShift) -> Void
    let onDelete: () -> Void

    @State private var selectedEmployeeID: UUID?
    @State private var dayOfWeek: Int
    @State private var startMinutes: Int
    @State private var endMinutes: Int
    @State private var errorMessage: String?

    private let dayOrder = [2, 3, 4, 5, 6, 7, 1]
    private let minuteOptions = Array(stride(from: 0, through: 24 * 60, by: 15))

    init(
        employees: [Employee],
        shift: WeekScheduledShift,
        onSave: @escaping (WeekScheduledShift) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.employees = employees
        self.shift = shift
        self.onSave = onSave
        self.onDelete = onDelete

        _selectedEmployeeID = State(initialValue: shift.employeeId)
        _dayOfWeek = State(initialValue: shift.dayOfWeek)
        _startMinutes = State(initialValue: shift.startMinutes)
        _endMinutes = State(initialValue: shift.endMinutes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.LiquidBackdrop()
                    .ignoresSafeArea()

                Form {
                    Section("Employee") {
                        Picker("Employee", selection: $selectedEmployeeID) {
                            ForEach(employees) { employee in
                                Text(employee.name).tag(employee.id as UUID?)
                            }
                        }
                    }

                    Section("Shift") {
                        Picker("Day", selection: $dayOfWeek) {
                            ForEach(dayOrder, id: \.self) { day in
                                Text(dayLabel(day)).tag(day)
                            }
                        }

                        Picker("Start", selection: $startMinutes) {
                            ForEach(minuteOptions, id: \.self) { minute in
                                Text(ScheduleCalendarService.timeLabel(for: minute)).tag(minute)
                            }
                        }

                        Picker("End", selection: $endMinutes) {
                            ForEach(minuteOptions, id: \.self) { minute in
                                Text(ScheduleCalendarService.timeLabel(for: minute)).tag(minute)
                            }
                        }
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

        let selectedEmployee = employees.first(where: { $0.id == selectedEmployeeID })
        var updated = shift
        updated.employeeId = selectedEmployeeID
        updated.employeeName = selectedEmployee?.name ?? shift.employeeName
        updated.dayOfWeek = dayOfWeek
        updated.startMinutes = startMinutes
        updated.endMinutes = endMinutes
        onSave(updated)
        dismiss()
    }

    private func dayLabel(_ day: Int) -> String {
        switch day {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return "Day"
        }
    }
}
