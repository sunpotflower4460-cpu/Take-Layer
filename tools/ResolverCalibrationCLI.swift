import Darwin
import Foundation

private enum ResolverCalibrationCLIError: LocalizedError {
    case missingValue(String)
    case missingManifest
    case invalidThreshold(String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .missingManifest:
            return "--manifest is required."
        case .invalidThreshold(let value):
            return "Invalid threshold list (each value must be finite and between 0 and 1): \(value)"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        }
    }
}

private struct ResolverCalibrationCLIConfiguration {
    var manifestURL: URL
    var corpusRootURL: URL
    var datasetURL: URL
    var reportURL: URL
    var thresholds: [Double]
}

@main
struct ResolverCalibrationCLI {
    static func main() {
        do {
            if CommandLine.arguments.dropFirst().contains("--help") || CommandLine.arguments.count == 1 {
                printUsage()
                return
            }
            let configuration = try parse(Array(CommandLine.arguments.dropFirst()))
            let result = try ResolverPrivateCorpusRunner.run(
                manifestURL: configuration.manifestURL,
                corpusRoot: configuration.corpusRootURL,
                datasetOutputURL: configuration.datasetURL,
                reportOutputURL: configuration.reportURL,
                thresholds: configuration.thresholds
            )
            printSummary(result, configuration: configuration)
        } catch {
            fputs("TakeLayer Resolver Calibration failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func parse(_ arguments: [String]) throws -> ResolverCalibrationCLIConfiguration {
        var manifestPath: String?
        var rootPath: String?
        var datasetPath: String?
        var reportPath: String?
        var thresholds = ResolverCalibrationHarness.defaultThresholds

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func nextValue() throws -> String {
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw ResolverCalibrationCLIError.missingValue(argument)
                }
                index += 1
                return arguments[valueIndex]
            }

            switch argument {
            case "--manifest":
                manifestPath = try nextValue()
            case "--root":
                rootPath = try nextValue()
            case "--dataset":
                datasetPath = try nextValue()
            case "--report":
                reportPath = try nextValue()
            case "--thresholds":
                let raw = try nextValue()
                let pieces = raw.split(separator: ",", omittingEmptySubsequences: false)
                let parsed = pieces.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard !parsed.isEmpty,
                      parsed.count == pieces.count,
                      parsed.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else {
                    throw ResolverCalibrationCLIError.invalidThreshold(raw)
                }
                thresholds = parsed
            default:
                throw ResolverCalibrationCLIError.unknownArgument(argument)
            }
            index += 1
        }

        guard let manifestPath else {
            throw ResolverCalibrationCLIError.missingManifest
        }

        let manifestURL = fileURL(manifestPath)
        let rootURL = rootPath.map(fileURL) ?? manifestURL.deletingLastPathComponent()
        let datasetURL = datasetPath.map(fileURL) ?? rootURL.appendingPathComponent("derived-dataset.json")
        let reportURL = reportPath.map(fileURL) ?? rootURL.appendingPathComponent("report.json")

        return ResolverCalibrationCLIConfiguration(
            manifestURL: manifestURL,
            corpusRootURL: rootURL,
            datasetURL: datasetURL,
            reportURL: reportURL,
            thresholds: thresholds
        )
    }

    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
    }

    private static func printSummary(
        _ result: ResolverPrivateCorpusRunResult,
        configuration: ResolverCalibrationCLIConfiguration
    ) {
        let report = result.report
        print("TakeLayer Resolver Calibration")
        print("Dataset: \(report.datasetName)")
        print("Cases: \(report.totalCases)")
        print("Same arrangement: \(report.sameArrangement.count)")
        print("Same song / different arrangement: \(report.sameSongDifferentArrangement.count)")
        print("Different song: \(report.differentSong.count)")
        print("Minimum positive confidence: \(formatted(report.minimumPositiveConfidence))")
        print("Maximum negative confidence: \(formatted(report.maximumNegativeConfidence))")
        print("Observed confidence gap: \(formatted(report.confidenceGap))")
        print("Derived dataset: \(configuration.datasetURL.path)")
        print("Report: \(configuration.reportURL.path)")
        print("Production Resolver thresholds and weights were not changed.")
    }

    private static func formatted(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.4f", value)
    }

    private static func printUsage() {
        print("""
        Usage:
          bash tools/run-resolver-calibration.sh --manifest <manifest.json> [options]

        Options:
          --root <directory>          Corpus root. Defaults to the manifest directory.
          --dataset <path>            Derived evidence dataset JSON output.
          --report <path>             Calibration report JSON output.
          --thresholds <csv>          Diagnostic thresholds from 0 through 1, e.g. 0.60,0.70,0.80,0.90
          --help                      Show this help.

        Raw WAV files remain local. This tool does not change production Resolver thresholds,
        Resolver weights, Song Memory links, TimelineMapper, or synchronization fields.
        """)
    }
}
