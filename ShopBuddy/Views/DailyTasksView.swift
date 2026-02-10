import SwiftUI
import SwiftData

struct DailyTasksView: View {

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyTask.sortOrder) private var allTasks: [DailyTask]
    @Query private var settings: [AppSettings]

    @State private var addingTaskForToday = false
    @State private var addingTaskForNextDay = false
    @State private var newTaskTitle = ""
    @FocusState private var isNewTaskFocused: Bool

    // MARK: - Computed

    private var appSettings: AppSettings? { settings.first }

    private var targetDate: Date {
        appSettings?.nextOperatingDay() ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    private var tasksForTarget: [DailyTask] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: targetDate)
        return allTasks.filter { cal.startOfDay(for: $0.targetDate) == start }
    }

    private var todaysTasks: [DailyTask] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return allTasks.filter { cal.startOfDay(for: $0.targetDate) == start }
    }

    private var canEdit: Bool {
        coordinator.isAuthenticated
    }

    private var canComplete: Bool {
        if let s = appSettings, s.requireClockInForChecklists {
            return coordinator.isManager || coordinator.currentEmployee?.isClockedIn == true
        }
        return coordinator.isAuthenticated
    }

    private var targetDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: targetDate)
    }

    private var todayFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.grid_3) {
                // Today's tasks — always on top
                taskSection(
                    title: "Today",
                    subtitle: todayFormatted,
                    tasks: todaysTasks,
                    isAdding: $addingTaskForToday,
                    date: Calendar.current.startOfDay(for: Date())
                )

                // Next operating day tasks
                taskSection(
                    title: "Next Day",
                    subtitle: targetDateFormatted,
                    tasks: tasksForTarget,
                    isAdding: $addingTaskForNextDay,
                    date: targetDate
                )
            }
            .padding(DesignSystem.Spacing.grid_3)
        }
        .liquidBackground()
        .navigationTitle("Daily Tasks")
    }

    // MARK: - Task Section

    @ViewBuilder
    private func taskSection(title: String, subtitle: String, tasks: [DailyTask], isAdding: Binding<Bool>, date: Date) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Typography.title3)
                        .foregroundColor(DesignSystem.Colors.primary)
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
                Spacer()

                if !tasks.isEmpty {
                    let done = tasks.filter(\.isCompleted).count
                    Text("\(done)/\(tasks.count)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(done == tasks.count ? DesignSystem.Colors.success : DesignSystem.Colors.secondary)
                }

                if canEdit {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isAdding.wrappedValue = true
                            newTaskTitle = ""
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isNewTaskFocused = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Add Task")
                }
            }

            if tasks.isEmpty && !isAdding.wrappedValue {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.largeTitle)
                            .foregroundColor(DesignSystem.Colors.tertiary)
                        Text("No tasks yet")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondary)
                    }
                    .padding(.vertical, DesignSystem.Spacing.grid_3)
                    Spacer()
                }
            } else {
                VStack(spacing: DesignSystem.Spacing.grid_1) {
                    ForEach(tasks) { task in
                        dailyTaskRow(task)
                    }

                    // Inline add row
                    if isAdding.wrappedValue {
                        HStack(spacing: DesignSystem.Spacing.grid_2) {
                            Image(systemName: "circle")
                                .font(.title3)
                                .foregroundColor(DesignSystem.Colors.tertiary)

                            TextField("New task…", text: $newTaskTitle)
                                .font(DesignSystem.Typography.body)
                                .textFieldStyle(.plain)
                                .focused($isNewTaskFocused)
                                .onSubmit {
                                    commitTask(for: date, isAdding: isAdding)
                                }

                            Spacer()

                            Button {
                                withAnimation { isAdding.wrappedValue = false }
                                newTaskTitle = ""
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.caption)
                                    .foregroundColor(DesignSystem.Colors.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, DesignSystem.Spacing.grid_1)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    // MARK: - Task Row

    private func dailyTaskRow(_ task: DailyTask) -> some View {
        HStack(spacing: DesignSystem.Spacing.grid_2) {
            Button {
                if task.isCompleted {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        task.isCompleted = false
                        task.completedBy = nil
                        task.completedAt = nil
                    }
                } else if canComplete {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        task.markComplete(by: coordinator.currentUserDisplayName)
                        DesignSystem.HapticFeedback.trigger(.success)
                    }
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(task.isCompleted ? DesignSystem.Colors.success : DesignSystem.Colors.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(!task.isCompleted && !canComplete)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(task.isCompleted ? DesignSystem.Colors.secondary : DesignSystem.Colors.primary)
                    .strikethrough(task.isCompleted)

                if let by = task.completedBy, let at = task.completedAt {
                    let formatter = DateFormatter()
                    let _ = formatter.dateFormat = "h:mm a"
                    Text("\(by) • \(formatter.string(from: at))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.tertiary)
                }
            }

            Spacer()

            if canEdit && !task.isCompleted {
                Button(role: .destructive) {
                    withAnimation { modelContext.delete(task) }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.error.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.grid_1)
    }

    // MARK: - Actions

    private func commitTask(for date: Date, isAdding: Binding<Bool>) {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            withAnimation { isAdding.wrappedValue = false }
            return
        }
        let cal = Calendar.current
        let targetDay = cal.startOfDay(for: date)
        let existingTasks = allTasks.filter { cal.startOfDay(for: $0.targetDate) == targetDay }
        let nextOrder = (existingTasks.map(\.sortOrder).max() ?? -1) + 1
        let task = DailyTask(title: trimmed, targetDate: date, sortOrder: nextOrder)
        modelContext.insert(task)
        newTaskTitle = ""
        DesignSystem.HapticFeedback.trigger(.success)
        // Keep adding mode open for quick entry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNewTaskFocused = true
        }
    }
}
