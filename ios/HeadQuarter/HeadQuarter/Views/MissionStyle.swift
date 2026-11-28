import SwiftUI

struct MissionTheme {
    let name: String
    var isDark: Bool { ["hq", "logbook", "ykf"].contains(name) }
    var ink: Color { isDark ? .white : Color(red: 0.06, green: 0.13, blue: 0.23) }
    var secondary: Color { ink.opacity(0.65) }
    var accent: Color {
        switch name {
        case "stack": return Color(red: 0.50, green: 0.32, blue: 0.08)
        case "crew": return Color(red: 0.57, green: 0.16, blue: 0.44)
        case "logbook": return Color(red: 0.72, green: 0.79, blue: 0.86)
        default: return isDark ? .cyan : Color(red: 0.08, green: 0.33, blue: 0.74)
        }
    }
    var background: Color {
        switch name {
        case "briefing": return Color(red: 0.81, green: 0.89, blue: 1)
        case "stack": return Color(red: 0.96, green: 0.91, blue: 0.81)
        case "crew": return Color(red: 0.98, green: 0.94, blue: 0.88)
        case "stocked": return Color(red: 0.84, green: 0.89, blue: 0.94)
        case "logbook": return Color(red: 0.045, green: 0.055, blue: 0.07)
        default: return Color(red: 0.015, green: 0.055, blue: 0.105)
        }
    }
    var surface: Color { isDark ? .white.opacity(0.065) : .white.opacity(0.48) }
    var border: Color { isDark ? .cyan.opacity(0.21) : .white.opacity(0.85) }
}

struct MissionBackground: View {
    var theme: MissionTheme
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.background
                if theme.name == "hq" || theme.name == "ykf" {
                    Image("MissionMountains").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped().opacity(0.11)
                }
                LinearGradient(colors: [theme.accent.opacity(0.16), .clear, theme.background.opacity(0.8)],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                if theme.name == "briefing" || theme.name == "stocked" || theme.name == "stack" {
                    MissionWave().fill(theme.accent.opacity(0.12))
                    MissionWave().stroke(.white.opacity(0.45), lineWidth: 1)
                }
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct MissionWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.28))
        path.addCurve(to: CGPoint(x: rect.width, y: rect.height * 0.04),
                      control1: CGPoint(x: rect.width * 0.7, y: rect.height * 0.3),
                      control2: CGPoint(x: rect.width * 0.45, y: rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.19))
        path.addCurve(to: CGPoint(x: 0, y: rect.height * 0.44),
                      control1: CGPoint(x: rect.width * 0.5, y: rect.height * 0.23),
                      control2: CGPoint(x: rect.width * 0.8, y: rect.height * 0.36))
        path.closeSubpath()
        return path
    }
}

struct GlassPanel<Content: View>: View {
    var theme: MissionTheme
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(theme.border, lineWidth: 0.8))
            .shadow(color: theme.accent.opacity(0.06), radius: 12, y: 5)
    }
}

extension ConnectionState {
    var color: Color {
        switch self {
        case .healthy: return Color(red: 0.08, green: 0.62, blue: 0.34)
        case .degraded: return .orange
        case .failed: return .red
        case .missing: return Color(red: 0.48, green: 0.55, blue: 0.64)
        case .unknown: return Color(red: 0.48, green: 0.55, blue: 0.64)
        case .disabled: return .gray
        }
    }
}

struct ConnectionBadge: View {
    let state: ConnectionState
    var body: some View {
        Label(state.title, systemImage: state.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(state.color)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(state.color.opacity(0.13), in: Capsule())
            .fixedSize()
    }
}

struct SystemArtwork: View {
    let system: SystemDefinition
    var size: CGFloat = 56
    var body: some View {
        Image(system.asset).resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23))
            .overlay(RoundedRectangle(cornerRadius: size * 0.23).stroke(.white.opacity(0.24)))
            .accessibilityHidden(true)
    }
}
