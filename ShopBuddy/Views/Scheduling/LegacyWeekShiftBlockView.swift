import SwiftUI

struct LegacyWeekShiftBlockView: View {
    let shift: WeekScheduledShift
    let width: CGFloat
    let height: CGFloat
    let pixelsPerMinute: CGFloat
    let onTap: () -> Void
    let onDragStart: () -> Void
    let onDragChanged: (Int) -> Void
    let onDragEnd: () -> Void

    @State private var hasStartedDrag = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(shift.color.opacity(0.9))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shift.employeeName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("\(timeLabel(shift.startMinutes)) - \(timeLabel(shift.endMinutes))")
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.white)
                .padding(6)
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .highPriorityGesture(moveGesture)
            .accessibilityLabel("\(shift.employeeName), \(timeLabel(shift.startMinutes)) to \(timeLabel(shift.endMinutes))")
            .accessibilityAddTraits(.isButton)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if !hasStartedDrag {
                    hasStartedDrag = true
                    onDragStart()
                }
                let rawDelta = Int((value.translation.height / pixelsPerMinute).rounded())
                let snappedDelta = (rawDelta / 15) * 15
                onDragChanged(snappedDelta)
            }
            .onEnded { _ in
                hasStartedDrag = false
                onDragEnd()
            }
    }

    private func timeLabel(_ minutes: Int) -> String {
        ScheduleCalendarService.timeLabel(for: minutes)
    }
}
