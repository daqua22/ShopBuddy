//
//  ChecklistsView.swift
//  PrepIt
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct ChecklistsView: View {
    
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \ChecklistTemplate.title) private var checklists: [ChecklistTemplate]
    @Query(filter: #Predicate<Employee> { $0.isActive })
    private var activeEmployees: [Employee]
    
    @State private var showingAddChecklist = false
    @State private var editingChecklist: ChecklistTemplate?
    @State private var selectedTask: ChecklistTask?
    @State private var showingEmployeeSelector = false
    
    private var clockedInEmployees: [Employee] {
        activeEmployees.filter { $0.isClockedIn }
    }

    @Query private var settings: [AppSettings]
    
    private var canEdit: Bool {
        coordinator.isManager
    }
    
    private var canMarkComplete: Bool {
        // If setting requires clock-in, only managers or clocked-in employees can complete
        if let setting = settings.first, setting.requireClockInForChecklists {
            return coordinator.isManager || coordinator.currentEmployee?.isClockedIn == true
        }
        // Otherwise, any authenticated user can complete
        return coordinator.isAuthenticated
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.grid_3) {
                if checklists.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "No Checklists",
                        message: "Create your first checklist to track daily tasks",
                        actionTitle: canEdit ? "Create Checklist" : nil,
                        action: canEdit ? { showingAddChecklist = true } : nil
                    )
                } else {
                    checklistsList
                }
            }
            .padding(DesignSystem.Spacing.grid_2)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationTitle("Checklists")
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddChecklist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddChecklist) {
            NavigationStack {
                AddEditChecklistView()
            }
            .frame(minWidth: 480, idealWidth: 520, minHeight: 480, idealHeight: 560)
        }
        .sheet(item: $editingChecklist) { checklist in
            NavigationStack {
                AddEditChecklistView(checklist: checklist)
            }
            .frame(minWidth: 480, idealWidth: 520, minHeight: 480, idealHeight: 560)
        }
        .sheet(isPresented: $showingEmployeeSelector) {
            EmployeeSelectorView(task: selectedTask)
                .frame(minWidth: 420, idealWidth: 460, minHeight: 400, idealHeight: 480)
        }
    }
    
    private var checklistsList: some View {
        VStack(spacing: DesignSystem.Spacing.grid_3) {
            ForEach(checklists) { checklist in
                ChecklistCard(
                    checklist: checklist,
                    canEdit: canEdit,
                    canMarkComplete: canMarkComplete,
                    dragEnabled: settings.first?.enableDragAndDrop ?? true,
                    onEdit: {
                        editingChecklist = checklist
                    },
                    onTaskTap: { task in
                        if task.isCompleted {
                            // Undo: un-complete the task
                            task.isCompleted = false
                            task.completedBy = nil
                            task.completedAt = nil
                        } else if let setting = settings.first, !setting.requireClockInForChecklists {
                            // Clock-in NOT required — complete directly with logged-in user
                            task.markComplete(by: coordinator.currentUserDisplayName)
                            DesignSystem.HapticFeedback.trigger(.success)
                        } else {
                            // Clock-in required — show employee selector
                            selectedTask = task
                            showingEmployeeSelector = true
                        }
                    },
                    onReset: {
                        resetChecklist(checklist)
                    }
                )
            }
        }
    }
    
    private func resetChecklist(_ checklist: ChecklistTemplate) {
        checklist.resetAllTasks()
        DesignSystem.HapticFeedback.trigger(.success)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to reset checklist: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
}

// MARK: - Checklist Card
struct ChecklistCard: View {
    
    @Environment(\.modelContext) private var modelContext
    @Bindable var checklist: ChecklistTemplate
    let canEdit: Bool
    let canMarkComplete: Bool
    let dragEnabled: Bool
    let onEdit: () -> Void
    let onTaskTap: (ChecklistTask) -> Void
    let onReset: () -> Void
    @State private var draggedTaskID: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.grid_2) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(checklist.title)
                        .font(DesignSystem.Typography.title3)
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    Text("\(Int(checklist.completionPercentage))% Complete")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
                
                Spacer()
                
                if canEdit {
                    HStack(spacing: DesignSystem.Spacing.grid_2) {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.title3)
                                .foregroundColor(DesignSystem.Colors.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Edit Checklist")

                        Button {
                            onReset()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.title3)
                                .foregroundColor(DesignSystem.Colors.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reset All Tasks")
                    }
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.surface)
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: geometry.size.width * (checklist.completionPercentage / 100), height: 8)
                }
            }
            .frame(height: 8)
            
            // Tasks
            VStack(spacing: DesignSystem.Spacing.grid_1) {
                ForEach(checklist.tasks.sorted(by: { $0.sortOrder < $1.sortOrder })) { task in
                    ChecklistTaskRow(
                        task: task,
                        canMarkComplete: canMarkComplete,
                        showDragHandle: dragEnabled && canEdit,
                        draggedTaskID: $draggedTaskID,
                        onTap: {
                            if task.isCompleted || canMarkComplete {
                                onTaskTap(task)
                            }
                        }
                    )
                    .onDrop(of: [.text], delegate: ChecklistTaskDropDelegate(
                        targetTask: task,
                        checklist: checklist,
                        draggedTaskID: $draggedTaskID,
                        modelContext: modelContext,
                        isEnabled: dragEnabled && canEdit
                    ))
                    .opacity(draggedTaskID == task.id ? 0.4 : 1.0)
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }

    private func reorderTask(draggedID: UUID, targetTask: ChecklistTask) {
        let sortedTasks = checklist.tasks.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard let draggedTask = sortedTasks.first(where: { $0.id == draggedID }),
              draggedTask.id != targetTask.id else { return }

        var reordered = sortedTasks.filter { $0.id != draggedID }
        if let targetIndex = reordered.firstIndex(where: { $0.id == targetTask.id }) {
            reordered.insert(draggedTask, at: targetIndex)
        }

        for (index, task) in reordered.enumerated() {
            task.sortOrder = index
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to reorder tasks: \(error)")
        }
    }
}

// MARK: - Checklist Task Drop Delegate
struct ChecklistTaskDropDelegate: DropDelegate {
    let targetTask: ChecklistTask
    let checklist: ChecklistTemplate
    @Binding var draggedTaskID: UUID?
    let modelContext: ModelContext
    let isEnabled: Bool

    func performDrop(info: DropInfo) -> Bool {
        draggedTaskID = nil
        return isEnabled
    }

    func dropEntered(info: DropInfo) {
        guard isEnabled,
              let draggedID = draggedTaskID,
              draggedID != targetTask.id else { return }

        let sortedTasks = checklist.tasks.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard let fromIndex = sortedTasks.firstIndex(where: { $0.id == draggedID }),
              let toIndex = sortedTasks.firstIndex(where: { $0.id == targetTask.id }) else { return }

        guard fromIndex != toIndex else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            var reordered = sortedTasks
            let moved = reordered.remove(at: fromIndex)
            reordered.insert(moved, at: toIndex)

            for (index, task) in reordered.enumerated() {
                task.sortOrder = index
            }
        }
    }

    func dropExited(info: DropInfo) {
        // No-op
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isEnabled ? .move : .cancel)
    }
}

// MARK: - Checklist Task Row
struct ChecklistTaskRow: View {
    
    @Bindable var task: ChecklistTask
    let canMarkComplete: Bool
    var showDragHandle: Bool = false
    @Binding var draggedTaskID: UUID?
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.grid_2) {
            if showDragHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.tertiary)
                    .frame(width: 20, height: 30)
                    .contentShape(Rectangle())
                    .onDrag {
                        draggedTaskID = task.id
                        return NSItemProvider(object: task.id.uuidString as NSString)
                    }
                    .help("Drag to reorder")
            }

            // Checkbox + text (tappable)
            HStack(spacing: DesignSystem.Spacing.grid_2) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(task.isCompleted ? DesignSystem.Colors.success : DesignSystem.Colors.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(task.isCompleted ? DesignSystem.Colors.secondary : DesignSystem.Colors.primary)
                        .strikethrough(task.isCompleted)
                    
                    if let completedBy = task.completedBy, let completedAt = task.completedAt {
                        Text("Completed by \(completedBy) at \(completedAt.timeString())")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.tertiary)
                    }
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
            .opacity(!task.isCompleted && !canMarkComplete ? 0.5 : 1.0)
            .onTapGesture {
                guard task.isCompleted || canMarkComplete else { return }
                onTap()
            }
        }
        .padding(.vertical, DesignSystem.Spacing.grid_1)
    }
}

// MARK: - Employee Selector View
struct EmployeeSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Employee> { $0.isActive })
    private var activeEmployees: [Employee]
    
    let task: ChecklistTask?
    
    private var clockedInEmployees: [Employee] {
        activeEmployees.filter { $0.isClockedIn }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if clockedInEmployees.isEmpty {
                    ContentUnavailableView(
                        "No Clocked In Employees",
                        systemImage: "person.slash",
                        description: Text("Employees must be clocked in to complete tasks")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(clockedInEmployees) { employee in
                        Button {
                            selectEmployee(employee)
                        } label: {
                            HStack {
                                Text(employee.name)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.primary)
                                
                                Spacer()
                                
                                Text(employee.role.rawValue)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Who completed this?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func selectEmployee(_ employee: Employee) {
        guard let task = task else { return }
        
        task.markComplete(by: employee.name)
        DesignSystem.HapticFeedback.trigger(.success)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to mark task complete: \(error)")
            DesignSystem.HapticFeedback.trigger(.error)
        }
    }
}

// MARK: - Add/Edit Checklist View
struct AddEditChecklistView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let checklist: ChecklistTemplate?
    
    @State private var title = ""
    @State private var tasks: [String] = [""]
    
    init(checklist: ChecklistTemplate? = nil) {
        self.checklist = checklist
        if let checklist = checklist {
            _title = State(initialValue: checklist.title)
            _tasks = State(initialValue: checklist.tasks.sorted(by: { $0.sortOrder < $1.sortOrder }).map { $0.title })
            if tasks.isEmpty {
                _tasks = State(initialValue: [""])
            }
        }
    }
    
    var body: some View {
        Form {
            Section("Checklist Information") {
                TextField("Checklist Title", text: $title)
            }
            
            Section("Tasks") {
                ForEach(tasks.indices, id: \.self) { index in
                    HStack {
                        TextField("Task \(index + 1)", text: $tasks[index])
                        
                        if tasks.count > 1 {
                            Button {
                                tasks.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .onMove { source, destination in
                    tasks.move(fromOffsets: source, toOffset: destination)
                }
                
                Button {
                    tasks.append("")
                } label: {
                    Label("Add Task", systemImage: "plus.circle.fill")
                }
            }
            
            if checklist != nil {
                Section {
                    Button(role: .destructive) {
                        deleteChecklist()
                    } label: {
                        Label("Delete Checklist", systemImage: "trash")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(checklist == nil ? "New Checklist" : "Edit Checklist")
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
                    saveChecklist()
                }
                .disabled(!isValid)
            }
        }
    }
    
    private var isValid: Bool {
        !title.isEmpty && tasks.contains(where: { !$0.isEmpty })
    }
    
    private func saveChecklist() {
        let validTasks = tasks.filter { !$0.isEmpty }
        
        if let checklist = checklist {
            // Update existing checklist
            checklist.title = title
            
            // Remove old tasks
            checklist.tasks.forEach { modelContext.delete($0) }
            
            // Add new tasks
            for (index, taskTitle) in validTasks.enumerated() {
                let task = ChecklistTask(title: taskTitle, sortOrder: index)
                task.template = checklist
                modelContext.insert(task)
            }
        } else {
            // Create new checklist
            let newChecklist = ChecklistTemplate(title: title)
            modelContext.insert(newChecklist)
            
            for (index, taskTitle) in validTasks.enumerated() {
                let task = ChecklistTask(title: taskTitle, sortOrder: index)
                task.template = newChecklist
                modelContext.insert(task)
            }
        }
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            DesignSystem.HapticFeedback.trigger(.error)
            print("Failed to save checklist: \(error)")
        }
    }
    
    private func deleteChecklist() {
        guard let checklist = checklist else { return }
        
        modelContext.delete(checklist)
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            DesignSystem.HapticFeedback.trigger(.error)
            print("Failed to delete checklist: \(error)")
        }
    }
}
