import SwiftUI

struct DraggableProgressBar: View {
    @Binding var progress: Double
    @Binding var isDragging: Bool
    let duration: Double
    let videoContentRatio: CGFloat
    let onEditingChanged: (Bool) -> Void
    let onSeek: (Double) -> Void
    let onScrub: (Double) -> Void

    @State private var dragProgress: Double = 0
    @State private var isDraggingInternal = false

    private let gap: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let videoWidth = totalWidth * videoContentRatio
            let edgeInset = (totalWidth - videoWidth) / 2
            let sidePadding = edgeInset + gap
            let barWidth = max(totalWidth - (sidePadding * 2), 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.white)
                    .frame(width: CGFloat(clampedProgress(dragProgress)) * barWidth, height: 4)
            }
            .padding(.horizontal, sidePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value: value, barWidth: barWidth, sidePadding: sidePadding)
                    }
                    .onEnded { value in
                        handleDragEnd(value: value, barWidth: barWidth, sidePadding: sidePadding)
                    }
            )
            .onAppear {
                dragProgress = clampedProgress(progress)
            }
            .onChange(of: progress) { newValue in
                if !isDraggingInternal {
                    dragProgress = clampedProgress(newValue)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("播放进度")
            .accessibilityValue("\(Int(clampedProgress(dragProgress) * 100))%")
        }
        .frame(height: 20)
    }

    private func handleDrag(value: DragGesture.Value, barWidth: CGFloat, sidePadding: CGFloat) {
        guard barWidth > 0 else { return }

        if !isDraggingInternal {
            isDraggingInternal = true
            isDragging = true
            onEditingChanged(true)
        }

        let location = value.location.x - sidePadding
        let newProgress = clampedProgress(location / barWidth)
        updateDrag(to: newProgress)
    }

    private func handleDragEnd(value: DragGesture.Value, barWidth: CGFloat, sidePadding: CGFloat) {
        guard barWidth > 0 else { return }

        let location = value.location.x - sidePadding
        let finalProgress = clampedProgress(location / barWidth)
        updateDrag(to: finalProgress)
        onSeek(finalProgress * duration)

        isDragging = false
        isDraggingInternal = false
        onEditingChanged(false)
    }

    private func updateDrag(to progressValue: Double) {
        let clamped = clampedProgress(progressValue)
        dragProgress = clamped
        progress = clamped
        onScrub(clamped * duration)
    }

    private func clampedProgress(_ progressValue: Double) -> Double {
        min(max(progressValue, 0), 1)
    }
}
