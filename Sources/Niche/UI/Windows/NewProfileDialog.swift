import AppKit
import SwiftUI

/// The colours of Arc's profile glyph and of the profile picker, shared by the profile dialogs.
enum ProfilePalette {
    /// The smiley: its ground, its ring, its eyes and smile.
    static let face = Color(hex: "#30305D")
    static let ring = Color(hex: "#6262A3")
    static let features = Color(hex: "#C4C4DC")
    /// The dashed ring around a profile that doesn't exist yet, and its plus badge.
    static let dashedRing = Color(hex: "#6262A3").opacity(0.45)
    static let badge = Color(hex: "#5DA642")
    /// The tile a space's icon sits on in Change Profile.
    static let tile = Color(hex: "#4049DC")
    /// The pill that picks a profile, and what is written on it.
    static let pill = Color(hex: "#2E36E7")
    static let pillInk = Color(hex: "#BEC0F3")
}

private enum Metrics {
    /// The card's width, Arc's.
    static let width: CGFloat = 450
    /// The glyph: the dashed ring, the face inside it, the plus badge.
    static let avatar: CGFloat = 61
    static let face: CGFloat = 54
    static let badge: CGFloat = 17
}

/// Arc 1.171's "Create a new Profile" dialog (Set Profile ▸ New Profile…), as wide as Arc's in a 2x
/// capture (1 Nov): a 450 pt card centred on the window, which dims behind it. Next
/// goes on to "Which Spaces should use this Profile?" (3 Nov), with the space it was opened for
/// ticked; Create Profile makes the profile and moves the ticked spaces onto it.
struct NewProfileDialog: View {
    let spaces: [Space]
    let onCreate: (String, Set<UUID>) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var ticked: Set<UUID>
    @State private var choosingSpaces = false
    @FocusState private var focused: Bool

    static let card = DialogTheme.card
    static let body = DialogTheme.body
    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    init(spaces: [Space], ticked: Set<UUID>, onCreate: @escaping (String, Set<UUID>) -> Void, onCancel: @escaping () -> Void) {
        self.spaces = spaces
        self.onCreate = onCreate
        self.onCancel = onCancel
        _ticked = State(initialValue: ticked)
    }

    var body: some View {
        if choosingSpaces {
            ProfileSpacesStep(spaces: spaces, ticked: $ticked, onBack: { choosingSpaces = false }) { onCreate(trimmed, ticked) }
        } else {
            nameStep
        }
    }

    private func next() {
        guard !trimmed.isEmpty else { return }
        if spaces.isEmpty { onCreate(trimmed, []) } else { choosingSpaces = true }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileAvatar()
            Text("Create a new Profile")
                .font(Design.Font.ui(.title, .semibold))
                .foregroundStyle(DialogTheme.title)
                .padding(.top, Design.Space.xl)
            Text("Profiles make your Spaces truly separate — with their own history, saved passwords, extensions, and other browsing data. No more flipping between work and personal accounts!")
                .font(Design.Font.ui(.body))
                .lineSpacing(Design.Space.hair)
                .foregroundStyle(Self.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Design.Space.m)
            Text("What do you want to call this Profile?")
                .font(Design.Font.ui(.body))
                .foregroundStyle(Self.body)
                .padding(.top, Design.Space.xl)
            TextField("", text: $name, prompt: Text("Personal").foregroundStyle(DialogTheme.faint))
                .textFieldStyle(.plain)
                .font(Design.Font.ui(.body))
                .foregroundStyle(DialogTheme.title)
                .focused($focused)
                .onSubmit(next)
                .padding(.horizontal, Design.Space.m)
                .frame(height: Design.Space.control)
                .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(Design.panelDarkRaisedColor))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).strokeBorder(DialogTheme.outline, lineWidth: 1))
                .padding(.top, Design.Space.s)
            HStack(spacing: Design.Space.xs) {
                Image(systemName: "clock.arrow.2.circlepath").font(.system(size: Design.Icon.small, weight: .semibold))
                Text("Profiles are ") + Text("not synced").bold() + Text(" between computers.")
            }
            .font(Design.Font.ui(.caption))
            .foregroundStyle(DialogTheme.body)
            .padding(.top, Design.Space.xs)
            HStack(spacing: Design.Space.m) {
                Spacer()
                DialogButton(title: "Cancel", key: "ESC", enabled: true, primary: false, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                DialogButton(title: "Next", key: "↩", enabled: !trimmed.isEmpty, primary: true, action: next)
            }
            .padding(.top, Design.Space.xxxl)
        }
        .padding(Design.Space.xxxl)
        .frame(width: Metrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(DialogSurface())
        .onAppear { focused = true }
    }
}

/// Arc's profile glyph: a lavender smiley in a dashed ring with a green plus badge.
struct ProfileAvatar: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().strokeBorder(ProfilePalette.dashedRing, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: Metrics.avatar, height: Metrics.avatar)
                Circle().fill(ProfilePalette.face).frame(width: Metrics.face, height: Metrics.face)
                Circle().strokeBorder(ProfilePalette.ring, lineWidth: 3).frame(width: Metrics.face, height: Metrics.face)
                VStack(spacing: 7) {
                    HStack(spacing: 9) {
                        Capsule().fill(ProfilePalette.features).frame(width: 4.5, height: 13)
                        Capsule().fill(ProfilePalette.features).frame(width: 4.5, height: 13)
                    }
                    SmileArc().stroke(ProfilePalette.features, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .frame(width: 26, height: 6)
                }
                .offset(y: 1)
            }
            ZStack {
                Circle().fill(ProfilePalette.badge).frame(width: Metrics.badge, height: Metrics.badge)
                Image(systemName: "plus").font(Design.Font.ui(.micro, .heavy)).foregroundStyle(DialogTheme.title)
            }
            .overlay(Circle().strokeBorder(DialogTheme.card, lineWidth: 1.5))
            .offset(x: 1, y: 1)
        }
        .frame(width: Metrics.avatar, height: Metrics.avatar)
    }
}

struct SmileArc: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY + r.height))
        return p
    }
}
