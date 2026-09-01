import CoreGraphics

struct ShortRenderGeometry: Equatable {
    let renderSize: CGSize
    let displaySize: CGSize
    let scaledDisplaySize: CGSize
    let cropOffset: CGPoint
    let scale: CGFloat
}

enum ShortRenderGeometryBuilder {
    static let renderSize = CGSize(width: 1080, height: 1920)

    static func make(displaySize: CGSize, crop: ShortCropPlan) -> ShortRenderGeometry {
        guard displaySize.width > 0, displaySize.height > 0 else {
            return ShortRenderGeometry(
                renderSize: renderSize,
                displaySize: displaySize,
                scaledDisplaySize: renderSize,
                cropOffset: .zero,
                scale: 1
            )
        }

        let zoom = CGFloat(min(max(crop.zoom, 1), 3))
        let baseScale = max(renderSize.width / displaySize.width, renderSize.height / displaySize.height)
        let scale = baseScale * zoom
        let scaledSize = CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
        let overflowX = max(0, scaledSize.width - renderSize.width)
        let overflowY = max(0, scaledSize.height - renderSize.height)
        let focusX = CGFloat(min(max(crop.focusX, 0), 1))
        let focusY = CGFloat(min(max(crop.focusY, 0), 1))

        return ShortRenderGeometry(
            renderSize: renderSize,
            displaySize: displaySize,
            scaledDisplaySize: scaledSize,
            cropOffset: CGPoint(x: overflowX * focusX, y: overflowY * focusY),
            scale: scale
        )
    }
}
