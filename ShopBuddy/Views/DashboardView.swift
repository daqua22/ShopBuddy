import SwiftUI
import SwiftData

struct DashboardView: View {

    @Environment(AppCoordinator.self) private var coordinator
    @Query(filter: #Predicate<Employee> { $0.isActive }) private var employees: [Employee]
    @Query private var inventoryItems: [InventoryItem]
    @Query(sort: \ChecklistTemplate.title) private var checklists: [ChecklistTemplate]
    @Query private var shifts: [Shift]
    @Query(sort: \DailyTask.sortOrder) private var allDailyTasks: [DailyTask]

    // MARK: - Computed Data

    private var todaysTasks: [DailyTask] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return allDailyTasks.filter { cal.startOfDay(for: $0.targetDate) == start }
    }

    private var clockedInEmployees: [Employee] {
        employees.filter { $0.isClockedIn }
    }

    private var lowStockItems: [InventoryItem] {
        inventoryItems.filter { $0.isBelowPar }
    }

    private var overallChecklistProgress: Double {
        guard !checklists.isEmpty else { return 0 }
        let total = checklists.reduce(0.0) { $0 + $1.completionPercentage }
        return total / Double(checklists.count)
    }

    private var weeklyHours: Double {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return 0 }
        return shifts
            .filter { shift in
                let end = shift.clockOutTime ?? now
                return end >= weekStart
            }
            .reduce(0.0) { total, shift in
                let calendar = Calendar.current
                let now = Date()
                let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
                let start = max(shift.clockInTime, weekStart)
                let end = shift.clockOutTime ?? now
                guard end > start else { return total }
                return total + end.timeIntervalSince(start) / 3600.0
            }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.grid_3) {
                welcomeHeader

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.grid_3),
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.grid_3)
                ], spacing: DesignSystem.Spacing.grid_3) {
                    todaysTasksCard
                    checklistProgressCard
                    clockedInCard
                    lowStockCard
                    hoursWorkedCard
                }
            }
            .padding(DesignSystem.Spacing.grid_3)
        }
        .liquidBackground()
        .navigationTitle("Dashboard")
    }

    // MARK: - Welcome

    private var welcomeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(DesignSystem.Typography.title2)
                    .foregroundColor(DesignSystem.Colors.primary)
                Text(dateSummary)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.secondary)
            }
            Spacer()
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = coordinator.currentUserDisplayName
        switch hour {
        case 0..<12: return "Good morning, \(name)"
        case 12..<17: return "Good afternoon, \(name)"
        default: return "Good evening, \(name)"
        }
    }

    private var dateSummary: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }
    // MARK: - Today's Tasks Card

    private var todaysTasksCard: some View {
        let done = todaysTasks.filter(\.isCompleted).count
        let total = todaysTasks.count
        let progress = total > 0 ? Double(done) / Double(total) : 0

        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            HStack {
                Image(systemName: "note.text")
                    .font(.title2)
                    .foregroundColor(done == total && total > 0 ? DesignSystem.Colors.success : DesignSystem.Colors.accent)
                Spacer()
                Text("\(done)/\(total)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            Text("Today's Tasks")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.primary)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.surface)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(done == total && total > 0 ? DesignSystem.Colors.success : DesignSystem.Colors.accent)
                        .frame(width: geo.size.width * progress, height: 8)
                }
            }
            .frame(height: 8)

            if todaysTasks.isEmpty {
                Text("No tasks for today")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(todaysTasks.prefix(4), id: \.id) { task in
                        HStack(spacing: 6) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundColor(task.isCompleted ? DesignSystem.Colors.success : DesignSystem.Colors.tertiary)
                            Text(task.title)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(task.isCompleted ? DesignSystem.Colors.tertiary : DesignSystem.Colors.secondary)
                                .lineLimit(1)
                                .strikethrough(task.isCompleted)
                        }
                    }
                    if todaysTasks.count > 4 {
                        Text("+\(todaysTasks.count - 4) more")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.tertiary)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    // MARK: - Clocked In Card

    private var clockedInCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            HStack {
                Image(systemName: "person.fill.checkmark")
                    .font(.title2)
                    .foregroundColor(DesignSystem.Colors.success)
                Spacer()
                Text("\(clockedInEmployees.count)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            Text("Clocked In")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.primary)

            if clockedInEmployees.isEmpty {
                Text("No one on shift")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(clockedInEmployees.prefix(4), id: \.id) { emp in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(DesignSystem.Colors.success)
                                .frame(width: 6, height: 6)
                            Text(emp.name)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondary)
                                .lineLimit(1)
                        }
                    }
                    if clockedInEmployees.count > 4 {
                        Text("+\(clockedInEmployees.count - 4) more")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.tertiary)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    // MARK: - Checklist Progress Card

    private var checklistProgressCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            HStack {
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundColor(DesignSystem.Colors.accent)
                Spacer()
                Text("\(Int(overallChecklistProgress))%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            Text("Checklist Progress")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.primary)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.surface)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: geo.size.width * (overallChecklistProgress / 100), height: 8)
                }
            }
            .frame(height: 8)

            if checklists.isEmpty {
                Text("No checklists yet")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(checklists.prefix(3), id: \.id) { cl in
                        HStack {
                            Text(cl.title)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(cl.completionPercentage))%")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(cl.completionPercentage >= 100 ? DesignSystem.Colors.success : DesignSystem.Colors.tertiary)
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    // MARK: - Low Stock Card

    private var lowStockCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(lowStockItems.isEmpty ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                Spacer()
                Text("\(lowStockItems.count)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            Text("Low Stock Alerts")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.primary)

            if lowStockItems.isEmpty {
                Text("All items are stocked")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.success)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lowStockItems.prefix(4), id: \.id) { item in
                        HStack {
                            Text(item.name)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(item.stockPercentage * 100))%")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.warning)
                        }
                    }
                    if lowStockItems.count > 4 {
                        Text("+\(lowStockItems.count - 4) more items")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.tertiary)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    // MARK: - Hours Worked Card

    private var hoursWorkedCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.title2)
                    .foregroundColor(DesignSystem.Colors.accent)
                Spacer()
                Text(String(format: "%.1f", weeklyHours))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            Text("Hours This Week")
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.primary)

            Text("Total across all employees")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondary)

            // Top contributors
            let topEmployees = employeesWithHoursThisWeek.prefix(3)
            if !topEmployees.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(topEmployees), id: \.0.id) { emp, hours in
                        HStack {
                            Text(emp.name)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1fh", hours))
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.tertiary)
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private var employeesWithHoursThisWeek: [(Employee, Double)] {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return [] }

        return employees.compactMap { emp in
            let hours = emp.shifts
                .filter { ($0.clockOutTime ?? now) >= weekStart }
                .reduce(0.0) { total, shift in
                    let start = max(shift.clockInTime, weekStart)
                    let end = shift.clockOutTime ?? now
                    guard end > start else { return total }
                    return total + end.timeIntervalSince(start) / 3600.0
                }
            return hours > 0 ? (emp, hours) : nil
        }
        .sorted { $0.1 > $1.1 }
    }
}
