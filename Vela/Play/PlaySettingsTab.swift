import SwiftUI

/// Settings ▸ Play: the main switch for Vela's playful side, and a switch for
/// each part of it.
struct PlaySettingsTab: View {
    @State private var confirmReset = false

    var body: some View {
        @Bindable var play = Play.shared

        Form {
            Section {
                Toggle(isOn: $play.settings.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Playful Vela")
                        Text("Points, levels, streaks, badges, challenges, Pip and confetti. Turning it off hides all of it and stops counting; your progress is kept.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Pieces") {
                Toggle("Show Pip in the toolbar", isOn: $play.settings.showPet)
                Toggle("Pip's speech bubbles", isOn: $play.settings.petBubbles)
                    .disabled(!play.settings.showPet)
                Toggle("Confetti for badges and level-ups", isOn: $play.settings.confetti)
                Toggle("Sounds", isOn: $play.settings.sounds)
                Toggle("Star Catcher game when you're offline", isOn: $play.settings.offlineGame)
                Toggle("Color Vela with the album playing on Spotify", isOn: $play.settings.moodTheming)
            }
            .disabled(!play.settings.isEnabled)

            Section("Your progress") {
                LabeledContent("Level", value: "\(play.level) · \(play.levelTitle)")
                LabeledContent("Points", value: play.state.xp.formatted())
                LabeledContent("Streak", value: "\(play.currentStreak) days (best \(play.state.bestStreak))")
                LabeledContent("Badges", value: "\(play.earnedBadges.count) of \(Badge.all.count)")
                Text("Kept only on this Mac, in ~/Library/Application Support/Vela/play.json. Private tabs never count.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Start Over…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .tint(Nightglass.accent)
        .confirmationDialog("Start over from level 1?", isPresented: $confirmReset) {
            Button("Erase My Progress", role: .destructive) { play.resetProgress() }
        } message: {
            Text("Your points, badges, streak, focus planet and bingo card will be erased. This can't be undone.")
        }
    }
}
