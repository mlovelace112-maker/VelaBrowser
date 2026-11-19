import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Bookmarks-style list of your saved passwords (⌥⌘P). Locked until you use
/// Touch ID or your Mac password, and locked again when it closes.
struct PasswordsView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var revealed: [String: String] = [:]
    @State private var isAdding = false
    @State private var unlockFailed = false
    @State private var isChecking = false
    @State private var importMessage: String?

    var body: some View {
        let vault = store.passwordVault

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Passwords")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
                if vault.isUnlocked {
                    Button { importFromPasswordsApp() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                        .help("Import passwords exported from the Passwords app, Chrome or Firefox")
                    Button { isChecking = true } label: { Label("Check", systemImage: "checkmark.shield") }
                        .help("Find weak, reused and breached passwords")
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
        .sheet(isPresented: $isChecking) { PasswordCheckView() }
        .alert("Import passwords", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    /// Passwords app ▸ File ▸ Export All Passwords… makes a .csv file. This
    /// picks it, imports it, and then destroys the file.
    private func importFromPasswordsApp() {
        let panel = NSOpenPanel()
        panel.title = "Import Passwords"
        panel.message = "Choose the file you exported from the Passwords app (File ▸ Export All Passwords…), Chrome or Firefox. Vela deletes it after importing."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try PasswordImporter.importFile(url, into: store.passwordVault)
            PasswordImporter.destroy(url)
            var message = "Imported \(result.imported) \(result.imported == 1 ? "login" : "logins")."
            if result.codes > 0 { message += " \(result.codes) of them came with 2FA codes." }
            if result.skipped > 0 { message += " Skipped \(result.skipped) without a website or password." }
            message += " The exported file was erased and deleted."
            importMessage = message
        } catch {
            importMessage = error.localizedDescription + " The file was left where it was."
        }
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
    @State private var isAddingCode = false
    @State private var confirmRemoveCode = false

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
            if store.passwordVault.hasCode(entry), let generator = store.passwordVault.oneTimeCode(for: entry) {
                Button {
                    PasswordVault.copyToClipboard(generator.code())
                } label: {
                    OneTimeCodeLabel(generator: generator)
                }
                .buttonStyle(.plain)
                .help("Copy the 2FA code")
                .contextMenu {
                    Button("Remove 2FA Code…", role: .destructive) { confirmRemoveCode = true }
                }
            } else {
                Button { isAddingCode = true } label: {
                    Image(systemName: "123.rectangle")
                }
                .buttonStyle(IconButtonStyle(size: 26))
                .help("Add a 2FA code (the setup key from the website)")
            }
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
        .confirmationDialog("Remove the 2FA code for \(entry.server)?", isPresented: $confirmRemoveCode) {
            Button("Remove", role: .destructive) { store.passwordVault.removeCode(for: entry) }
        } message: {
            Text("Make sure you can still sign in another way (an authenticator app or backup codes) first.")
        }
        .sheet(isPresented: $isAddingCode) { AddOneTimeCodeView(entry: entry) }
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

/// Passwords ▸ Check: weak, reused and breached passwords.
private struct PasswordCheckView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var includeBreaches = true
    @State private var issues: [PasswordIssue]?
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Password Check")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Toggle(isOn: $includeBreaches) {
                Text("Also check known data breaches")
                Text("Sends only the first 5 characters of a scrambled code of each password to Have I Been Pwned. Your passwords never leave your Mac.")
            }
            .toggleStyle(.switch)
            .tint(Nightglass.accent)

            Button(isRunning ? "Checking…" : "Check My Passwords") {
                isRunning = true
                Task {
                    issues = await PasswordHealth.check(store.passwordVault, includeBreaches: includeBreaches)
                    isRunning = false
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Nightglass.accent)
            .disabled(isRunning)

            if let issues {
                if issues.isEmpty {
                    Label("No problems found. Nice work.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Nightglass.safe)
                } else {
                    Text("\(issues.count) \(issues.count == 1 ? "login needs" : "logins need") attention. Change these passwords on their websites, then save the new ones.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Nightglass.mutedText)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(issues) { issue in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(issue.entry.server).font(.system(size: 13, weight: .semibold))
                                    if !issue.entry.account.isEmpty {
                                        Text(issue.entry.account)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Nightglass.secondaryText)
                                    }
                                    HStack(spacing: 6) {
                                        ForEach(issue.kinds, id: \.self) { kind in
                                            Text(kind.rawValue)
                                                .font(.system(size: 11, weight: .medium))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill((kind == .breached ? Nightglass.danger : Nightglass.caution).opacity(0.2)))
                                                .foregroundStyle(kind == .breached ? Nightglass.danger : Nightglass.caution)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 520, height: 480)
        .background(Nightglass.background)
    }
}
