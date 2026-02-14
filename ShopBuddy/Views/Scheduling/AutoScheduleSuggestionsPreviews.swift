import SwiftUI
import SwiftData

#Preview("Auto-Schedule Suggestions") {
    let container = previewScheduleContainer()
    let coordinator = previewScheduleCoordinator(context: container.mainContext)

    return NavigationStack {
        AutoScheduleSuggestionsView()
    }
    .modelContainer(container)
    .environment(coordinator)
}

private func previewScheduleContainer() -> ModelContainer {
    do {
        let schema = Schema(versionedSchema: SchemaV3.self)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let existingEmployees = try context.fetch(FetchDescriptor<Employee>())
        if existingEmployees.isEmpty {
            seedSchedulingPreviewData(context: context)
        }

        return container
    } catch {
        fatalError("Failed to create preview container: \(error)")
    }
}

private func previewScheduleCoordinator(context: ModelContext) -> AppCoordinator {
    let coordinator = AppCoordinator()
    if let manager = try? context.fetch(FetchDescriptor<Employee>()).first(where: { $0.role == .manager }) {
        coordinator.currentEmployee = manager
        coordinator.isAuthenticated = true
        coordinator.currentViewState = .managerView(manager)
    }
    return coordinator
}

private func seedSchedulingPreviewData(context: ModelContext) {
    let shopId = ShopContext.activeShopID
    let tz = ShopContext.activeTimeZone
    let weekStart = ScheduleCalendarService.normalizedWeekStart(Date(), in: tz)

    let manager = Employee(name: "Avery", pin: "1111", role: .manager, hourlyWage: 28)
    let shiftLead = Employee(name: "Jordan", pin: "2222", role: .shiftLead, hourlyWage: 24)
    let employee1 = Employee(name: "Mia", pin: "3333", role: .employee, hourlyWage: 20)
    let employee2 = Employee(name: "Leo", pin: "4444", role: .employee, hourlyWage: 20)
    let employee3 = Employee(name: "Noah", pin: "5555", role: .employee, hourlyWage: 19)

    let team = [manager, shiftLead, employee1, employee2, employee3]
    team.forEach(context.insert)

    for employee in team {
        for day in [2, 3, 4, 5, 6] {
            context.insert(
                EmployeeAvailabilityWindow(
                    shopId: shopId,
                    employee: employee,
                    dayOfWeek: day,
                    startMinutes: 7 * 60,
                    endMinutes: 17 * 60
                )
            )
        }
    }

    context.insert(
        EmployeeUnavailableDate(
            shopId: shopId,
            employee: employee3,
            date: ScheduleCalendarService.date(for: weekStart, dayOfWeek: 4, minutesFromMidnight: 0, in: tz),
            reason: "Class schedule"
        )
    )

    for day in [2, 3, 4, 5, 6] {
        context.insert(
            CoverageRequirement(
                shopId: shopId,
                weekStartDate: weekStart,
                dayOfWeek: day,
                startMinutes: 7 * 60,
                endMinutes: 13 * 60,
                headcount: 2
            )
        )

        context.insert(
            CoverageRequirement(
                shopId: shopId,
                weekStartDate: weekStart,
                dayOfWeek: day,
                startMinutes: 13 * 60,
                endMinutes: 18 * 60,
                headcount: 2,
                roleRequirement: .shiftLead
            )
        )
    }

    try? context.save()
}
