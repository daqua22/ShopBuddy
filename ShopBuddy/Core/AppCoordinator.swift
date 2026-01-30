import Foundation
import SwiftUI
import SwiftData

@Observable
final class AppCoordinator {
    
    // MARK: - View State
    enum ViewState {
        case publicView
        case employeeView(Employee)
        case managerView(Employee)
    }
    
    // MARK: - Properties
    var currentViewState: ViewState = .publicView
    var currentEmployee: Employee?
    var isAuthenticated: Bool = false
    
    // MARK: - Computed Properties
    var isManager: Bool {
        if case .managerView = currentViewState { return true }
        return false
    }
    
    var isEmployee: Bool {
        if case .employeeView = currentViewState { return true }
        return false
    }
    
    var isPublic: Bool {
        if case .publicView = currentViewState { return true }
        return false
    }
    
    // MARK: - Authentication
    
    /// Login with PIN
    func login(with pin: String, employees: [Employee]) -> Bool {
        guard let employee = employees.first(where: { $0.pin == pin && $0.isActive }) else {
            // FIXED: Updated to trigger syntax
            DesignSystem.HapticFeedback.trigger(DesignSystem.HapticType.error)
            return false
        }
        
        currentEmployee = employee
        isAuthenticated = true
        
        switch employee.role {
        case .manager:
            currentViewState = .managerView(employee)
        case .shiftLead, .employee:
            currentViewState = .employeeView(employee)
        }
        
        // FIXED: Updated to trigger syntax
        HapticFeedbackDesignSystem.HapticFeedback.trigger(.success)
        return true
    }
    
    /// Logout current user
    func logout() {
        currentEmployee = nil
        isAuthenticated = false
        currentViewState = .publicView
        // FIXED: Updated to trigger syntax
        HapticFeedback.trigger(.medium)
    }
    
    /// Get display name for current user
    var currentUserDisplayName: String {
        currentEmployee?.name ?? "Guest"
    }
    
    /// Get role display for current user
    var currentUserRole: String {
        currentEmployee?.role.rawValue ?? ""
    }
}

// MARK: - Tab Item Definition
enum TabItem: String, CaseIterable {
    case inventory = "Inventory"
    case checklists = "Checklists"
    case clockInOut = "Clock In/Out"
    case tips = "Tips"
    case employees = "Employees"
    case reports = "Reports"
    case payroll = "Payroll"
    
    var icon: String {
        switch self {
        case .inventory: return "shippingbox.fill"
        case .checklists: return "checklist"
        case .clockInOut: return "clock.fill"
        case .tips: return "dollarsign.circle.fill"
        case .employees: return "person.3.fill"
        case .reports: return "chart.bar.fill"
        case .payroll: return "banknote.fill"
        }
    }
    
    static func visibleTabs(for viewState: AppCoordinator.ViewState) -> [TabItem] {
        switch viewState {
        case .publicView:
            return [.inventory, .checklists, .clockInOut]
        case .employeeView:
            return [.inventory, .checklists, .clockInOut, .tips]
        case .managerView:
            return TabItem.allCases
        }
    }
}
