import SwiftUI
import Newtv1Core

enum WorkspaceTheme {
    static let background = Color(red: 0.065, green: 0.073, blue: 0.080)
    static let sidebar = Color(red: 0.080, green: 0.089, blue: 0.097)
    static let card = Color(red: 0.100, green: 0.112, blue: 0.122)
    static let raised = Color(red: 0.130, green: 0.145, blue: 0.156)
    static let accent = Color(red: 0.72, green: 0.89, blue: 0.80)
    static let text = Color(red: 0.93, green: 0.94, blue: 0.94)
    static let secondary = Color(red: 0.64, green: 0.68, blue: 0.70)
    static let line = Color.white.opacity(0.075)
}

struct WorkspaceButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 15).padding(.vertical, 10)
            .foregroundStyle(primary ? WorkspaceTheme.background : WorkspaceTheme.text)
            .background(primary ? WorkspaceTheme.accent : WorkspaceTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(primary ? Color.clear : WorkspaceTheme.line))
            .opacity(enabled ? configuration.isPressed ? 0.75 : 1 : 0.38)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct WorkspaceFieldStyle: TextFieldStyle {
    @FocusState private var focused: Bool
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.font(.system(size: 13)).textFieldStyle(.plain).focused($focused)
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(WorkspaceTheme.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? WorkspaceTheme.accent.opacity(0.65) : WorkspaceTheme.line))
    }
}

struct WorkspaceToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 20) {
            configuration.label.frame(maxWidth: .infinity, alignment: .leading).accessibilityHidden(true)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
        }.padding(.vertical, 3)
    }
}

struct WorkspaceHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.8).foregroundStyle(WorkspaceTheme.text)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(WorkspaceTheme.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WorkspaceTabs: View {
    let items: [String]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                Button { selection = item } label: {
                    Text(item).font(.system(size: 12, weight: selection == item ? .semibold : .medium))
                        .foregroundStyle(selection == item ? WorkspaceTheme.text : WorkspaceTheme.secondary)
                        .padding(.horizontal, 15).padding(.vertical, 10)
                        .background(selection == item ? WorkspaceTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).accessibilityAddTraits(selection == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }.padding(5).background(WorkspaceTheme.card, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct WorkspaceEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 24, weight: .light)).foregroundStyle(WorkspaceTheme.accent)
                .frame(width: 60, height: 60).background(WorkspaceTheme.accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
            Text(title).font(.system(size: 16, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary).multilineTextAlignment(.center).frame(maxWidth: 370).lineSpacing(4)
        }.padding(32).frame(maxWidth: .infinity).workspaceCard()
    }
}

extension View {
    func workspaceCard() -> some View {
        background(WorkspaceTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(WorkspaceTheme.line))
    }
}

extension AppPage {
    var workspaceTitle: String {
        switch self {
        case .control: return "Mac control"
        case .brain: return "Answers"
        case .companion: return "Newt"
        case .guide: return "Command library"
        default: return rawValue
        }
    }
    var workspaceGroup: String {
        switch self {
        case .companion, .control, .brain, .jobs: return "Workspace"
        case .system, .browser, .connections, .diagrams, .utilities: return "Tools"
        case .notch, .workflows, .routines: return "Personalize"
        case .guide, .settings: return "App"
        }
    }
}
