import SwiftUI

/// The sheet's geometry, as measured from Arc's.
private enum Metrics {
    static let size = CGSize(width: 508, height: 440)
    static let headerHeight: CGFloat = 76
    static let footerHeight: CGFloat = 90
    static let newRouteWidth: CGFloat = 94
    /// Where the routes and the Default row start, from the sheet's padded edge.
    static let routesInset: CGFloat = 31
    static let defaultInset: CGFloat = 36
    static let defaultLabelWidth: CGFloat = 104
    /// A route's columns: "URL", the match menu, the text; and its second line under the menu.
    static let urlLabelWidth: CGFloat = 49
    static let matchWidth: CGFloat = 110
    static let textWidth: CGFloat = 210
    static let openInInset: CGFloat = 74
    static let openInLabelWidth: CGFloat = 70
    static let destinationWidth: CGFloat = 165
    static let emptyTextWidth: CGFloat = 300
}

/// Arc's Air Traffic Control sheet (Settings ▸ Links, Arc 1.170), measured from window
/// captures and the accessibility tree: title and "New Route" over a hairline, one
/// two-line route per entry ("🔗 URL [Contains ⌃⌄] [text] ⊖" / "↳ Open in [Space ⌃⌄]",
/// 52 pt tall on a 76 pt pitch), then "Default" below a second hairline.
struct AirTrafficControlView: View {
    @Environment(SidebarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedRoute: UUID?

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Air Traffic Control").font(Design.Font.ui(.body, .bold))
                Spacer(minLength: Design.Space.m)
                Button { addRoute() } label: { Text("New Route").frame(width: Metrics.newRouteWidth) }
                    .controlSize(.regular)
                    .buttonBorderShape(.roundedRectangle(radius: Design.Radius.inset))
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: Design.Icon.bar, weight: .light))
                        .frame(width: Design.Space.controlLarge, height: Design.Space.controlLarge).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close")
                .keyboardShortcut(.cancelAction)
                .padding(.leading, Design.Space.xxxl)
            }
            .frame(height: Metrics.headerHeight)
            .padding(.top, Design.Space.m)
            SettingsCardDivider(inset: 0)
            routes
            SettingsCardDivider(inset: 0)
            HStack(spacing: 0) {
                Text("Default").font(Design.Font.body)
                    .frame(width: Metrics.defaultLabelWidth, alignment: .leading)
                destinationPicker($store.settings.defaultLinkDestination)
                Spacer(minLength: 0)
            }
            .padding(.leading, Metrics.defaultInset)
            .frame(height: Metrics.footerHeight)
        }
        .padding(.horizontal, Design.Space.xxxl)
        .frame(width: Metrics.size.width, height: Metrics.size.height)
        // Arc opens the sheet with nothing focused; AppKit would select the first route's text.
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
    }

    private var routes: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: Design.Space.xxxl) {
                    ForEach(store.settings.linkRoutes) { route in
                        routeRow(route.id).id(route.id)
                    }
                }
                .padding(.top, Design.Space.xxxl)
                .padding(.bottom, Design.Space.xl)
                .padding(.leading, Metrics.routesInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if store.settings.linkRoutes.isEmpty {
                    Text("Add a route to open matching links from other apps in a chosen space.")
                        .font(Design.Font.detail).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: Metrics.emptyTextWidth)
                }
            }
            .onChange(of: store.settings.linkRoutes.last?.id) { _, id in
                guard let id, focusedRoute == id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func routeRow(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            HStack(spacing: Design.Space.m) {
                Label("URL", systemImage: "link")
                    .labelStyle(RouteLabelStyle())
                    .frame(width: Metrics.urlLabelWidth, alignment: .leading)
                    .accessibilityLabel("Link URL")
                Picker("Match", selection: binding(id, \.match)) {
                    ForEach(LinkMatchStyle.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: Metrics.matchWidth)
                TextField("URL", text: binding(id, \.text), prompt: Text("nichebrowser.app"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedRoute, equals: id)
                    .frame(width: Metrics.textWidth)
                Button { removeRoute(id) } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: Design.Icon.regular))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.background, .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove")
            }
            HStack(spacing: Design.Space.m) {
                Label("Open in", systemImage: "arrow.turn.down.right")
                    .labelStyle(RouteLabelStyle())
                    .frame(width: Metrics.openInLabelWidth, alignment: .leading)
                destinationPicker(binding(id, \.destination))
            }
            .padding(.leading, Metrics.openInInset)
        }
    }

    /// Arc's destination menu: an "Open in Space" header over Most Recent Space and
    /// every space, then Little Arc after a separator.
    private func destinationPicker(_ selection: Binding<LinkDestination>) -> some View {
        let spaces = store.orderedSpaces
        // A route to a deleted space opens in the most recent one; show it that way.
        let shown = Binding<LinkDestination>(
            get: {
                if case .space(let sid) = selection.wrappedValue, !spaces.contains(where: { $0.id == sid }) { return .mostRecentSpace }
                return selection.wrappedValue
            },
            set: { selection.wrappedValue = $0 })
        return Picker("Open in", selection: shown) {
            Section("Open in Space") {
                Text("Most Recent Space").tag(LinkDestination.mostRecentSpace)
                ForEach(spaces) { space in
                    Text(space.labeled).tag(LinkDestination.space(space.id))
                }
            }
            Divider()
            Text("Little Window").tag(LinkDestination.littleWindow)
        }
        .labelsHidden()
        .frame(width: Metrics.destinationWidth)
    }

    private func binding<T>(_ id: UUID, _ key: WritableKeyPath<LinkRoute, T>) -> Binding<T> {
        Binding(
            get: { store.settings.linkRoutes.first { $0.id == id }.map { $0[keyPath: key] } ?? LinkRoute()[keyPath: key] },
            set: { value in
                guard let i = store.settings.linkRoutes.firstIndex(where: { $0.id == id }) else { return }
                store.settings.linkRoutes[i][keyPath: key] = value
            })
    }

    private func addRoute() {
        let route = LinkRoute()
        store.settings.linkRoutes.append(route)
        focusedRoute = route.id
    }

    private func removeRoute(_ id: UUID) {
        if focusedRoute == id { focusedRoute = nil }
        store.settings.linkRoutes.removeAll { $0.id == id }
    }
}

/// Secondary 13 pt label with its symbol in front ("🔗 URL", "↳ Open in").
private struct RouteLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Design.Space.s) {
            configuration.icon.font(.system(size: Design.Icon.small))
            configuration.title.font(Design.Font.body)
        }
        .foregroundStyle(.secondary)
    }
}
