import Foundation
import SwiftUI
import WebKit

/// A container: a separate "identity" for tabs, like Firefox's Multi-Account
/// Containers.
///
/// **Why:** each container keeps its own cookies, logins and site data. A
/// tab in Shopping can't see that you're signed in to Facebook in Personal,
/// so trackers can't follow you between them. You can also be signed in to
/// two accounts on the same site at once (your work Google in Work and your
/// own in Personal).
///
/// **How:** WebKit lets an app make extra, separate website data stores,
/// each with a fixed ID. Every container gets one, and its tabs use it.
struct TabContainer: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var color: GroupColor
    var icon: String

    static let defaults: [TabContainer] = [
        TabContainer(name: "Personal", color: .blue, icon: "person.fill"),
        TabContainer(name: "Work", color: .orange, icon: "briefcase.fill"),
        TabContainer(name: "Shopping", color: .pink, icon: "cart.fill"),
        TabContainer(name: "Banking", color: .green, icon: "building.columns.fill"),
    ]

    /// Icons you can pick for a container.
    static let icons = ["person.fill", "briefcase.fill", "cart.fill", "building.columns.fill",
                        "gamecontroller.fill", "heart.fill", "graduationcap.fill", "airplane",
                        "film.fill", "house.fill", "star.fill", "lock.fill"]
}

/// The two tabs side by side in split view.
struct SplitPair: Equatable {
    var left: UUID
    var right: UUID

    func contains(_ id: UUID?) -> Bool { id == left || id == right }

    /// The tab shown next to `id`.
    func partner(of id: UUID?) -> UUID? {
        id == left ? right : id == right ? left : nil
    }
}

extension BrowserStore {
    // MARK: Containers

    static let containersKey = "vela.containers"

    static func loadContainers() -> [TabContainer] {
        guard let data = UserDefaults.standard.data(forKey: containersKey),
              let saved = try? JSONDecoder().decode([TabContainer].self, from: data) else {
            return TabContainer.defaults
        }
        return saved
    }

    func saveContainers() {
        if let data = try? JSONEncoder().encode(containers) {
            UserDefaults.standard.set(data, forKey: Self.containersKey)
        }
    }

    func container(for tab: BrowserTab) -> TabContainer? {
        guard let id = tab.containerID else { return nil }
        return containers.first { $0.id == id }
    }

    /// The web view settings for a container's tabs: the same as normal tabs,
    /// but with the container's own cookie jar.
    func configuration(forContainer id: UUID?) -> WKWebViewConfiguration {
        guard let id, containers.contains(where: { $0.id == id }) else { return configuration }
        if let made = containerConfigurations[id] { return made }
        let made = configuration.copy() as! WKWebViewConfiguration
        made.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)
        containerConfigurations[id] = made
        return made
    }

    func addContainer(named name: String) {
        let used = Set(containers.map(\.color))
        let color = GroupColor.allCases.first { !used.contains($0) } ?? .purple
        containers.append(TabContainer(name: name, color: color, icon: "star.fill"))
        saveContainers()
    }

    func updateContainer(_ container: TabContainer) {
        guard let index = containers.firstIndex(where: { $0.id == container.id }) else { return }
        containers[index] = container
        saveContainers()
    }

    /// Deletes a container, its tabs, and everything its sites stored.
    func deleteContainer(_ container: TabContainer) {
        for tab in tabs where tab.containerID == container.id { close(tab) }
        containers.removeAll { $0.id == container.id }
        containerConfigurations[container.id] = nil
        saveContainers()
        Task { try? await WKWebsiteDataStore.remove(forIdentifier: container.id) }
    }

    /// Opens the same page again in another container (or none).
    func reopen(_ tab: BrowserTab, inContainer id: UUID?) {
        guard let url = tab.url else { return }
        newTab(url: url, opener: tab, container: id)
        close(tab)
    }

    // MARK: Split view

    /// Shows `other` next to the current tab. ⌥-click a tab, or right-click ▸ Open in Split View.
    func openSplitView(with other: BrowserTab) {
        guard let current = selectedTab, current.id != other.id else { return }
        other.wake()
        splitPair = SplitPair(left: current.id, right: other.id)
    }

    /// ••• ▸ Split View: puts a new tab next to the current one.
    func openSplitViewWithNewTab() {
        guard let current = selectedTab else { return }
        let other = newTab(opener: current, select: false, container: current.containerID)
        splitPair = SplitPair(left: current.id, right: other.id)
        selectedTabID = other.id
        addressBarFocusRequest += 1
    }

    func closeSplitView() {
        splitPair = nil
    }

    /// The tab in the pane you're not typing in.
    var splitPartner: BrowserTab? {
        guard let id = splitPair?.partner(of: selectedTabID) else { return nil }
        return tabs.first { $0.id == id }
    }
}

/// The little colored badge for a container (address bar, tab menu).
struct ContainerBadge: View {
    let container: TabContainer

    var body: some View {
        Label(container.name, systemImage: container.icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(container.color.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(container.color.color.opacity(0.18)))
    }
}

/// Settings ▸ General ▸ Containers.
struct ContainersSettingsSection: View {
    @Environment(BrowserStore.self) private var store
    @State private var newName = ""
    @State private var confirmDelete: TabContainer?

    var body: some View {
        Section {
            ForEach(store.containers) { container in
                HStack(spacing: 10) {
                    Menu {
                        ForEach(TabContainer.icons, id: \.self) { icon in
                            Button { var c = container; c.icon = icon; store.updateContainer(c) } label: {
                                Label(icon, systemImage: icon)
                            }
                        }
                    } label: {
                        Image(systemName: container.icon).foregroundStyle(container.color.color)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    TextField("Name", text: Binding(
                        get: { container.name },
                        set: { var c = container; c.name = $0; store.updateContainer(c) }
                    ))
                    .textFieldStyle(.plain)
                    Picker("Color", selection: Binding(
                        get: { container.color },
                        set: { var c = container; c.color = $0; store.updateContainer(c) }
                    )) {
                        ForEach(GroupColor.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    Button { confirmDelete = container } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Delete \(container.name) and everything its sites stored")
                }
            }
            HStack {
                TextField("New container name", text: $newName)
                Button("Add") {
                    store.addContainer(named: newName.trimmingCharacters(in: .whitespaces))
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Containers")
        } footer: {
            Text("Each container keeps its own cookies and logins, so sites in one can't see what you do in another. Open a tab in one from the + button's menu, or right-click a tab ▸ Reopen in Container.")
                .font(.system(size: 11.5))
                .foregroundStyle(Nightglass.mutedText)
        }
        .confirmationDialog(
            "Delete \(confirmDelete?.name ?? "this container")?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let confirmDelete { store.deleteContainer(confirmDelete) }
                confirmDelete = nil
            }
        } message: {
            Text("Its tabs close, and you're signed out of every site you used in it.")
        }
    }
}
