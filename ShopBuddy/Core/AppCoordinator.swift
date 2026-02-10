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
    }

    var currentUserDisplayName: String { currentEmployee?.name ?? "Guest" }
    var currentUserRole: String { currentEmployee?.role.rawValue ?? "" }
}

enum TabItem: String, CaseIterable {
    case dashboard = "Dashboard"
    case inventory = "Inventory"
    case checklists = "Checklists"
    case clockInOut = "Clock In/Out"
    case tips = "Tips"
    case employees = "Employees"
    case reports = "Reports"
    case payroll = "Payroll"
    case settings = "Settings"
    
    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .inventory: return "shippingbox.fill"
        case .checklists: return "checklist"
        case .clockInOut: return "clock.fill"
        case .tips: return "dollarsign.circle.fill"
        case .employees: return "person.3.fill"
        case .reports: return "chart.bar.fill"
        case .payroll: return "banknote.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    static func visibleTabs(for viewState: AppCoordinator.ViewState) -> [TabItem] {
        switch viewState {
        case .publicView:
            return [.dashboard, .inventory, .checklists, .clockInOut]
        case .employeeView:
            return [.dashboard, .inventory, .checklists, .clockInOut, .tips]
        case .managerView:
            return [.dashboard, .inventory, .checklists, .clockInOut, .tips, .employees, .reports, .payroll, .settings]
        }
    }
}
