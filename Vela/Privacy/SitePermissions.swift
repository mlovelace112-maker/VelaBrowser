import Foundation

/// Something a website can ask to use.
enum PermissionKind: String, CaseIterable, Identifiable {
    case camera
    case microphone

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .camera: "video.fill"
        case .microphone: "mic.fill"
        }
    }

    /// "www.zoom.us" → "zoom.us", so one answer covers the whole site.
    static func siteName(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// "zoom.us wants to use your camera and microphone", waiting for an answer.
struct PermissionRequest: Identifiable, Equatable {
    let id = UUID()
    let site: String
    let kinds: [PermissionKind]
    /// Tells WebKit the answer. Call it exactly once.
    let answer: @MainActor (Bool) -> Void

    static func == (a: PermissionRequest, b: PermissionRequest) -> Bool { a.id == b.id }

    /// "camera and microphone"
    var description: String {
        kinds.map { $0.title.lowercased() }.joined(separator: " and ")
    }
}

extension PrivacySettings {
    /// Your remembered answer for a site: true (allowed), false (blocked) or nil (ask).
    func permission(_ kind: PermissionKind, for site: String) -> Bool? {
        switch kind {
        case .camera: cameraSites[site]
        case .microphone: microphoneSites[site]
        }
    }

    /// Remembers an answer, or forgets it with nil (Vela asks again next time).
    mutating func setPermission(_ kind: PermissionKind, _ allowed: Bool?, for site: String) {
        switch kind {
        case .camera: cameraSites[site] = allowed
        case .microphone: microphoneSites[site] = allowed
        }
    }

    /// Every site you've made a choice for, for the Site Settings page.
    var customizedSites: [String] {
        var sites = Set<String>()
        sites.formUnion(cameraSites.keys)
        sites.formUnion(microphoneSites.keys)
        sites.formUnion(popupAllowedSites)
        sites.formUnion(siteScriptLevels.keys)
        sites.formUnion(shieldsDownSites)
        sites.formUnion(signInSites)
        sites.formUnion(httpAllowedSites)
        sites.formUnion(keptSites)
        sites.formUnion(neverSavePasswordSites)
        return sites.sorted()
    }

    /// Clears every per-site choice for one site.
    mutating func forget(site: String) {
        cameraSites[site] = nil
        microphoneSites[site] = nil
        popupAllowedSites.remove(site)
        siteScriptLevels[site] = nil
        shieldsDownSites.remove(site)
        signInSites.remove(site)
        httpAllowedSites.remove(site)
        keptSites.remove(site)
        neverSavePasswordSites.remove(site)
    }
}
