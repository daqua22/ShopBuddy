import SwiftUI

struct WeekScheduleView: View {
    @Binding var weekStartDate: Date
    @Binding var shifts: [WeekScheduledShift]
    let employees: [Employee]
    let onGenerateOptions: () -> Void
    let onPublish: () -> Void

    @StateObject private var viewModel: WeekScheduleViewModel
    @State private var editingShift: WeekScheduledShift?

    init(
        weekStartDate: Binding<Date>,
        shifts: Binding<[WeekScheduledShift]>,
        employees: [Employee],
        onGenerateOptions: @escaping () -> Void = {},
        onPublish: @escaping () -> Void = {}
    ) {
        self._weekStartDate = weekStartDate
        self._shifts = shifts
        self.employees = employees
        self.onGenerateOptions = onGenerateOptions
        self.onPublish = onPublish

        let initialWidth: CGFloat
        #if os(iOS)
        initialWidth = UIDevice.current.userInterfaceIdiom == .phone ? 138 : 180
        #else
        initialWidth = 190
        #endif

        _viewModel = StateObject(
            wrappedValue: WeekScheduleViewModel(
                weekStartDate: weekStartDate.wrappedValue,
                shifts: shifts.wrappedValue,
                visibleStartMinutes: 6 * 60 + 30,
                visibleEndMinutes: 18 * 60 + 30,
                pixelsPerMinute: 1.4,
                dayColumnWidth: initialWidth
            )
        )
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.grid_1) {
            controlBar
            WeekScheduleGridView(viewModel: viewModel) { shift in
                editingShift = shift
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: viewModel.shifts) { _, newValue in
            if shifts != newValue {
                shifts = newValue
            }
        }
        .onChange(of: shifts) { _, newValue in
            if viewModel.shifts != newValue {
                viewModel.shifts = newValue
            }
        }
        .onChange(of: viewModel.weekStartDate) { _, newValue in
            if weekStartDate != newValue {
                weekStartDate = newValue
            }
        }
        .onChange(of: weekStartDate) { _, newValue in
            if viewModel.weekStartDate != newValue {
                viewModel.weekStartDate = newValue
            }
        }
        .sheet(item: $editingShift) { shift in
            EditShiftSheet(employees: employees, shift: shift) { updated in
                viewModel.updateShift(updated)
            } onDelete: {
                viewModel.deleteShift(shift.id)
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 560)
            #endif
        }
    }

    private var controlBar: some View {
        HStack(spacing: DesignSystem.Spacing.grid_1) {
            Button {
                viewModel.previousWeek()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)

            Text(weekLabel)
                .font(DesignSystem.Typography.headline)
                .frame(minWidth: 220, alignment: .leading)

            Button {
                viewModel.nextWeek()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { viewModel.pixelsPerMinute },
                        set: { viewModel.pixelsPerMinute = max(1.1, min($0, 1.9)) }
                    ),
                    in: 1.1...1.9
                )
                .frame(width: 120)
            }

            Button {
                addShift()
            } label: {
                Label("Add Shift", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            Button {
                onGenerateOptions()
            } label: {
                Label("Generate Options", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)

            Button {
                onPublish()
            } label: {
                Label("Publish", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, DesignSystem.Spacing.grid_1)
        .padding(.vertical, 6)
    }

    private var weekLabel: String {
        let calendar = ScheduleCalendarService.calendar(in: ShopContext.activeTimeZone)
        let end = calendar.date(byAdding: .day, value: 6, to: viewModel.weekStartDate) ?? viewModel.weekStartDate
        let startLabel = ScheduleCalendarService.abbreviatedDateLabel(for: viewModel.weekStartDate, in: ShopContext.activeTimeZone)
        let endLabel = ScheduleCalendarService.abbreviatedDateLabel(for: end, in: ShopContext.activeTimeZone)
        return "\(startLabel) - \(endLabel)"
    }

    private func addShift() {
        let newShift = WeekScheduledShift(
            employeeName: employees.first?.name ?? "Unassigned",
            employeeId: employees.first?.id,
            dayOfWeek: 2,
            startMinutes: 8 * 60,
            endMinutes: 16 * 60,
            color: palette[(viewModel.shifts.count) % palette.count]
        )
        viewModel.addShift(newShift)
        editingShift = newShift
    }

    private var palette: [Color] {
        [.blue, .teal, .green, .orange, .pink, .purple, .indigo]
    }
}

#Preview("Week Schedule Grid") {
    @Previewable @State var weekStart = ScheduleCalendarService.normalizedWeekStart(Date(), in: ShopContext.activeTimeZone)
    @Previewable @State var demoShifts: [WeekScheduledShift] = [
        WeekScheduledShift(employeeName: "Avery", dayOfWeek: 2, startMinutes: 7 * 60, endMinutes: 11 * 60, color: .blue),
        WeekScheduledShift(employeeName: "Jordan", dayOfWeek: 2, startMinutes: 9 * 60, endMinutes: 14 * 60, color: .green),
        WeekScheduledShift(employeeName: "Mia", dayOfWeek: 3, startMinutes: 6 * 60 + 30, endMinutes: 12 * 60, color: .orange),
        WeekScheduledShift(employeeName: "Leo", dayOfWeek: 4, startMinutes: 11 * 60, endMinutes: 18 * 60, color: .purple),
        WeekScheduledShift(employeeName: "Noah", dayOfWeek: 6, startMinutes: 8 * 60 + 30, endMinutes: 15 * 60, color: .teal)
    ]

    let employees = [
        Employee(name: "Avery", pin: "1111", role: .manager),
        Employee(name: "Jordan", pin: "2222", role: .shiftLead),
        Employee(name: "Mia", pin: "3333", role: .employee),
        Employee(name: "Leo", pin: "4444", role: .employee),
        Employee(name: "Noah", pin: "5555", role: .employee)
    ]

    return NavigationStack {
        WeekScheduleView(
            weekStartDate: $weekStart,
            shifts: $demoShifts,
            employees: employees
        )
        .padding(DesignSystem.Spacing.grid_1)
    }
    .frame(minWidth: 1000, minHeight: 700)
}
