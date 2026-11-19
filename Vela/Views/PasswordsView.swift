import SwiftUI

/// Bookmarks-style list of your saved passwords (⌥⌘P). Locked until you use
/// Touch ID or your Mac password, and locked again when it closes.
struct PasswordsView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var revealed: [String: String] = [:]
    @State private var isAdding = false
    @State private var unlockFailed = false

    var body: some View {
        let vault = store.passwordVault

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Passwords")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
                if vault.isUnlocked {
                    Button { isAdding = true } label: { Label("Add", systemImage: "plus") }
                    Button {
                        revealed = [:]
                        vault.lock()
                    } label: { Label("Lock", systemImage: "lock") }
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            if vault.isUnlocked {
                unlockedList(vault)
            } else {
                lockedView(vault)
            }

            GeneratorRow()
            PasskeyNote()
        }
        .padding(22)
        .frame(width: 640, height: 600)
        .background(Nightglass.background)
        .onAppear { vault.reload() }
        .onDisappear {
            revealed = [:]
            vault.lock()
        }
        .sheet(isPresented: $isAdding) { AddPasswordView() }
    }

    private func lockedView(_ vault: PasswordVault) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Nightglass.accent)
                .accessibilityHidden(true)
            Text("Your passwords are locked")
                .font(.system(size: 15, weight: .semibold))
            Text("\(vault.entries.count) saved \(vault.entries.count == 1 ? "login" : "logins")")
                .font(.system(size: 12.5))
                .foregroundStyle(Nightglass.mutedText)
            Button("Unlock with Touch ID or Password") {
                Task { unlockFailed = !(await vault.unlock(reason: "show your saved passwords")) }
            }
            .buttonStyle(.borderedProminent)
            .tint(Nightglass.accent)
            if unlockFailed {
                Text("Couldn't unlock. Try again.")
                    .font(.system(size: 12))
                    .foregroundStyle(Nightglass.danger)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unlockedList(_ vault: PasswordVault) -> some View {
        let shown = vault.entries.filter {
            search.isEmpty
                || $0.server.localizedCaseInsensitiveContains(search)
                || $0.account.localizedCaseInsensitiveContains(search)
        }

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Nightglass.mutedText)
                    .accessibilityHidden(true)
                TextField("Search passwords", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.35)))

            ScrollView {
                LazyVStack(spacing: 2) {
                    if shown.isEmpty {
                        Text(search.isEmpty ? "No saved passwords yet. Vela offers to save one when you sign in to a website." : "No matches.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Nightglass.mutedText)
                            .padding(30)
                    }
                    ForEach(shown) { entry in
                        PasswordRow(entry: entry, revealed: Binding(
                            get: { revealed[entry.id] },
                            set: { revealed[entry.id] = $0 }
                        ))
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct PasswordRow: View {
    @Environment(BrowserStore.self) private var store
    let entry: PasswordEntry
    @Binding var revealed: String?
    @State private var confirmDelete = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            FaviconView(url: URL(string: "https://\(entry.server)"), size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.server).font(.system(size: 13.5))
                Text(entry.account.isEmpty ? "No username" : entry.account)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Nightglass.mutedText)
                    .textSelection(.enabled)
            }
            Spacer()
            Text(revealed ?? "••••••••••")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Nightglass.secondaryText)
                .lineLimit(1)
                .textSelection(.enabled)
            Button {
                revealed = revealed == nil ? store.passwordVault.password(for: entry) : nil
            } label: {
                Image(systemName: revealed == nil ? "eye" : "eye.slash")
            }
            .buttonStyle(IconButtonStyle(size: 26))
            .help(revealed == nil ? "Show password" : "Hide password")

            Button {
                if let password = store.passwordVault.password(for: entry) {
                    PasswordVault.copyToClipboard(password)
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(IconButtonStyle(size: 26))
            .help("Copy password (cleared from the clipboard after 90 seconds)")

            Button { confirmDelete = true } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(IconButtonStyle(size: 26))
            .help("Delete")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(isHovering ? 0.05 : 0)))
        .onHover { isHovering = $0 }
        .confirmationDialog("Delete the password for \(entry.server)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.deletePassword(entry) }
        }
    }
}

/// A form for saving a login by hand.
private struct AddPasswordView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var website = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Password")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Form {
                TextField("Website", text: $website, prompt: Text("example.com"))
                TextField("Username", text: $username)
                HStack {
                    TextField("Password", text: $password)
                        .font(.system(size: 13, design: .monospaced))
                    Button("Generate") { password = PasswordGenerator.make() }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let host {
                        store.savePassword(server: host, account: username, password: password)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(host == nil || password.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    /// "https://www.example.com/login" or "example.com" → "example.com"
    private var host: String? {
        let text = website.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let withScheme = text.contains("://") ? text : "https://" + text
        guard let host = URL(string: withScheme)?.host(), host.contains(".") || host == "localhost" else { return nil }
        return PasswordVault.normalize(host)
    }
}

/// A strong random password you can copy, for signing up somewhere new.
private struct GeneratorRow: View {
    @State private var generated = PasswordGenerator.make()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(Nightglass.accent)
                .accessibilityHidden(true)
            Text(generated)
                .font(.system(size: 12.5, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button { generated = PasswordGenerator.make() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(IconButtonStyle(size: 26))
                .help("Make another")
            Button { PasswordVault.copyToClipboard(generated) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(IconButtonStyle(size: 26))
                .help("Copy")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

/// Why Vela can't use passkeys yet.
private struct PasskeyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.badge.key")
                .foregroundStyle(Nightglass.mutedText)
                .accessibilityHidden(true)
            Text("**Passkeys:** macOS only lets browsers that Apple has approved create or use passkeys. Until Vela has that approval, sites will offer a password or another way to sign in, and your existing passkeys stay in Apple's Passwords app.")
                .font(.system(size: 11.5))
                .foregroundStyle(Nightglass.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
