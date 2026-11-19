import SwiftUI

/// A named, colored set of tabs that can be collapsed into a single chip.
struct TabGroup: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var color: GroupColor
    var isCollapsed = false
}

enum GroupColor: String, CaseIterable, Codable {
    case blue, green, purple, orange, yellow, pink

    var color: Color {
        switch self {
        case .blue: Color(hex: 0x5B9CFF)
        case .green: Color(hex: 0x4FD1A5)
        case .purple: Color(hex: 0xA99BFF)
        case .orange: Color(hex: 0xE8875F)
        case .yellow: Color(hex: 0xF2C14E)
        case .pink: Color(hex: 0xF07FB4)
        }
    }

    var name: String { rawValue.capitalized }
}

/// What the tab strip shows, in order: group chips and individual tabs.
enum StripItem: Identifiable {
    case group(TabGroup)
    case tab(BrowserTab)

    var id: UUID {
        switch self {
        case .group(let group): group.id
        case .tab(let tab): tab.id
        }
    }
}
