import Foundation
import SwiftUI
import SwiftData

@Observable
final class AppCoordinator {
    enum ViewState {
        case publicView
        case employeeView(Employee)
        case managerView(Employee)
    }
    
    var currentViewState: ViewState = .publicView
    var currentEmployee: Employee?
    var isAuthenticated: Bool = false
    var requestedTab: TabItem?
    
    var isManager: Bool {
        if case .managerView = currentViewState { return true }
        return false
    }

    func login(with pin: String, employees: [Employee]) -> Bool {
        guard let employee = employees.first(where: { $0.matchesPIN(pin) && $0.isActive }) else { return false }
        currentEmployee = employee
        isAuthenticated = true
        switch employee.role {
        case .manager: currentViewState = .managerView(employee)
        default: currentViewState = .employeeView(employee)
        }
        return true
    }
    
    func logout() {
        currentEmployee = nil
        isAuthenticated = false
        currentViewState = .publicView
        requestedTab = nil
    }

    var currentUserDisplayName: String { currentEmployee?.name ?? "Guest" }
    var currentUserRole: String { currentEmployee?.role.rawValue ?? "" }
}

enum TabItem: String, CaseIterable {
    case dashboard = "Dashboard"
    case schedule = "Schedule"
    case recipes = "Recipes"
    case inventory = "Inventory"
    case checklists = "Checklists"
    case dailyTasks = "Daily Tasks"
    case clockInOut = "Clock In/Out"
    case tips = "Tips"
    case employees = "Employees"
    case reports = "Reports"
    case paySummary = "Pay Summary"
    case settings = "Settings"
    
    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .schedule: return "calendar.badge.clock"
        case .recipes: return "book.fill"
        case .inventory: return "shippingbox.fill"
        case .checklists: return "checklist"
        case .dailyTasks: return "note.text"
        case .clockInOut: return "clock.fill"
        case .tips: return "dollarsign.circle.fill"
        case .employees: return "person.3.fill"
        case .reports: return "chart.bar.fill"
        case .paySummary: return "banknote.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    static func visibleTabs(for viewState: AppCoordinator.ViewState) -> [TabItem] {
        switch viewState {
        case .publicView:
            return [.dashboard, .recipes, .inventory, .checklists, .dailyTasks, .clockInOut]
        case .employeeView:
            return [.dashboard, .schedule, .recipes, .inventory, .checklists, .dailyTasks, .clockInOut, .tips]
        case .managerView:
            return [.dashboard, .schedule, .recipes, .inventory, .checklists, .dailyTasks, .clockInOut, .tips, .employees, .reports, .paySummary, .settings]
        }
    }
}
