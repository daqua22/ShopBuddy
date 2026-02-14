import SwiftUI

struct ShiftBlockView: View {
    let shift: ScheduleDraftShift
    let title: String
    let subtitle: String
    let width: CGFloat
    let height: CGFloat
    let borderColor: Color
    let showWarningBadge: Bool

    let onTap: () -> Void
    let onMoveStart: () -> Void
    let onMoveChanged: (CGSize) -> Void
    let onMoveEnd: () -> Void
    let onResizeTopChanged: (CGFloat) -> Void
    let onResizeTopEnd: () -> Void
    let onResizeBottomChanged: (CGFloat) -> Void
    let onResizeBottomEnd: () -> Void

    @State private var isMoving = false
    @State private var isResizing = false

    private let handleTouchSize: CGFloat = 44

    private var resolvedHeight: CGFloat {
        max(32, height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(blockColor(seed: shift.colorSeed).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(borderColor, lineWidth: 1.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 6) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if showWarningBadge {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                Text(subtitle)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.86))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)

            VStack(spacing: 0) {
                resizeHandle(isTop: true)
                    .frame(height: handleTouchSize)
                Spacer(minLength: 0)
                resizeHandle(isTop: false)
                    .frame(height: handleTouchSize)
            }
        }
        .frame(width: width, height: resolvedHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isMoving, !isResizing else { return }
            onTap()
        }
        .simultaneousGesture(moveGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title), \(subtitle)")
    }

    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard !isResizing else { return }
                guard case .second(true, let drag?) = value else { return }

                if !isMoving {
                    isMoving = true
                    onMoveStart()
                }
                onMoveChanged(drag.translation)
            }
            .onEnded { _ in
                guard isMoving else { return }
                isMoving = false
                onMoveEnd()
            }
    }

    @ViewBuilder
    private func resizeHandle(isTop: Bool) -> some View {
        let visualHandle = RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.white.opacity(0.95))
            .frame(width: 34, height: 3)
            .padding(.top, isTop ? 4 : 0)
            .padding(.bottom, isTop ? 0 : 4)

        let dragGesture = DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if !isResizing {
                    isResizing = true
                }
                if isTop {
                    onResizeTopChanged(value.translation.height)
                } else {
                    onResizeBottomChanged(value.translation.height)
                }
            }
            .onEnded { _ in
                isResizing = false
                if isTop {
                    onResizeTopEnd()
                } else {
                    onResizeBottomEnd()
                }
            }

        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(alignment: isTop ? .top : .bottom) {
                visualHandle
            }
            .highPriorityGesture(dragGesture)
            .zIndex(10)
    }

    private func blockColor(seed: String) -> Color {
        let palette: [Color] = [.blue, .teal, .green, .orange, .pink, .purple, .indigo]
        let hash = UInt(bitPattern: seed.hashValue)
        return palette[Int(hash % UInt(palette.count))]
    }
}
