import AppKit
import SwiftUI
import WebKit

// MARK: - Focus mode screen

/// Shown instead of a site focus mode is blocking.
struct FocusBlockedView: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    let url: URL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 40))
                .foregroundStyle(Nightglass.accent)
            Text("Stay focused")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Nightglass.text)
            Text("\(BrowserStore.siteName(url)) is paused while focus mode is on.")
                .font(.system(size: 14))
                .foregroundStyle(Nightglass.secondaryText)
            if let status = store.focusStatus, status != "On", status != "Scheduled" {
                Text("\(status) left")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Nightglass.mutedText)
            }
            HStack(spacing: 12) {
                Button("Go Back") { store.leaveFocusScreen(in: tab, load: false) }
                    .keyboardShortcut(.defaultAction)
                Button("Take a 5-Minute Break") { store.takeFocusBreak(in: tab) }
            }
            .controlSize(.large)
            .padding(.top, 6)
            Button("Turn Off Focus Mode") { store.stopFocus() }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Nightglass.background)
    }
}

// MARK: - Toolbar items

/// The focus timer and the web panels button, next to Claude in the toolbar.
struct SiteToolbarItems: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        // Refreshes the "23m left" countdown twice a minute.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            if let status = store.focusStatus {
                Menu {
                    Button("Turn Off Focus Mode") { store.stopFocus() }
                    Button("Focus Settings…") { openSettings() }
                } label: {
                    Label(status, systemImage: "leaf.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Nightglass.accent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Nightglass.accent.opacity(0.16)))
                .help("Focus mode is on")
            }
        }

        Button { withAnimation(Nightglass.spring) { store.toggleWebPanels() } } label: {
            Image(systemName: "rectangle.righthalf.inset.filled")
                .foregroundStyle(store.isWebPanelVisible ? Nightglass.accent : Nightglass.secondaryText)
        }
        .buttonStyle(IconButtonStyle())
        .help("Web Panels: Calendar, Gmail and more (⌃⌘P)")
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Web panels

/// The right-hand panel with small versions of Calendar, Gmail and any
/// other sites you add.
struct WebPanelView: View {
    @Environment(BrowserStore.self) private var store
    @State private var isAdding = false
    @State private var newName = ""
    @State private var newAddress = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(store.webPanels) { panel in
                    Button { store.selectedPanelID = panel.id } label: {
                        Image(systemName: panel.icon)
                            .foregroundStyle(store.selectedPanel?.id == panel.id ? Nightglass.accent : Nightglass.secondaryText)
                    }
                    .buttonStyle(IconButtonStyle(size: 28))
                    .help(panel.name)
                    .contextMenu {
                        Button("Open in a Tab") { store.newTab(url: panel.url) }
                        Button("Remove \(panel.name)", role: .destructive) { store.removeWebPanel(panel) }
                    }
                }
                Button { isAdding = true } label: { Image(systemName: "plus") }
                    .buttonStyle(IconButtonStyle(size: 28))
                    .help("Add a site")
                    .popover(isPresented: $isAdding, arrowEdge: .bottom) { addForm }
                Spacer()
                if let panel = store.selectedPanel {
                    Button { store.webView(for: panel).reload() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(IconButtonStyle(size: 26))
                        .help("Reload")
                    Button { store.newTab(url: store.webView(for: panel).url ?? panel.url) } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(IconButtonStyle(size: 26))
                    .help("Open in a Tab")
                }
                Button { withAnimation(Nightglass.spring) { store.isWebPanelVisible = false } } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle(size: 26))
                .help("Close Web Panels (⌃⌘P)")
            }
            .padding(.horizontal, 8)
            .frame(height: 40)

            Rectangle().fill(Nightglass.stroke).frame(height: 1)

            if let panel = store.selectedPanel {
                WebViewContainer(webView: store.webView(for: panel))
                    .id(panel.id)
            } else {
                ContentUnavailableView("No panels", systemImage: "rectangle.righthalf.inset.filled",
                                       description: Text("Click + to add a site."))
            }
        }
        .frame(width: 390)
        .frame(maxHeight: .infinity)
        .clipped()
        .background(VisualEffectBackground())
        .overlay(alignment: .leading) {
            Rectangle().fill(Nightglass.stroke).frame(width: 1)
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a web panel").font(.system(size: 13, weight: .semibold))
            TextField("Name (like Messages)", text: $newName)
            TextField("Address (like messages.google.com)", text: $newAddress)
                .onSubmit(add)
            HStack {
                Spacer()
                Button("Cancel") { isAdding = false }
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(BrowserStore.url(from: newAddress) == nil || !newAddress.contains("."))
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(16)
        .frame(width: 300)
    }

    private func add() {
        guard newAddress.contains(".") else { return }
        store.addWebPanel(name: newName, address: newAddress)
        newName = ""
        newAddress = ""
        isAdding = false
    }
}

// MARK: - Settings

/// Settings ▸ Focus.
struct FocusSettingsTab: View {
    @Environment(BrowserStore.self) private var store
    @State private var newSite = ""

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                if store.isFocusActive {
                    HStack {
                        Label("Focus mode is on", systemImage: "leaf.fill").foregroundStyle(Nightglass.accent)
                        Spacer()
                        Button("Turn Off") { store.stopFocus() }
                    }
                } else {
                    HStack {
                        Text("Start a focus session")
                        Spacer()
                        Button("25 min") { store.startFocus(minutes: 25) }
                        Button("1 hour") { store.startFocus(minutes: 60) }
                        Button("Until I stop") { store.startFocus(minutes: nil) }
                    }
                }
            } footer: {
                Text("While focus mode is on, the sites below show a calm “Stay focused” screen instead. You can always take a 5-minute break.")
            }

            Section("Sites to block") {
                ForEach(store.focusSites, id: \.self) { site in
                    HStack {
                        FaviconView(url: URL(string: "https://\(site)"))
                        Text(site)
                        Spacer()
                        Button { store.focusSites.removeAll { $0 == site } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove")
                    }
                }
                HStack {
                    TextField("Add a site, like reddit.com", text: $newSite)
                        .onSubmit(addSite)
                    Button("Add", action: addSite).disabled(!newSite.contains("."))
                }
            }

            Section {
                Toggle("Turn on focus mode automatically", isOn: $store.focusSchedule.isEnabled)
                if store.focusSchedule.isEnabled {
                    DatePicker("From", selection: minutes($store.focusSchedule.start), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minutes($store.focusSchedule.end), displayedComponents: .hourAndMinute)
                    Toggle("Weekdays only", isOn: $store.focusSchedule.weekdaysOnly)
                }
            } header: {
                Text("Focus hours")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .tint(Nightglass.accent)
    }

    private func addSite() {
        var site = newSite.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: site.contains("://") ? site : "https://\(site)"), let host = url.host() {
            site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        guard site.contains("."), !store.focusSites.contains(site) else { return }
        store.focusSites.append(site)
        newSite = ""
    }

    /// Shows "minutes after midnight" as a time of day in the picker.
    private func minutes(_ value: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(value.wrappedValue) * 60)
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            value.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

/// Settings ▸ Appearance ▸ Websites.
struct DarkModeSettingsSection: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        @Bindable var store = store

        Section {
            Toggle(isOn: $store.darkModeEverywhere) {
                Text("Dark mode for every website")
                Text("Bright sites turn dark to match Vela. Photos and videos keep their colors. Turn it off for one site with View ▸ Dark Mode for This Site.")
            }
            if !store.darkModeOffSites.isEmpty {
                ForEach(store.darkModeOffSites.sorted(), id: \.self) { site in
                    HStack {
                        Text("Off for \(site)").foregroundStyle(Nightglass.secondaryText)
                        Spacer()
                        Button("Turn Back On") { store.darkModeOffSites.remove(site) }
                            .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Websites")
        }
        .toggleStyle(.switch)
        .tint(Nightglass.accent)
    }
}
