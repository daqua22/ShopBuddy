//
//  ChecklistsView.swift
//  ShopBuddy
//
//  Created by Dan on 1/29/26.
//

import SwiftUI
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
    
    private var canEdit: Bool {
        coordinator.isManager
    }
    
    private var canMarkComplete: Bool {
        coordinator.isManager || coordinator.currentEmployee?.isClockedIn == true
    }
    
    var body: some View {
        NavigationStack {
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
                AddEditChecklistView()
            }
            .sheet(item: $editingChecklist) { checklist in
                AddEditChecklistView(checklist: checklist)
            }
            .sheet(isPresented: $showingEmployeeSelector) {
                EmployeeSelectorView(task: selectedTask)
            }
        }
    }
    
    private var checklistsList: some View {
        VStack(spacing: DesignSystem.Spacing.grid_3) {
            ForEach(checklists) { checklist in
                ChecklistCard(
                    checklist: checklist,
                    canEdit: canEdit,
                    canMarkComplete: canMarkComplete,
                    onEdit: {
                        editingChecklist = checklist
                    },
                    onTaskTap: { task in
                        selectedTask = task
                        showingEmployeeSelector = true
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
        DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.success)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to reset checklist: \(error)")
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
        }
    }
}

// MARK: - Checklist Card
struct ChecklistCard: View {
    
    @Bindable var checklist: ChecklistTemplate
    let canEdit: Bool
    let canMarkComplete: Bool
    let onEdit: () -> Void
    let onTaskTap: (ChecklistTask) -> Void
    let onReset: () -> Void
    
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
                    Menu {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit Checklist", systemImage: "pencil")
                        }
                        
                        Button {
                            onReset()
                        } label: {
                            Label("Reset All Tasks", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundColor(DesignSystem.Colors.primary)
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
                        onTap: {
                            if !task.isCompleted && canMarkComplete {
                                onTaskTap(task)
                            }
                        }
                    )
                }
            }
        }
        .padding(DesignSystem.Spacing.grid_2)
        .glassCard()
    }
}

// MARK: - Checklist Task Row
struct ChecklistTaskRow: View {
    
    @Bindable var task: ChecklistTask
    let canMarkComplete: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: DesignSystem.Spacing.grid_2) {
                // Checkbox
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
            .padding(.vertical, DesignSystem.Spacing.grid_1)
        }
        .disabled(task.isCompleted || !canMarkComplete)
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
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.background)
            .navigationTitle("Who completed this?")
            .navigationBarTitleDisplayMode(.inline)
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
        DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.success)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to mark task complete: \(error)")
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
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
        NavigationStack {
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
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.background)
            .navigationTitle(checklist == nil ? "New Checklist" : "Edit Checklist")
            .navigationBarTitleDisplayMode(.inline)
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
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
            print("Failed to save checklist: \(error)")
        }
    }
    
    private func deleteChecklist() {
        guard let checklist = checklist else { return }
        
        modelContext.delete(checklist)
        
        do {
            try modelContext.save()
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.success)
            dismiss()
        } catch {
            DesignSystem.HapticFeedbackDesignSystem.HapticFeedback.trigger(.error)
            print("Failed to delete checklist: \(error)")
        }
    }
}
