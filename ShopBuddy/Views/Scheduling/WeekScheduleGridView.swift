import SwiftUI

private struct ScheduleGridScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

private struct ShiftLaneLayout: Identifiable {
    let id: UUID
    let shift: WeekScheduledShift
    let laneIndex: Int
    let laneCount: Int
}

struct WeekScheduleGridView: View {
    @ObservedObject var viewModel: WeekScheduleViewModel
    let onShiftTap: (WeekScheduledShift) -> Void

    private let headerHeight: CGFloat = 44
    private let timeAxisWidth: CGFloat = 78
    private let columnPadding: CGFloat = 4

    @State private var scrollOffset: CGPoint = .zero

    private var orderedDays: [Int] {
        viewModel.dayOrderMondayFirst
    }

    private var dayAreaWidth: CGFloat {
        viewModel.dayColumnWidth * CGFloat(orderedDays.count)
    }

    private var gridHeight: CGFloat {
        CGFloat(viewModel.totalVisibleMinutes) * viewModel.pixelsPerMinute
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
                                key: ScheduleGridScrollOffsetKey.self,
                                value: proxy.frame(in: .named("week-grid-scroll")).origin
                            )
                        }
                    )
            }
            .coordinateSpace(name: "week-grid-scroll")
            .onPreferenceChange(ScheduleGridScrollOffsetKey.self) { origin in
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
    }

    private var contentCanvas: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: canvasWidth, height: canvasHeight)

            gridBackground
                .frame(width: dayAreaWidth, height: gridHeight)
                .offset(x: timeAxisWidth, y: headerHeight)

            shiftsOverlay
                .offset(x: timeAxisWidth, y: headerHeight)
        }
    }

    private var gridBackground: some View {
        ZStack(alignment: .topLeading) {
            // Alternating 30-minute row shading
            ForEach(0..<max(1, viewModel.totalVisibleMinutes / 30), id: \.self) { row in
                Rectangle()
                    .fill(row.isMultiple(of: 2) ? Color.primary.opacity(0.02) : Color.clear)
                    .frame(height: CGFloat(30) * viewModel.pixelsPerMinute)
                    .offset(y: CGFloat(row * 30) * viewModel.pixelsPerMinute)
            }

            // 15-minute subticks + 30-minute lines
            ForEach(Array(stride(from: viewModel.visibleStartMinutes, through: viewModel.visibleEndMinutes, by: 15)), id: \.self) { minute in
                let y = CGFloat(minute - viewModel.visibleStartMinutes) * viewModel.pixelsPerMinute
                let isMajor = minute % 30 == 0
                Rectangle()
                    .fill(isMajor ? Color.primary.opacity(0.14) : Color.primary.opacity(0.07))
                    .frame(height: isMajor ? 1 : 0.5)
                    .offset(y: y)
            }

            // Day separators
            ForEach(0...orderedDays.count, id: \.self) { index in
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: gridHeight)
                    .offset(x: CGFloat(index) * viewModel.dayColumnWidth)
            }
        }
    }

    private var shiftsOverlay: some View {
        ZStack(alignment: .topLeading) {
            ForEach(orderedDays, id: \.self) { day in
                let dayLayouts = layoutsForDay(day)
                let dayIndex = orderedDays.firstIndex(of: day) ?? 0
                ForEach(dayLayouts) { layout in
                    let laneWidth = max(44, (viewModel.dayColumnWidth - columnPadding * 2) / CGFloat(max(1, layout.laneCount)))
                    let x = CGFloat(dayIndex) * viewModel.dayColumnWidth + columnPadding + CGFloat(layout.laneIndex) * laneWidth
                    let y = viewModel.shiftYPosition(layout.shift)
                    let height = viewModel.shiftHeight(layout.shift)

                    LegacyWeekShiftBlockView(
                        shift: layout.shift,
                        width: max(40, laneWidth - 4),
                        height: height,
                        pixelsPerMinute: viewModel.pixelsPerMinute
                    ) {
                        onShiftTap(layout.shift)
                    } onDragStart: {
                        viewModel.beginDrag(for: layout.shift.id)
                    } onDragChanged: { delta in
                        viewModel.moveShift(layout.shift.id, deltaMinutes: delta)
                    } onDragEnd: {
                        viewModel.endDrag(for: layout.shift.id)
                    }
                    .offset(x: x, y: y)
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
                    ForEach(orderedDays, id: \.self) { day in
                        VStack(spacing: 2) {
                            Text(shortDayName(day))
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

    private func shortDayName(_ day: Int) -> String {
        switch day {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return "Day"
        }
    }

    private func dayDateLabel(_ day: Int) -> String {
        let date = ScheduleCalendarService.date(
            for: viewModel.weekStartDate,
            dayOfWeek: day,
            minutesFromMidnight: 12 * 60,
            in: ShopContext.activeTimeZone
        )
        return ScheduleCalendarService.abbreviatedDateLabel(for: date, in: ShopContext.activeTimeZone)
    }

    private func layoutsForDay(_ dayOfWeek: Int) -> [ShiftLaneLayout] {
        let dayShifts = viewModel.shifts
            .filter { $0.dayOfWeek == dayOfWeek }
            .sorted {
                if $0.startMinutes != $1.startMinutes { return $0.startMinutes < $1.startMinutes }
                return $0.endMinutes < $1.endMinutes
            }

        guard !dayShifts.isEmpty else { return [] }

        var results: [ShiftLaneLayout] = []
        var cluster: [WeekScheduledShift] = []
        var clusterMaxEnd = -1

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            var laneEndByIndex: [Int] = []
            var assignments: [(WeekScheduledShift, Int)] = []

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
                    ShiftLaneLayout(
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
