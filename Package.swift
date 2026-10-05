// swift-tools-version:5.9
//
// TakeLayerCore: Foundation-only core (models, TimelineMapper, SongResolver).
// MANIFEST UNVERIFIED LOCALLY (authored on a machine with no Swift toolchain).
//
// Single source of truth for the file list: tools/core-files.txt
// (tools/check-core-boundary.sh fails if this `sources:` list drifts from it).
// No files are moved; the iOS app target in project.yml is unchanged and does
// not consume this package. Types are internal (not `public`) today, so the
// library compiles but is not yet importable by other modules; see
// docs/artist-os-core-boundary.md.
import PackageDescription

let package = Package(
    name: "TakeLayerCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "TakeLayerCore", targets: ["TakeLayerCore"]),
    ],
    targets: [
        .target(
            name: "TakeLayerCore",
            path: "TakeLayer",
            sources: [
                "Models/ExportSettings.swift",
                "Models/ImportedMasterAudio.swift",
                "Models/ImportedVideo.swift",
                "Models/ProjectDraft.swift",
                "Models/RecordedTake.swift",
                "Models/ResolverCalibrationModels.swift",
                "Models/ResolverPrivateCorpusModels.swift",
                "Models/ShortEditDraft.swift",
                "Models/SongMemoryModels.swift",
                "Models/SongResolverEvidenceModels.swift",
                "Services/ExportValidationService.swift",
                "Services/SongResolver.swift",
                "Services/TimelineMapper.swift",
                "Utilities/TimeFormatting.swift",
            ]
        ),
    ]
)
