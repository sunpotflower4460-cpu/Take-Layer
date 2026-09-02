import SwiftUI

struct SongResolverEvidenceView: View {
    let project: ProjectDraft
    let songMemory: SongMemoryLibrary
    let evidenceLibrary: SongResolverEvidenceLibrary
    let currentEvidence: AudioEvidenceVector?
    let matchResult: SongMatchResult?
    let isAnalyzing: Bool
    let message: String?
    let onRegisterEvidence: () -> Void
    let onAnalyze: () -> Void
    let onConfirmCandidate: (SongMatchCandidate) -> Void

    var body: some View {
        SectionCard(title: "Song Resolver Evidence") {
            Text("完成WAVから決定論的な音響Evidenceを作り、既知Arrangementとの候補を提示します。Tonal Evidenceは移調に加えて構成の伸縮も比較しますが、Resolverは自動でSong Memoryへ接続しません。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            MediaInfoGrid(rows: [
                ("Master WAV", project.importedMasterAudio == nil ? "Missing" : "Ready"),
                ("Known fingerprints", "\(evidenceLibrary.fingerprints.count)"),
                ("Linked arrangement evidence", "\(linkedArrangementEvidenceCount)"),
                ("Current signature", currentEvidence.map { String($0.signature.prefix(12)) } ?? "Not analyzed"),
                ("Tonal Evidence", currentEvidence?.tonalEvidence == nil ? "Not analyzed" : "Ready")
            ])

            HStack {
                Button(isAnalyzing ? "解析中…" : "このWAVをArrangement Evidenceとして登録") {
                    onRegisterEvidence()
                }
                .buttonStyle(.bordered)
                .disabled(isAnalyzing || project.importedMasterAudio == nil || project.songMemoryLink?.arrangementID == nil)

                Button(isAnalyzing ? "解析中…" : "Song Memory候補を解析") {
                    onAnalyze()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnalyzing || project.importedMasterAudio == nil)
            }

            if isAnalyzing {
                ProgressView()
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let matchResult {
                Divider()
                Text("Candidates")
                    .font(.headline)

                if matchResult.candidates.isEmpty {
                    Text("候補はありません。まず確認済みSong / ArrangementへWAV Evidenceを登録すると比較できるようになります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matchResult.candidates) { candidate in
                        candidateRow(candidate, matchResult: matchResult)
                    }
                }
            }
        }
    }

    private var linkedArrangementEvidenceCount: Int {
        guard let arrangementID = project.songMemoryLink?.arrangementID else { return 0 }
        return evidenceLibrary.fingerprints(for: arrangementID).count
    }

    @ViewBuilder
    private func candidateRow(_ candidate: SongMatchCandidate, matchResult: SongMatchResult) -> some View {
        let identity = songMemory.identity(for: candidate.songID)
        let arrangement = songMemory.arrangement(for: candidate.arrangementID)
        let isResolved = matchResult.resolvedSongID == candidate.songID
            && matchResult.resolvedArrangementID == candidate.arrangementID

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(identity?.canonicalTitle ?? "Unknown Song")
                        .font(.subheadline.weight(.semibold))
                    Text(arrangement?.name ?? "Unknown Arrangement")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(candidate.confidence, format: .percent.precision(.fractionLength(1)))
                    .font(.headline.monospacedDigit())
            }

            MediaInfoGrid(rows: evidenceRows(for: candidate.evidence))

            if isResolved {
                Label("この候補へ確認済み接続", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else {
                Button("この候補に接続") {
                    onConfirmCandidate(candidate)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func evidenceRows(for evidence: SongMatchEvidence) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("duration", percent(evidence.duration)),
            ("energy shape", percent(evidence.energyEnvelope)),
            ("transient shape", percent(evidence.transientEnvelope))
        ]
        if let tonal = evidence.tonal {
            rows.append(("tonal / chroma", percent(tonal)))
        }
        if let semitones = evidence.transpositionSemitones {
            rows.append(("estimated key shift", semitoneText(semitones)))
        }
        if let coverage = evidence.tonalAlignmentCoverage {
            rows.append(("tonal structure coverage", percent(coverage)))
        }
        if let warp = evidence.tonalWarpFraction {
            rows.append(("elastic warp", percent(warp)))
        }
        return rows
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }

    private func semitoneText(_ value: Int) -> String {
        if value == 0 { return "same key" }
        return value > 0 ? "+\(value) semitones" : "\(value) semitones"
    }
}
