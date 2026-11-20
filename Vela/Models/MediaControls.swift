import Foundation
import WebKit

/// Video and audio controls: speed, skip and mute for any player on any site.
///
/// **How it works:** a small script runs in every page (and in embedded
/// players like a YouTube video inside a news article). It tells Vela when
/// something starts or stops playing with sound, which lights up the speaker
/// on the tab. When you change the speed or mute a tab, Vela asks that script
/// to set every `<video>` and `<audio>` on the page. The script runs in Vela's
/// own private space, so pages can't see it or undo it.
enum MediaControls {
    /// The speeds View ▸ Video ▸ Faster and Slower step through.
    static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    static func script() -> WKUserScript {
        let source = """
        (() => {
          if (window.__velaMedia) return;
          let rate = 1, muted = false, lastAudible = null;
          const players = () => Array.from(document.querySelectorAll('video, audio'));
          const post = (message) => {
            try { window.webkit.messageHandlers.\(ContentBlocker.clientMessageName).postMessage(message); } catch (e) {}
          };
          const isAudible = () => players().some((m) => !m.paused && !m.ended && !m.muted && m.volume > 0);
          const report = () => {
            const now = isAudible();
            if (now === lastAudible) return;
            lastAudible = now;
            post({ type: 'media', audible: now });
          };
          // New videos (the next one in a playlist) get this tab's speed and mute.
          const adjust = (m) => {
            if (rate !== 1 && m.playbackRate !== rate) m.playbackRate = rate;
            if (muted && !m.muted) m.muted = true;
          };
          ['play', 'playing', 'pause', 'ended', 'volumechange', 'loadedmetadata', 'emptied'].forEach((name) => {
            document.addEventListener(name, (event) => {
              const m = event.target;
              if (m instanceof HTMLMediaElement && (name === 'play' || name === 'loadedmetadata')) adjust(m);
              report();
            }, true);
          });
          window.__velaMedia = {
            apply(newRate, newMuted) {
              const unmute = muted && !newMuted;
              rate = newRate;
              muted = newMuted;
              players().forEach((m) => {
                m.playbackRate = newRate;
                if (newMuted) m.muted = true;
                else if (unmute) m.muted = false;
              });
              report();
            },
            skip(seconds) {
              const list = players();
              const m = list.find((p) => !p.paused) || list.find((p) => p.currentTime > 0) || list[0];
              if (!m) return false;
              m.currentTime = Math.max(0, Math.min(m.currentTime + seconds, m.duration || Infinity));
              return true;
            },
          };
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient)
    }
}

extension BrowserTab {
    /// The media script saw something start or stop playing with sound.
    func mediaChanged(isAudible: Bool, in frame: WKFrameInfo) {
        let key = "\(frame.isMainFrame ? "main" : "frame")|\(frame.securityOrigin.protocol)://\(frame.securityOrigin.host):\(frame.securityOrigin.port)"
        let isNew = mediaFrames[key] == nil
        if isNew, mediaFrames.count < 20 { mediaFrames[key] = frame }
        // A player that just showed up gets this tab's speed and mute.
        if isNew, playbackRate != 1 || isMuted { applyMediaSettings(in: frame) }
        if isAudible {
            isPlayingAudio = true
        } else {
            // Another player on the page may still be playing: ask WebKit.
            Task { [weak self] in
                guard let self else { return }
                let state = await self.webView.requestMediaPlaybackState()
                self.isPlayingAudio = state == .playing && !self.isMuted
            }
        }
    }

    /// The speaker button on the tab.
    func toggleMute() {
        isMuted.toggle()
        applyMediaSettingsEverywhere()
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = min(max(rate, 0.25), 4)
        applyMediaSettingsEverywhere()
    }

    /// Jumps the playing video forward (or back, with a negative number).
    func skipMedia(by seconds: Double) {
        let frames: [WKFrameInfo?] = [nil] + mediaFrames.values.filter { !$0.isMainFrame }.map { Optional($0) }
        for frame in frames {
            webView.callAsyncJavaScript(
                "return window.__velaMedia ? window.__velaMedia.skip(seconds) : false;",
                arguments: ["seconds": seconds], in: frame, in: .defaultClient
            ) { _ in }
        }
    }

    private func applyMediaSettingsEverywhere() {
        applyMediaSettings(in: nil)
        for frame in mediaFrames.values where !frame.isMainFrame {
            applyMediaSettings(in: frame)
        }
    }

    private func applyMediaSettings(in frame: WKFrameInfo?) {
        webView.callAsyncJavaScript(
            "if (window.__velaMedia) window.__velaMedia.apply(rate, muted);",
            arguments: ["rate": playbackRate, "muted": isMuted], in: frame, in: .defaultClient
        ) { _ in }
    }
}

extension BrowserStore {
    /// View ▸ Video ▸ Faster / Slower: steps through MediaControls.speeds.
    func changeVideoSpeed(faster: Bool) {
        guard let tab = selectedTab else { return }
        let speeds = MediaControls.speeds
        let next: Double
        if faster {
            next = speeds.first { $0 > tab.playbackRate + 0.01 } ?? speeds.last!
        } else {
            next = speeds.last { $0 < tab.playbackRate - 0.01 } ?? speeds.first!
        }
        setVideoSpeed(next)
    }

    func setVideoSpeed(_ speed: Double) {
        guard let tab = selectedTab else { return }
        tab.setPlaybackRate(speed)
        showNotice(speed == 1 ? "Normal video speed" : "Video speed \(speed.formatted(.number.precision(.fractionLength(0...2))))×")
    }
}
