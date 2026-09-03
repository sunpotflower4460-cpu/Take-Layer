import CryptoKit
import Foundation

enum ResolverPrivateCorpusRunnerError: LocalizedError, Equatable {
    case unsupportedManifestSchemaVersion(Int)
    case emptyManifestName
    case emptyCaseName
    case absolutePathNotAllowed(String)
    case pathEscapesCorpusRoot(String)
    case missingFile(String)
    case unsupportedAudioExtension(String)
    case duplicateCaseID(UUID)

    var errorDescription: String? {
        switch self {
        case .unsupportedManifestSchemaVersion(let version):
            return "Resolver private corpus manifest schema version \(version) is not supported."
        case .emptyManifestName:
            return "Resolver private corpus manifest name is empty."
        case .emptyCaseName:
            return "Resolver private corpus contains a case with an empty name."
        case .absolutePathNotAllowed(let path):
            return "Resolver private corpus paths must be relative: \(path)"
        case .pathEscapesCorpusRoot(let path):
            return "Resolver private corpus path escapes the configured root: \(path)"
        case .missingFile(let path):
            return "Resolver private corpus WAV does not exist: \(path)"
        case .unsupportedAudioExtension(let path):
            return "Resolver private corpus currently accepts WAV files only: \(path)"
        case .duplicateCaseID(let id):
            return "Resolver private corpus contains duplicate benchmark case ID: \(id.uuidString)"
        }
    }
}

enum ResolverPrivateCorpusRunner {
    static func loadManifest(from url: URL) throws -> ResolverPrivateCorpusManifest {
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(ResolverPrivateCorpusManifest.self, from: data)
        try validateManifest(manifest)
        return manifest
    }

    static func buildDataset(
        manifest: ResolverPrivateCorpusManifest,
        corpusRoot: URL
    ) throws -> ResolverCalibrationDataset {
        try validateManifest(manifest)

        let root = corpusRoot.standardizedFileURL.resolvingSymlinksInPath()
        var seenCaseIDs = Set<UUID>()
        var cases: [ResolverCalibrationCase] = []
        cases.reserveCapacity(manifest.cases.count)

        for manifestCase in manifest.cases {
            let queryURL = try resolveWAV(
                relativePath: manifestCase.queryPath,
                corpusRoot: root
            )
            let referenceURL = try resolveWAV(
                relativePath: manifestCase.referencePath,
                corpusRoot: root
            )
            let caseID = manifestCase.id ?? stableCaseID(
                manifestName: manifest.name,
                manifestCase: manifestCase
            )
            guard seenCaseIDs.insert(caseID).inserted else {
                throw ResolverPrivateCorpusRunnerError.duplicateCaseID(caseID)
            }

            var benchmarkCase = try ResolverCalibrationHarness.makeCase(
                name: manifestCase.name.trimmingCharacters(in: .whitespacesAndNewlines),
                relationship: manifestCase.relationship,
                queryWAVURL: queryURL,
                referenceWAVURL: referenceURL,
                notes: manifestCase.notes
            )
            benchmarkCase.id = caseID
            cases.append(benchmarkCase)
        }

        return ResolverCalibrationDataset(name: manifest.name, cases: cases)
    }

    @discardableResult
    static func run(
        manifestURL: URL,
        corpusRoot: URL? = nil,
        datasetOutputURL: URL? = nil,
        reportOutputURL: URL? = nil,
        thresholds: [Double] = ResolverCalibrationHarness.defaultThresholds
    ) throws -> ResolverPrivateCorpusRunResult {
        let manifest = try loadManifest(from: manifestURL)
        let root = corpusRoot ?? manifestURL.deletingLastPathComponent()
        let dataset = try buildDataset(manifest: manifest, corpusRoot: root)
        let report = try ResolverCalibrationHarness.evaluate(dataset, thresholds: thresholds)

        if let datasetOutputURL {
            try ensureParentDirectory(for: datasetOutputURL)
            try ResolverCalibrationHarness.save(dataset, to: datasetOutputURL)
        }
        if let reportOutputURL {
            try ensureParentDirectory(for: reportOutputURL)
            try ResolverCalibrationHarness.save(report, to: reportOutputURL)
        }

        return ResolverPrivateCorpusRunResult(
            dataset: dataset,
            report: report,
            datasetURL: datasetOutputURL,
            reportURL: reportOutputURL
        )
    }

    private static func validateManifest(_ manifest: ResolverPrivateCorpusManifest) throws {
        guard manifest.schemaVersion == ResolverPrivateCorpusManifest.currentSchemaVersion else {
            throw ResolverPrivateCorpusRunnerError.unsupportedManifestSchemaVersion(manifest.schemaVersion)
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResolverPrivateCorpusRunnerError.emptyManifestName
        }
        for manifestCase in manifest.cases {
            guard !manifestCase.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ResolverPrivateCorpusRunnerError.emptyCaseName
            }
        }
    }

    private static func resolveWAV(relativePath: String, corpusRoot: URL) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = NSString(string: trimmed)
        guard !trimmed.isEmpty, !path.isAbsolutePath, !trimmed.hasPrefix("~") else {
            throw ResolverPrivateCorpusRunnerError.absolutePathNotAllowed(relativePath)
        }

        let candidate = corpusRoot
            .appendingPathComponent(trimmed, isDirectory: false)
            .standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw ResolverPrivateCorpusRunnerError.missingFile(relativePath)
        }

        let resolvedRoot = corpusRoot.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        guard isDescendant(resolvedCandidate, of: resolvedRoot) else {
            throw ResolverPrivateCorpusRunnerError.pathEscapesCorpusRoot(relativePath)
        }

        guard resolvedCandidate.pathExtension.lowercased() == "wav" else {
            throw ResolverPrivateCorpusRunnerError.unsupportedAudioExtension(relativePath)
        }
        return resolvedCandidate
    }

    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path.hasPrefix(rootPath)
    }

    private static func stableCaseID(
        manifestName: String,
        manifestCase: ResolverPrivateCorpusManifestCase
    ) -> UUID {
        let payload = [
            manifestName.trimmingCharacters(in: .whitespacesAndNewlines),
            manifestCase.name.trimmingCharacters(in: .whitespacesAndNewlines),
            manifestCase.relationship.rawValue,
            manifestCase.queryPath,
            manifestCase.referencePath
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        let bytes = Array(digest.prefix(16))
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }

    private static func ensureParentDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
