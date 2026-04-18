import SwiftUI

struct DraggableProgressBar: View {
    @Binding var progress: Double
    @Binding var isDragging: Bool
    let duration: Double
    let onEditingChanged: (Bool) -> Void
    let onSeek: (Double) -> Void
    let onScrub: (Double) -> Void

    @State private var dragProgress: Double = 0
    @State private var isDraggingInternal = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 6)

                Capsule()
                    .fill(Color.white)
                    .frame(width: CGFloat(clampedProgress(dragProgress)) * width, height: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value: value, width: width)
                    }
                    .onEnded { value in
                        handleDragEnd(value: value, width: width)
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
        .frame(height: 44)
    }

    private func handleDrag(value: DragGesture.Value, width: CGFloat) {
        guard width > 0, duration > 0 else { return }

        if !isDraggingInternal {
            isDraggingInternal = true
            isDragging = true
            onEditingChanged(true)
        }

        let location = value.location.x
        let newProgress = clampedProgress(location / width)
        updateDrag(to: newProgress)
    }

    private func handleDragEnd(value: DragGesture.Value, width: CGFloat) {
        guard width > 0, duration > 0 else { return }

        let location = value.location.x
        let finalProgress = clampedProgress(location / width)
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
