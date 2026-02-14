import SwiftUI

struct EditShiftPopover: View {
    @Environment(\.dismiss) private var dismiss

    let employees: [Employee]
    let shift: ScheduleDraftShift
    let visibleStartMinutes: Int
    let visibleEndMinutes: Int
    let onSave: (ScheduleDraftShift) -> Void
    let onDelete: () -> Void

    @State private var employeeId: UUID?
    @State private var dayOfWeek: Int
    @State private var startMinutes: Int
    @State private var endMinutes: Int
    @State private var notes: String
    @State private var validationMessage: String?

    private let minimumDurationMinutes = 30

    init(
        employees: [Employee],
        shift: ScheduleDraftShift,
        visibleStartMinutes: Int,
        visibleEndMinutes: Int,
        onSave: @escaping (ScheduleDraftShift) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.employees = employees
        self.shift = shift
        self.visibleStartMinutes = visibleStartMinutes
        self.visibleEndMinutes = visibleEndMinutes
        self.onSave = onSave
        self.onDelete = onDelete

        _employeeId = State(initialValue: shift.employeeId)
        _dayOfWeek = State(initialValue: shift.dayOfWeek)
        _startMinutes = State(initialValue: shift.startMinutes)
        _endMinutes = State(initialValue: shift.endMinutes)
        _notes = State(initialValue: shift.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.LiquidBackdrop()
                    .ignoresSafeArea()

                VStack {
                    Form {
                        Section("Assignment") {
                            Picker("Employee", selection: $employeeId) {
                                Text("Open Shift").tag(UUID?.none)
                                ForEach(employees.filter(\.isActive), id: \.id) { employee in
                                    Text(employee.name).tag(UUID?.some(employee.id))
                                }
                            }

                            Picker("Day", selection: $dayOfWeek) {
                                ForEach(ScheduleDayMapper.orderedDays, id: \.self) { day in
                                    Text(ScheduleDayMapper.shortName(for: day)).tag(day)
                                }
                            }
                        }

                        Section("Time") {
                            Stepper {
                                timeRow(label: "Start", minutes: startMinutes)
                            } onIncrement: {
                                startMinutes = TimeSnapper.snapAndClamp(
                                    startMinutes + 15,
                                    min: visibleStartMinutes,
                                    max: endMinutes - minimumDurationMinutes
                                )
                            } onDecrement: {
                                startMinutes = TimeSnapper.snapAndClamp(
                                    startMinutes - 15,
                                    min: visibleStartMinutes,
                                    max: endMinutes - minimumDurationMinutes
                                )
                            }

                            Stepper {
                                timeRow(label: "End", minutes: endMinutes)
                            } onIncrement: {
                                endMinutes = TimeSnapper.snapAndClamp(
                                    endMinutes + 15,
                                    min: startMinutes + minimumDurationMinutes,
                                    max: visibleEndMinutes
                                )
                            } onDecrement: {
                                endMinutes = TimeSnapper.snapAndClamp(
                                    endMinutes - 15,
                                    min: startMinutes + minimumDurationMinutes,
                                    max: visibleEndMinutes
                                )
                            }
                        }

                        if let validationMessage {
                            Section {
                                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(DesignSystem.Colors.warning)
                            }
                        }

                        Section("Notes") {
                            TextField("Optional", text: $notes, axis: .vertical)
                        }

                        Section {
                            Button("Delete Shift", role: .destructive) {
                                onDelete()
                                dismiss()
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .liquidFormChrome()
                    .tint(DesignSystem.Colors.accent)
                    .safeAreaPadding(.horizontal, DesignSystem.Spacing.grid_1)
                    .safeAreaPadding(.bottom, DesignSystem.Spacing.grid_1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Edit Shift")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard endMinutes > startMinutes else {
                            validationMessage = "End time must be after start time."
                            return
                        }
                        guard (endMinutes - startMinutes) >= minimumDurationMinutes else {
                            validationMessage = "Shift must be at least 30 minutes."
                            return
                        }
                        validationMessage = nil

                        var updated = shift
                        updated.employeeId = employeeId
                        updated.dayOfWeek = dayOfWeek
                        updated.startMinutes = startMinutes
                        updated.endMinutes = endMinutes
                        updated.notes = notes.isEmpty ? nil : notes
                        if let employeeId {
                            updated.colorSeed = employeeId.uuidString
                        }
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }

    private func timeRow(label: String, minutes: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(ScheduleCalendarService.timeLabel(for: minutes))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
