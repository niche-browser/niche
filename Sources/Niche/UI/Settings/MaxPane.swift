import AppKit
import SwiftUI

/// Intelligence: one card, a row per feature with a picture, its name, what it does and a switch,
/// and a line under the card about where the data goes. The features run on the Mac's own Apple
/// Intelligence model, so that line says nothing leaves the Mac, or, while Apple Intelligence
/// can't run, why and how to turn it on.
struct MaxPane: View {
    @Environment(SidebarStore.self) private var store
    private var service: TidyTabsService { TidyTabsService.shared }

    var body: some View {
        @Bindable var store = store
        let available = service.status == .available
        SettingsCardPane {
            SettingsHeader("Features")
            SettingsCard {
                MaxFeatureRow(title: "Tidy Tabs", isOn: $store.settings.tidyTabs, enabled: available) {
                    TidyTabsPicture()
                } description: {
                    Text("Press \(Image(nsImage: BroomGlyph.image).renderingMode(.template)) to let the sidebar sort itself once you have six or more tabs today.")
                }
                SettingsCardDivider(inset: 124)
                MaxFeatureRow(title: "Tidy Tab Titles", isOn: $store.settings.tidyTabTitles, enabled: available) {
                    TidyTabTitlesPicture()
                } description: {
                    Text("Pinned tabs get shorter, tidier titles.")
                }
                SettingsCardDivider(inset: 124)
                MaxFeatureRow(title: "Tidy Downloads", isOn: $store.settings.tidyDownloads, enabled: available) {
                    TidyDownloadsPicture()
                } description: {
                    Text("Downloads get clear names, so they’re easier to find later.")
                }
            }
            MaxFooter(status: service.status) { service.openSystemSettings() }
                .padding(.top, 10)
        }
        // Coming back from System Settings brings Niche to the front, which reads the status again;
        // a model still downloading gets there without that.
        .task {
            while !Task.isCancelled {
                service.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

/// One feature: picture, name over description, switch. Off while Apple Intelligence can't run.
struct MaxFeatureRow<Picture: View, Description: View>: View {
    let title: String
    @Binding var isOn: Bool
    var enabled = true
    @ViewBuilder let picture: Picture
    @ViewBuilder let description: Description

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            MaxPictureFrame { picture }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Design.Font.body)
                description
                    .font(Design.Font.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            SettingsSwitch(title: title, isOn: Binding(get: { isOn && enabled }, set: { isOn = $0 }))
                .disabled(!enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

/// Each picture on a rounded tile with a hairline edge.
private struct MaxPictureFrame<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(width: 88, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Design.hairline))
            .accessibilityHidden(true)
    }
}

/// Under the card: what runs where, or why it can't and the way to System Settings ▸ Apple
/// Intelligence & Siri.
private struct MaxFooter: View {
    let status: TidyTabsService.Status
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(status.explanation)
                .font(Design.Font.detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if status.canOpenSettings {
                Button("Turn on Apple Intelligence in System Settings", action: openSettings)
                    .buttonStyle(.link)
                    .font(Design.Font.detail)
            }
        }
        .padding(.horizontal, Design.Space.rowInset)
    }
}

/// Tidy Downloads' picture: the "Download renamed to:" card on blue.
private struct TidyDownloadsPicture: View {
    private let grey = Color(white: 0.55)
    var body: some View {
        ZStack {
            Color(red: 0.16, green: 0.20, blue: 0.93)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text("Download renamed to:").font(.system(size: 4)).foregroundStyle(grey).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 4.5, weight: .semibold)).foregroundStyle(grey)
                    Image(systemName: "xmark").font(.system(size: 4.5, weight: .semibold)).foregroundStyle(grey)
                }
                Text("Navan Itinerary.pdf").font(.system(size: 6, weight: .medium)).foregroundStyle(.black).lineLimit(1).fixedSize()
                Text("387494875.pdf").font(.system(size: 4.5)).strikethrough().foregroundStyle(grey).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 5).padding(.vertical, 4)
            .frame(width: 70)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white))
        }
    }
}

/// Tidy Tab Titles' picture: a renamed tab, "Double-click to rename" under it, sparkles round it,
/// on mauve.
private struct TidyTabTitlesPicture: View {
    private let ink = Color(red: 0.42, green: 0.27, blue: 0.62)
    var body: some View {
        ZStack {
            Color(red: 0.61, green: 0.48, blue: 0.62)
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 0.32, green: 0.12, blue: 0.36))
                    .frame(width: 8, height: 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Interior Design Book").font(.system(size: 6, weight: .medium)).foregroundStyle(ink)
                        .lineLimit(1).fixedSize()
                    Text("Double-click to rename").font(.system(size: 4.5)).foregroundStyle(ink.opacity(0.8))
                        .lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, 5).padding(.vertical, 2.5)
            .background(Capsule().fill(Color.white))
            ForEach(0..<9, id: \.self) { i in
                Circle().fill(Color.white.opacity(i % 2 == 0 ? 0.9 : 0.6))
                    .frame(width: i % 3 == 0 ? 1.6 : 1.1, height: i % 3 == 0 ? 1.6 : 1.1)
                    .offset(x: [-33, -20, -6, 9, 22, 34, -26, 15, 30][i], y: [-12, 13, -14, 12, -13, 10, 9, -11, -6][i])
            }
        }
    }
}

/// Tidy Tabs' picture: the squiggle, the broom and a ✕ on lavender.
private struct TidyTabsPicture: View {
    private let ink = Color(red: 0.55, green: 0.52, blue: 0.72)
    var body: some View {
        ZStack {
            Color(red: 0.84, green: 0.82, blue: 0.96)
            HStack(spacing: 5) {
                Squiggle()
                    .stroke(Color(red: 0.70, green: 0.67, blue: 0.90), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                    .frame(width: 40, height: 5)
                Image(nsImage: BroomGlyph.image).renderingMode(.template).foregroundStyle(ink)
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(ink)
            }
            .offset(x: -2)
        }
    }
}

private struct Squiggle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let period: CGFloat = 9
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        var x: CGFloat = 0
        while x <= r.width {
            p.addLine(to: CGPoint(x: r.minX + x, y: r.midY + r.height / 2 * sin(2 * .pi * x / period)))
            x += 0.5
        }
        return p
    }
}
