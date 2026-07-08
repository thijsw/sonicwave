import Foundation

/// Scrobbling: report plays to the server so play counts, recently-played and
/// any connected external scrobbler stay accurate. A "now playing" report
/// fires at each track start; the play itself is recorded once playback
/// passes the customary threshold. Best-effort — failures never surface.
extension PlayerModel {
    /// Defaults to on; the Settings → Playback toggle stores the same key.
    private var scrobblingEnabled: Bool {
        UserDefaults.standard.object(forKey: "scrobbleEnabled") == nil
            || UserDefaults.standard.bool(forKey: "scrobbleEnabled")
    }

    /// A track just became current: report "now playing" (submission=false)
    /// and re-arm the play-count submission.
    func scrobbleTrackStarted() {
        submittedScrobble = false
        guard scrobblingEnabled, let scrobbler, let id = currentTrack?.id else { return }
        Task { await scrobbler(id, false) }
    }

    /// Record the play once playback passes half the track or 4 minutes,
    /// whichever is first; tracks under 30s don't count — the Last.fm rules,
    /// which Navidrome mirrors. Called from the position event stream.
    func scrobbleIfPlayedEnough() {
        guard !submittedScrobble, scrobblingEnabled, let scrobbler,
              let id = currentTrack?.id, duration >= 30,
              position >= min(duration / 2, 240) else { return }
        submittedScrobble = true
        Task { await scrobbler(id, true) }
    }
}
