import SwiftUI

private struct BoardShiftLaneLayout: Identifiable {
    let id: UUID
    let shift: ScheduleDraftShift
    let laneIndex: Int
    let laneCount: Int
}

private struct BoardGridScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

struct WeekGridCanvasView: View {
    @ObservedObject var viewModel: ScheduleBoardViewModel
    let canEdit: Bool

    @State private var editingShift: ScheduleDraftShift?
    @State private var scrollOffset: CGPoint = .zero

    private let headerHeight: CGFloat = 44
    private let timeAxisWidth: CGFloat = 76
    private let columnPadding: CGFloat = 4

    private var dayOrder: [Int] {
        ScheduleDayMapper.orderedDays
    }

    private var dayAreaWidth: CGFloat {
        viewModel.dayColumnWidth * CGFloat(dayOrder.count)
    }

    private var gridHeight: CGFloat {
        CGFloat(viewModel.visibleTotalMinutes) * viewModel.pixelsPerMinute
    }

    private var canvasWidth: CGFloat {
        timeAxisWidth + dayAreaWidth
    }

    private var canvasHeight: CGFloat {
        headerHeight + gridHeight
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                contentCanvas
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: BoardGridScrollOffsetKey.self,
                                value: proxy.frame(in: .named("schedule-board-scroll")).origin
                            )
                        }
                    )
            }
            .coordinateSpace(name: "schedule-board-scroll")
            .onPreferenceChange(BoardGridScrollOffsetKey.self) { origin in
                scrollOffset = CGPoint(x: -origin.x, y: -origin.y)
            }
            .overlay(alignment: .topLeading) {
                stickyTopHeader(viewportWidth: geometry.size.width)
                    .allowsHitTesting(false)
                    .zIndex(2)
            }
            .overlay(alignment: .topLeading) {
                stickyTimeAxis(viewportHeight: geometry.size.height)
                    .allowsHitTesting(false)
                    .zIndex(3)
            }
            .overlay(alignment: .topLeading) {
                stickyTopLeftCell
                    .allowsHitTesting(false)
                    .zIndex(4)
            }
        }
        .sheet(item: $editingShift) { shift in
            EditShiftPopover(
                employees: viewModel.allEmployees.filter(\.isActive),
                shift: shift,
                visibleStartMinutes: viewModel.visibleStartMinutes,
                visibleEndMinutes: viewModel.visibleEndMinutes
            ) { updated in
                viewModel.updateShift(updated)
            } onDelete: {
                viewModel.deleteShift(shift.id)
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 560)
            #endif
        }
    }

    private var contentCanvas: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: canvasWidth, height: canvasHeight)

            gridBackground
                .frame(width: dayAreaWidth, height: gridHeight)
                .offset(x: timeAxisWidth, y: headerHeight)

            heatMapOverlay
                .offset(x: timeAxisWidth, y: headerHeight)

            shiftsOverlay
                .offset(x: timeAxisWidth, y: headerHeight)
        }
    }

    private var gridBackground: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<max(1, viewModel.visibleTotalMinutes / 30), id: \.self) { row in
                Rectangle()
                    .fill(row.isMultiple(of: 2) ? Color.primary.opacity(0.02) : Color.clear)
                    .frame(height: CGFloat(30) * viewModel.pixelsPerMinute)
                    .offset(y: CGFloat(row * 30) * viewModel.pixelsPerMinute)
            }

            ForEach(Array(stride(from: viewModel.visibleStartMinutes, through: viewModel.visibleEndMinutes, by: 15)), id: \.self) { minute in
                let y = CGFloat(minute - viewModel.visibleStartMinutes) * viewModel.pixelsPerMinute
                let isMajor = minute % 30 == 0
                Rectangle()
                    .fill(isMajor ? Color.primary.opacity(0.14) : Color.primary.opacity(0.07))
                    .frame(height: isMajor ? 1 : 0.5)
                    .offset(y: y)
            }

            ForEach(0...dayOrder.count, id: \.self) { index in
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: gridHeight)
                    .offset(x: CGFloat(index) * viewModel.dayColumnWidth)
            }
        }
    }

    @ViewBuilder
    private var heatMapOverlay: some View {
        if viewModel.showHeatMap {
            ZStack(alignment: .topLeading) {
                ForEach(dayOrder, id: \.self) { day in
                    let dayIndex = dayOrder.firstIndex(of: day) ?? 0
                    let x = CGFloat(dayIndex) * viewModel.dayColumnWidth
                    let buckets = viewModel.coverageEvaluation.bucketsByDay[day] ?? []

                    ForEach(buckets) { bucket in
                        let y = CGFloat(bucket.bucketStartMinutes - viewModel.visibleStartMinutes) * viewModel.pixelsPerMinute
                        Rectangle()
                            .fill(heatColor(for: bucket.delta))
                            .frame(width: viewModel.dayColumnWidth, height: max(2, 15 * viewModel.pixelsPerMinute))
                            .offset(x: x, y: y)
                    }
                }
            }
            .frame(width: dayAreaWidth, height: gridHeight, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    private var shiftsOverlay: some View {
        let renderedShifts = viewModel.displayedShifts
        let allLayouts = dayOrder.flatMap { day in
            layoutsForDay(day, shifts: renderedShifts)
        }

        return ZStack(alignment: .topLeading) {
            ForEach(dayOrder, id: \.self) { day in
                let dayIndex = dayOrder.firstIndex(of: day) ?? 0
                let dayX = CGFloat(dayIndex) * viewModel.dayColumnWidth

                Color.clear
                    .frame(width: viewModel.dayColumnWidth, height: gridHeight)
                    .dropDestination(for: String.self) { items, location in
                        guard canEdit else { return false }
                        guard let first = items.first, let employeeId = UUID(uuidString: first) else { return false }
                        let startMinutes = viewModel.minutes(fromY: location.y)
                        viewModel.addShift(employeeId: employeeId, dayOfWeek: day, startMinutes: startMinutes)
                        return true
                    }
                .offset(x: dayX)
            }

            ForEach(allLayouts) { layout in
                let dayIndex = dayOrder.firstIndex(of: layout.shift.dayOfWeek) ?? 0
                let dayX = CGFloat(dayIndex) * viewModel.dayColumnWidth
                let laneWidth = max(46, (viewModel.dayColumnWidth - columnPadding * 2) / CGFloat(max(1, layout.laneCount)))
                let x = dayX + columnPadding + CGFloat(layout.laneIndex) * laneWidth
                let y = viewModel.yPosition(for: layout.shift)
                let blockHeight = viewModel.height(for: layout.shift)

                ShiftBlockView(
                    shift: layout.shift,
                    title: employeeName(for: layout.shift),
                    subtitle: "\(ScheduleCalendarService.timeLabel(for: layout.shift.startMinutes)) – \(ScheduleCalendarService.timeLabel(for: layout.shift.endMinutes))",
                    width: max(40, laneWidth - 4),
                    height: blockHeight,
                    borderColor: viewModel.shiftBorderColor(layout.shift),
                    showWarningBadge: (viewModel.warningsByShiftId[layout.shift.id] ?? []).isEmpty == false
                ) {
                    viewModel.selectShift(layout.shift.id)
                    editingShift = layout.shift
                } onMoveStart: {
                    guard canEdit else { return }
                    viewModel.selectShift(layout.shift.id)
                    viewModel.beginDrag(for: layout.shift.id)
                } onMoveChanged: { translation in
                    guard canEdit else { return }
                    viewModel.dragShift(layout.shift.id, translation: translation)
                } onMoveEnd: {
                    guard canEdit else { return }
                    viewModel.endDrag(for: layout.shift.id)
                } onResizeTopChanged: { delta in
                    guard canEdit else { return }
                    viewModel.selectShift(layout.shift.id)
                    viewModel.resizeShiftStart(layout.shift.id, deltaY: delta)
                } onResizeTopEnd: {
                    guard canEdit else { return }
                    viewModel.endResize(for: layout.shift.id)
                } onResizeBottomChanged: { delta in
                    guard canEdit else { return }
                    viewModel.selectShift(layout.shift.id)
                    viewModel.resizeShiftEnd(layout.shift.id, deltaY: delta)
                } onResizeBottomEnd: {
                    guard canEdit else { return }
                    viewModel.endResize(for: layout.shift.id)
                }
                .contextMenu {
                    Button("Edit Shift", systemImage: "pencil") {
                        viewModel.selectShift(layout.shift.id)
                        editingShift = layout.shift
                    }
                    Button("Delete Shift", systemImage: "trash", role: .destructive) {
                        viewModel.selectShift(layout.shift.id)
                        viewModel.deleteShift(layout.shift.id)
                    }
                }
                .offset(x: x, y: y)
                .dropDestination(for: String.self) { items, _ in
                    guard canEdit else { return false }
                    guard let first = items.first, let employeeId = UUID(uuidString: first) else { return false }
                    viewModel.reassignShift(layout.shift.id, employeeId: employeeId)
                    return true
                }
            }
        }
        .frame(width: dayAreaWidth, height: gridHeight, alignment: .topLeading)
    }

    private func stickyTopHeader(viewportWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: timeAxisWidth, height: headerHeight)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: headerHeight)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.16))
                            .frame(height: 1)
                    }

                HStack(spacing: 0) {
                    ForEach(dayOrder, id: \.self) { day in
                        VStack(spacing: 2) {
                            Text(ScheduleDayMapper.shortName(for: day))
                                .font(.caption.weight(.semibold))
                            Text(dayDateLabel(day))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: viewModel.dayColumnWidth, height: headerHeight)
                    }
                }
                .offset(x: -scrollOffset.x)
            }
            .frame(width: max(0, viewportWidth - timeAxisWidth), height: headerHeight, alignment: .leading)
            .clipped()
        }
        .frame(height: headerHeight)
    }

    private func stickyTimeAxis(viewportHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(width: timeAxisWidth, height: headerHeight)

            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.16))
                            .frame(width: 1)
                    }

                timeAxisContent
                    .offset(y: -scrollOffset.y)
            }
            .frame(width: timeAxisWidth, height: max(0, viewportHeight - headerHeight), alignment: .top)
            .clipped()
        }
        .frame(width: timeAxisWidth, alignment: .leading)
    }

    private var stickyTopLeftCell: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Text("Time")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: timeAxisWidth, height: headerHeight)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.16))
                .frame(height: 1)
        }
    }

    private var timeAxisContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: viewModel.visibleStartMinutes, to: viewModel.visibleEndMinutes, by: 30)), id: \.self) { minute in
                ZStack(alignment: .topTrailing) {
                    let showLabel = minute == viewModel.visibleStartMinutes || minute % 60 == 0
                    if showLabel {
                        Text(ScheduleCalendarService.timeLabel(for: minute))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                            .offset(y: -8)
                    }
                }
                .frame(height: CGFloat(30) * viewModel.pixelsPerMinute, alignment: .topTrailing)
            }
        }
        .frame(width: timeAxisWidth, height: gridHeight, alignment: .topTrailing)
    }

    private func dayDateLabel(_ dayIndex: Int) -> String {
        let dayDate = viewModel.dateForDayIndex(dayIndex)
        return ScheduleCalendarService.abbreviatedDateLabel(for: dayDate, in: viewModel.displayTimeZone)
    }

    private func employeeName(for shift: ScheduleDraftShift) -> String {
        guard let employeeId = shift.employeeId else { return "Open Shift" }
        return viewModel.employeesById[employeeId]?.name ?? "Unassigned"
    }

    private func heatColor(for delta: Int) -> Color {
        if delta < 0 {
            return DesignSystem.Colors.error.opacity(min(0.36, 0.08 + Double(abs(delta)) * 0.08))
        }
        if delta > 0 {
            return DesignSystem.Colors.success.opacity(min(0.28, 0.05 + Double(delta) * 0.05))
        }
        return Color.clear
    }

    private func layoutsForDay(_ dayOfWeek: Int, shifts: [ScheduleDraftShift]) -> [BoardShiftLaneLayout] {
        let dayShifts = shifts
            .filter { $0.dayOfWeek == dayOfWeek }
            .sorted {
                if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
                return $0.endMinutes < $1.endMinutes
            }

        guard !dayShifts.isEmpty else { return [] }

        var results: [BoardShiftLaneLayout] = []
        var cluster: [ScheduleDraftShift] = []
        var clusterMaxEnd = -1

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            var laneEndByIndex: [Int] = []
            var assignments: [(ScheduleDraftShift, Int)] = []

            for shift in cluster {
                if let reusableLane = laneEndByIndex.firstIndex(where: { $0 <= shift.startMinutes }) {
                    assignments.append((shift, reusableLane))
                    laneEndByIndex[reusableLane] = shift.endMinutes
                } else {
                    assignments.append((shift, laneEndByIndex.count))
                    laneEndByIndex.append(shift.endMinutes)
                }
            }

            let laneCount = max(1, laneEndByIndex.count)
            assignments.forEach { shift, lane in
                results.append(
                    BoardShiftLaneLayout(
                        id: shift.id,
                        shift: shift,
                        laneIndex: lane,
                        laneCount: laneCount
                    )
                )
            }

            cluster.removeAll(keepingCapacity: true)
            clusterMaxEnd = -1
        }

        for shift in dayShifts {
            if cluster.isEmpty {
                cluster = [shift]
                clusterMaxEnd = shift.endMinutes
                continue
            }

            if shift.startMinutes < clusterMaxEnd {
                cluster.append(shift)
                clusterMaxEnd = max(clusterMaxEnd, shift.endMinutes)
            } else {
                flushCluster()
                cluster = [shift]
                clusterMaxEnd = shift.endMinutes
            }
        }

        flushCluster()
        return results
    }
}
