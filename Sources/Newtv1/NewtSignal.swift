import SwiftUI

enum NewtSignalState { case idle, listening, working, attention }

/// A small luminous core with restrained breathing, audio ripples, and orbiting work trails.
struct NewtSignal: View {
    var state: NewtSignalState = .idle
    var level: Float = 0
    var tint: Color
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = animated && !reduceMotion
        TimelineView(.animation(minimumInterval: state == .idle ? 1.0 / 12 : 1.0 / 30, paused: !moving)) { timeline in
            Canvas { context, size in
                let time = moving ? timeline.date.timeIntervalSinceReferenceDate : 0
                let color: Color = state == .attention ? .orange : tint
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let side = min(size.width, size.height)
                let audio = moving && state == .listening ? CGFloat(min(max(level, 0), 1)) : 0
                let breathe = moving ? CGFloat(sin(time * (state == .listening ? 2.8 : 1.6))) : 0
                let radius = side * (0.135 + audio * 0.07) * (1 + breathe * 0.06)
                func circle(_ radius: CGFloat, at point: CGPoint) -> Path { Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)) }
                context.fill(circle(side * 0.48, at: center), with: .radialGradient(Gradient(colors: [color.opacity(0.24 + Double(audio) * 0.2), color.opacity(0.07), .clear]), center: center, startRadius: 0, endRadius: side * 0.48))

                if state == .working {
                    for index in 0..<2 {
                        var ring = context
                        ring.translateBy(x: center.x, y: center.y)
                        ring.rotate(by: .radians(time * (index == 0 ? 1.7 : -1.2) + Double(index)))
                        let bounds = CGRect(x: -side * 0.34, y: -side * 0.22, width: side * 0.68, height: side * 0.44)
                        ring.stroke(Path(ellipseIn: bounds), with: .conicGradient(Gradient(colors: [.clear, color.opacity(0.08), color.opacity(0.85), .white.opacity(0.7), .clear]), center: .zero, angle: .zero), lineWidth: max(0.7, side * 0.022))
                    }
                } else if state == .listening, moving {
                    for index in 0..<2 {
                        let phase = (time * 0.65 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                        let halo = radius + CGFloat(phase) * side * 0.29
                        context.stroke(circle(halo, at: center), with: .color(color.opacity((1 - phase) * 0.32)), lineWidth: max(0.65, side * 0.016))
                    }
                } else {
                    context.stroke(circle(side * 0.3, at: center), with: .color(color.opacity(0.12 + Double(breathe) * 0.025)), lineWidth: max(0.6, side * 0.012))
                }

                var glow = context
                glow.addFilter(.shadow(color: color.opacity(0.6), radius: side * 0.08))
                glow.fill(circle(radius, at: center), with: .radialGradient(Gradient(colors: [.white.opacity(0.98), color.opacity(0.95), color.opacity(0.65)]), center: CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.3), startRadius: 0, endRadius: radius * 1.7))
                for index in 0..<3 {
                    let speed = state == .working ? 1.6 : 0.35
                    let angle = time * speed + Double(index) * .pi * 2 / 3
                    let distance = side * (0.31 + audio * 0.07)
                    let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance * 0.72)
                    context.fill(circle(side * (index == 0 ? 0.027 : 0.018), at: point), with: .color(color.opacity(index == 0 ? 0.75 : 0.35)))
                }
            }
        }
        .drawingGroup()
        .accessibilityLabel(state == .working ? "Newt is working" : state == .listening ? "Newt is listening" : state == .attention ? "Newt needs attention" : "Newt is ready")
    }
}

struct ListeningRibbon: View {
    let level: Float
    let tint: Color
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated || reduceMotion)) { timeline in
            let time = animated && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate : 0
            let amount = animated && !reduceMotion ? Double(min(max(level, 0), 1)) : 0
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<17) { index in
                    let envelope = sin(Double(index + 1) / 18 * .pi)
                    let wave = 0.65 + 0.35 * sin(time * 5 + Double(index) * 0.6)
                    Capsule().fill(tint.opacity(0.35 + envelope * 0.65))
                        .frame(width: 2, height: 2 + envelope * wave * amount * 9)
                }
            }.frame(height: 11)
        }.animation(animated && !reduceMotion ? .easeOut(duration: 0.15) : nil, value: level)
    }
}
