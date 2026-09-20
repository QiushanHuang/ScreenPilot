import SwiftUI

/// The ScreenPilot display-and-cursor mark, without the app icon's background tile.
struct BrandMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 660, size.height / 580)
            context.translateBy(x: (size.width - 660 * scale) / 2,
                                y: (size.height - 580 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -165, y: -250)

            var rear = Path()
            rear.move(to: CGPoint(x: 374, y: 354))
            rear.addLine(to: CGPoint(x: 374, y: 308))
            rear.addQuadCurve(to: CGPoint(x: 404, y: 278), control: CGPoint(x: 374, y: 278))
            rear.addLine(to: CGPoint(x: 766, y: 278))
            rear.addQuadCurve(to: CGPoint(x: 796, y: 308), control: CGPoint(x: 796, y: 278))
            rear.addLine(to: CGPoint(x: 796, y: 550))
            rear.addQuadCurve(to: CGPoint(x: 766, y: 580), control: CGPoint(x: 796, y: 580))
            rear.addLine(to: CGPoint(x: 720, y: 580))
            context.stroke(rear, with: .color(AppPalette.accent.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 28, lineCap: .round))

            let front = Path(roundedRect: CGRect(x: 195, y: 369, width: 510, height: 340),
                             cornerRadius: 33)
            context.stroke(front, with: .color(AppPalette.accent), lineWidth: 30)
            context.fill(Path(roundedRect: CGRect(x: 424, y: 718, width: 52, height: 80),
                              cornerRadius: 12), with: .color(AppPalette.accent))
            context.fill(Path(roundedRect: CGRect(x: 338, y: 784, width: 224, height: 30),
                              cornerRadius: 15), with: .color(AppPalette.accent))
            var cursor = Path()
            cursor.move(to: CGPoint(x: 403, y: 471))
            cursor.addLines([CGPoint(x: 570, y: 543), CGPoint(x: 490, y: 571),
                             CGPoint(x: 458, y: 647)])
            cursor.closeSubpath()
            context.fill(cursor, with: .color(AppPalette.accent))
        }
        .accessibilityLabel("ScreenPilot")
    }
}
