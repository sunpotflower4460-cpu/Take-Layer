import SwiftUI

struct SongMemoryEditorView: View {
    let library: SongMemoryLibrary
    let linkedSongID: UUID?
    let linkedArrangementID: UUID?
    let onSave: (ConfirmedSongMemoryInput) -> Void
    let onDetach: () -> Void

    @State private var selectedSongID: UUID?
    @State private var existingArrangementID: UUID?
    @State private var canonicalTitle = ""
    @State private var artistName = ""
    @State private var aliasesText = ""
    @State private var isOriginal = true
    @State private var bpmText = ""
    @State private var keySignature = ""
    @State private var tuningHzText = ""
    @State private var arrangementName = ""
    @State private var arrangementType: SongArrangementType = .acousticSolo
    @State private var formalLyricsText = ""
    @State private var lyricsLanguage = "ja"
    @State private var didLoadInitialState = false

    var body: some View {
        SectionCard(title: "Song Intelligence / Song Memory") {
            Text("曲名・アーティスト・正式歌詞など、人間が確認した情報を曲単位で保存します。ここで保存した値は将来のAI推定や外部メタデータより優先されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Song Memory", selection: $selectedSongID) {
                Text("新しい曲として登録").tag(Optional<UUID>.none)
                ForEach(sortedIdentities) { identity in
                    Text(identityLabel(identity)).tag(Optional(identity.id))
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedSongID) { _, newValue in
                loadSong(newValue)
            }

            TextField("Canonical title", text: $canonicalTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Artist / Unit", text: $artistName)
                .textFieldStyle(.roundedBorder)
            TextField("Aliases（カンマ区切り）", text: $aliasesText)
                .textFieldStyle(.roundedBorder)

            Toggle("オリジナル曲", isOn: $isOriginal)

            HStack {
                TextField("BPM", text: $bpmText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                TextField("Key", text: $keySignature)
                    .textFieldStyle(.roundedBorder)
                TextField("Tuning Hz", text: $tuningHzText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            Text("Arrangement")
                .font(.subheadline.weight(.semibold))

            if selectedSongID != nil {
                Picker("Arrangement Memory", selection: $existingArrangementID) {
                    Text("新しいArrangement").tag(Optional<UUID>.none)
                    ForEach(availableArrangements) { arrangement in
                        Text(arrangementLabel(arrangement)).tag(Optional(arrangement.id))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: existingArrangementID) { _, newValue in
                    loadArrangement(newValue)
                }
            }

            Picker("Type", selection: $arrangementType) {
                ForEach(SongArrangementType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)
            TextField("Arrangement name", text: $arrangementName)
                .textFieldStyle(.roundedBorder)

            if selectedSongID != nil {
                Text(existingArrangementID == nil
                    ? "この曲に新しいArrangementを追加してProjectへ接続します。"
                    : "選択したArrangementの確認済み情報を更新します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Formal Lyrics")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                TextField("language", text: $lyricsLanguage)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
            }
            TextEditor(text: $formalLyricsText)
                .frame(minHeight: 140)
                .padding(8)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.secondary.opacity(0.25), lineWidth: 1)
                }

            Text("歌詞を空にして保存すると、この曲のユーザー確認済み正式歌詞を削除します。自動推定歌詞で上書きはしません。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(saveButtonTitle) {
                    onSave(makeInput())
                }
                .buttonStyle(.borderedProminent)
                .disabled(canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if linkedSongID != nil {
                    Button("Projectから切り離す") {
                        onDetach()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let linkedIdentity = library.identity(for: linkedSongID) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("このProjectは「\(linkedIdentity.canonicalTitle)」に接続済み")
                        .font(.footnote.weight(.semibold))
                    if let linkedArrangement = library.arrangement(for: linkedArrangementID) {
                        Text("Arrangement: \(linkedArrangement.name)")
                            .font(.caption)
                    }
                    Text("userConfirmed: \(linkedIdentity.userConfirmed ? "true" : "false") / confidence: \(linkedIdentity.confidence, format: .number.precision(.fractionLength(2)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            guard !didLoadInitialState else { return }
            didLoadInitialState = true
            selectedSongID = linkedSongID
            loadSong(linkedSongID)
        }
        .onChange(of: linkedSongID) { _, newValue in
            selectedSongID = newValue
            loadSong(newValue)
        }
    }

    private var sortedIdentities: [SongIdentity] {
        library.identities.sorted {
            $0.canonicalTitle.localizedCaseInsensitiveCompare($1.canonicalTitle) == .orderedAscending
        }
    }

    private var availableArrangements: [ArrangementProfile] {
        library.arrangements(for: selectedSongID).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var saveButtonTitle: String {
        if selectedSongID == nil {
            return "Song Memoryに登録"
        }
        if existingArrangementID == nil {
            return "新しいArrangementを追加"
        }
        return "確認済み情報を更新"
    }

    private func identityLabel(_ identity: SongIdentity) -> String {
        guard let artist = identity.artistName, !artist.isEmpty else {
            return identity.canonicalTitle
        }
        return "\(identity.canonicalTitle) — \(artist)"
    }

    private func arrangementLabel(_ arrangement: ArrangementProfile) -> String {
        "\(arrangement.name) — \(arrangement.type.displayName)"
    }

    private func loadSong(_ songID: UUID?) {
        guard let identity = library.identity(for: songID) else {
            existingArrangementID = nil
            canonicalTitle = ""
            artistName = ""
            aliasesText = ""
            isOriginal = true
            bpmText = ""
            keySignature = ""
            tuningHzText = ""
            arrangementName = ""
            arrangementType = .acousticSolo
            formalLyricsText = ""
            lyricsLanguage = "ja"
            return
        }

        canonicalTitle = identity.canonicalTitle
        artistName = identity.artistName ?? ""
        aliasesText = identity.aliases.joined(separator: ", ")
        isOriginal = identity.isOriginal

        if let profile = library.profile(for: identity.id) {
            bpmText = profile.bpm.map { String(format: "%g", $0) } ?? ""
            keySignature = profile.keySignature ?? ""
            tuningHzText = profile.tuningHz.map { String(format: "%g", $0) } ?? ""
        } else {
            bpmText = ""
            keySignature = ""
            tuningHzText = ""
        }

        let preferredArrangement: ArrangementProfile?
        if linkedSongID == identity.id,
           let linked = library.arrangement(for: linkedArrangementID),
           linked.songID == identity.id {
            preferredArrangement = linked
        } else {
            preferredArrangement = availableArrangements.first
        }
        existingArrangementID = preferredArrangement?.id
        loadArrangement(preferredArrangement?.id)

        if let lyrics = library.lyrics(for: identity.id) {
            formalLyricsText = lyrics.text
            lyricsLanguage = lyrics.language ?? "ja"
        } else {
            formalLyricsText = ""
            lyricsLanguage = "ja"
        }
    }

    private func loadArrangement(_ arrangementID: UUID?) {
        guard let arrangement = library.arrangement(for: arrangementID),
              arrangement.songID == selectedSongID else {
            arrangementName = ""
            arrangementType = .acousticSolo
            return
        }
        arrangementName = arrangement.name
        arrangementType = arrangement.type
    }

    private func makeInput() -> ConfirmedSongMemoryInput {
        ConfirmedSongMemoryInput(
            existingSongID: selectedSongID,
            existingArrangementID: existingArrangementID,
            canonicalTitle: canonicalTitle,
            artistName: artistName,
            aliases: aliasesText.split(separator: ",").map(String.init),
            isOriginal: isOriginal,
            bpm: Double(bpmText),
            keySignature: keySignature,
            tuningHz: Double(tuningHzText),
            arrangementName: arrangementName,
            arrangementType: arrangementType,
            formalLyricsText: formalLyricsText,
            lyricsLanguage: lyricsLanguage
        )
    }
}
