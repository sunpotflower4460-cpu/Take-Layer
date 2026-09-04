import Foundation

enum SongArrangementType: String, Codable, CaseIterable, Identifiable {
    case studio
    case acousticSolo = "acoustic_solo"
    case live
    case duo
    case band
    case alternate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .studio: return "Studio"
        case .acousticSolo: return "Acoustic Solo"
        case .live: return "Live"
        case .duo: return "Duo"
        case .band: return "Band"
        case .alternate: return "Alternate"
        }
    }
}

struct SongExternalIDs: Codable, Equatable {
    var isrc: String?
    var musicBrainzRecordingID: String?
    var appleMusicSongID: String?
}

struct SongIdentity: Identifiable, Codable, Equatable {
    var id: UUID
    var canonicalTitle: String
    var artistName: String?
    var aliases: [String]
    var isOriginal: Bool
    var externalIDs: SongExternalIDs?
    var confidence: Double
    var userConfirmed: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct SongProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var songID: UUID
    var bpm: Double?
    var keySignature: String?
    var tuningHz: Double?
    var themeTags: [String]
    var visualMoodTags: [String]
    var formalLyricsID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

struct ArrangementProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var songID: UUID
    var name: String
    var type: SongArrangementType
    var expectedDurationSec: Double?
    var tempoHint: Double?
    var keyHint: String?
    var fingerprintIDs: [String]
    var createdAt: Date
    var updatedAt: Date
}

enum FormalLyricsSource: String, Codable {
    case userConfirmed = "user_confirmed"
    case licensedProvider = "licensed_provider"
    case transcriptionEstimate = "transcription_estimate"

    /// Song-information authority order. A newer estimate must never outrank a
    /// permitted provider record, and neither may outrank user-confirmed lyrics.
    var authorityPriority: Int {
        switch self {
        case .userConfirmed: return 3
        case .licensedProvider: return 2
        case .transcriptionEstimate: return 1
        }
    }
}

struct FormalLyrics: Identifiable, Codable, Equatable {
    var id: UUID
    var songID: UUID
    var text: String
    var source: FormalLyricsSource
    var userConfirmed: Bool
    var language: String?
    var version: Int
    var createdAt: Date
    var updatedAt: Date
}

struct ProjectSongMemoryLink: Codable, Equatable {
    var songID: UUID
    var arrangementID: UUID?
    var linkedAt: Date
}

struct ConfirmedSongMemoryInput: Equatable {
    var existingSongID: UUID?
    var existingArrangementID: UUID?
    var canonicalTitle: String
    var artistName: String
    var aliases: [String]
    var isOriginal: Bool
    var bpm: Double?
    var keySignature: String
    var tuningHz: Double?
    var arrangementName: String
    var arrangementType: SongArrangementType
    var arrangementTempoHint: Double?
    var arrangementKeyHint: String
    var formalLyricsText: String
    var lyricsLanguage: String
}

struct SongMemoryLibrary: Codable, Equatable {
    var identities: [SongIdentity] = []
    var profiles: [SongProfile] = []
    var arrangements: [ArrangementProfile] = []
    var formalLyrics: [FormalLyrics] = []

    func identity(for songID: UUID?) -> SongIdentity? {
        guard let songID else { return nil }
        return identities.first { $0.id == songID }
    }

    func profile(for songID: UUID?) -> SongProfile? {
        guard let songID else { return nil }
        return profiles.first { $0.songID == songID }
    }

    func arrangement(for arrangementID: UUID?) -> ArrangementProfile? {
        guard let arrangementID else { return nil }
        return arrangements.first { $0.id == arrangementID }
    }

    func arrangements(for songID: UUID?) -> [ArrangementProfile] {
        guard let songID else { return [] }
        return arrangements.filter { $0.songID == songID }
    }

    func lyrics(for songID: UUID?) -> FormalLyrics? {
        guard let songID else { return nil }
        return formalLyrics
            .filter { $0.songID == songID }
            .sorted { lhs, rhs in
                if lhs.source.authorityPriority != rhs.source.authorityPriority {
                    return lhs.source.authorityPriority > rhs.source.authorityPriority
                }
                if lhs.userConfirmed != rhs.userConfirmed {
                    return lhs.userConfirmed && !rhs.userConfirmed
                }
                if lhs.version != rhs.version {
                    return lhs.version > rhs.version
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .first
    }

    /// Repairs a persisted Project link against the current Song Memory library.
    /// Missing songs invalidate the whole link. A missing/wrong Arrangement keeps
    /// the confirmed Song association but drops only the stale Arrangement ID.
    func repairedProjectLink(_ link: ProjectSongMemoryLink?) -> ProjectSongMemoryLink? {
        guard let link, identity(for: link.songID) != nil else { return nil }
        guard let arrangementID = link.arrangementID else { return link }
        guard let arrangement = arrangement(for: arrangementID), arrangement.songID == link.songID else {
            return ProjectSongMemoryLink(songID: link.songID, arrangementID: nil, linkedAt: link.linkedAt)
        }
        return link
    }

    @discardableResult
    mutating func upsertConfirmedSong(
        _ input: ConfirmedSongMemoryInput,
        now: Date = Date()
    ) -> ProjectSongMemoryLink {
        let title = input.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = optionalTrimmed(input.artistName)
        let aliases = uniqueTrimmed(input.aliases)
        let keySignature = optionalTrimmed(input.keySignature)
        let arrangementName = input.arrangementName.trimmingCharacters(in: .whitespacesAndNewlines)
        let arrangementTempoHint = sanitizedPositive(input.arrangementTempoHint) ?? sanitizedPositive(input.bpm)
        let arrangementKeyHint = optionalTrimmed(input.arrangementKeyHint) ?? keySignature
        let language = optionalTrimmed(input.lyricsLanguage)

        let songID: UUID
        if let existingSongID = input.existingSongID,
           let index = identities.firstIndex(where: { $0.id == existingSongID }) {
            songID = existingSongID
            identities[index].canonicalTitle = title
            identities[index].artistName = artist
            identities[index].aliases = aliases
            identities[index].isOriginal = input.isOriginal
            identities[index].confidence = 1.0
            identities[index].userConfirmed = true
            identities[index].updatedAt = now
        } else {
            songID = UUID()
            identities.append(
                SongIdentity(
                    id: songID,
                    canonicalTitle: title,
                    artistName: artist,
                    aliases: aliases,
                    isOriginal: input.isOriginal,
                    externalIDs: nil,
                    confidence: 1.0,
                    userConfirmed: true,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        let profileID: UUID
        if let index = profiles.firstIndex(where: { $0.songID == songID }) {
            profileID = profiles[index].id
            profiles[index].bpm = sanitizedPositive(input.bpm)
            profiles[index].keySignature = keySignature
            profiles[index].tuningHz = sanitizedPositive(input.tuningHz)
            profiles[index].updatedAt = now
        } else {
            profileID = UUID()
            profiles.append(
                SongProfile(
                    id: profileID,
                    songID: songID,
                    bpm: sanitizedPositive(input.bpm),
                    keySignature: keySignature,
                    tuningHz: sanitizedPositive(input.tuningHz),
                    themeTags: [],
                    visualMoodTags: [],
                    formalLyricsID: nil,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        let arrangementID: UUID
        if let existingArrangementID = input.existingArrangementID,
           let index = arrangements.firstIndex(where: { $0.id == existingArrangementID && $0.songID == songID }) {
            arrangementID = existingArrangementID
            arrangements[index].name = arrangementName.isEmpty ? input.arrangementType.displayName : arrangementName
            arrangements[index].type = input.arrangementType
            arrangements[index].tempoHint = arrangementTempoHint
            arrangements[index].keyHint = arrangementKeyHint
            arrangements[index].updatedAt = now
        } else {
            arrangementID = UUID()
            arrangements.append(
                ArrangementProfile(
                    id: arrangementID,
                    songID: songID,
                    name: arrangementName.isEmpty ? input.arrangementType.displayName : arrangementName,
                    type: input.arrangementType,
                    expectedDurationSec: nil,
                    tempoHint: arrangementTempoHint,
                    keyHint: arrangementKeyHint,
                    fingerprintIDs: [],
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        let lyricsText = input.formalLyricsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) {
            if lyricsText.isEmpty {
                if let existingLyricsID = profiles[profileIndex].formalLyricsID,
                   let lyricsIndex = formalLyrics.firstIndex(where: { $0.id == existingLyricsID }),
                   formalLyrics[lyricsIndex].source == .userConfirmed {
                    formalLyrics.remove(at: lyricsIndex)
                    // Restore the highest-authority remaining permitted source instead of
                    // leaving the profile pointer stale/empty when provider lyrics exist.
                    profiles[profileIndex].formalLyricsID = lyrics(for: songID)?.id
                }
            } else if let existingLyricsID = profiles[profileIndex].formalLyricsID,
                      let lyricsIndex = formalLyrics.firstIndex(where: { $0.id == existingLyricsID }),
                      formalLyrics[lyricsIndex].source == .userConfirmed {
                let changed = formalLyrics[lyricsIndex].text != lyricsText || formalLyrics[lyricsIndex].language != language
                formalLyrics[lyricsIndex].text = lyricsText
                formalLyrics[lyricsIndex].userConfirmed = true
                formalLyrics[lyricsIndex].language = language
                if changed {
                    formalLyrics[lyricsIndex].version += 1
                }
                formalLyrics[lyricsIndex].updatedAt = now
            } else if !lyricsText.isEmpty {
                let lyricsID = UUID()
                formalLyrics.append(
                    FormalLyrics(
                        id: lyricsID,
                        songID: songID,
                        text: lyricsText,
                        source: .userConfirmed,
                        userConfirmed: true,
                        language: language,
                        version: 1,
                        createdAt: now,
                        updatedAt: now
                    )
                )
                profiles[profileIndex].formalLyricsID = lyricsID
            }
            profiles[profileIndex].updatedAt = now
        }

        return ProjectSongMemoryLink(songID: songID, arrangementID: arrangementID, linkedAt: now)
    }

    mutating func attachFingerprintID(_ fingerprintID: UUID, to arrangementID: UUID) {
        guard let index = arrangements.firstIndex(where: { $0.id == arrangementID }) else { return }
        let value = fingerprintID.uuidString
        guard !arrangements[index].fingerprintIDs.contains(value) else { return }
        arrangements[index].fingerprintIDs.append(value)
        arrangements[index].updatedAt = Date()
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func uniqueTrimmed(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private func sanitizedPositive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
