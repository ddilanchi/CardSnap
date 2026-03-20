import SwiftUI

struct CardOverlayView: View {
    let points: [CGPoint]
    let color: Color

    var body: some View {
        if points.count == 4 {
            ZStack {
                // Filled overlay
                Path { p in
                    p.move(to: points[0])
                    points.dropFirst().forEach { p.addLine(to: $0) }
                    p.closeSubpath()
                }
                .fill(color.opacity(0.08))

                // Border
                Path { p in
                    p.move(to: points[0])
                    points.dropFirst().forEach { p.addLine(to: $0) }
                    p.closeSubpath()
                }
                .stroke(color, lineWidth: 3)
                .shadow(color: color.opacity(0.6), radius: 6)

                // Corner ticks
                ForEach(0..<4, id: \.self) { i in
                    cornerTick(at: points[i], index: i, color: color)
                }
            }
        }
    }

    @ViewBuilder
    private func cornerTick(at point: CGPoint, index: Int, color: Color) -> some View {
        let size: CGFloat = 20
        let lw: CGFloat = 4
        Canvas { ctx, _ in
            let dirs: [(CGFloat, CGFloat)] = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
            let (dx, dy) = dirs[index]
            var h = Path()
            h.move(to: CGPoint(x: point.x, y: point.y))
            h.addLine(to: CGPoint(x: point.x + dx * size, y: point.y))
            var v = Path()
            v.move(to: CGPoint(x: point.x, y: point.y))
            v.addLine(to: CGPoint(x: point.x, y: point.y + dy * size))
            ctx.stroke(h, with: .color(color), lineWidth: lw)
            ctx.stroke(v, with: .color(color), lineWidth: lw)
        }
        .frame(width: 1, height: 1)
    }
}
