import Darwin
import Foundation

// take-layer-render: headless RENDER_EDIT_PLAN entry point for the Mac Runner.
//   take-layer-render --help
//   take-layer-render render --request <request.json> --result <result.json>
//   take-layer-render self-test --workdir <dir> [--result <result.json>]
// Exit codes: 0 completed, 2 usage, 3 render failed (details in the result JSON).

let usage = """
take-layer-render \(renderToolVersion)
usage:
  take-layer-render --help
  take-layer-render render --request <request.json> --result <result.json>
  take-layer-render self-test --workdir <dir> [--result <result.json>]
  take-layer-render make-fixtures --workdir <dir> --result <fixtures.json>   (synthetic 8 s video + 10 s WAV, for integration tests)
"""

func argValue(_ flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func emit(_ result: RenderResult, to path: String?) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(result) else { return }
    if let path { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args.contains("--help") || args.contains("-h") {
    print(usage)
    exit(args.isEmpty ? 2 : 0)
}

Task {
    var code: Int32 = 2
    switch args[0] {
    case "render":
        guard let requestPath = argValue("--request", in: args) else { print(usage); exit(2) }
        let resultPath = argValue("--result", in: args)
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: requestPath))
            let request = try JSONDecoder().decode(RenderEditPlanRequest.self, from: data)
            let result = await RenderPipeline.run(request)
            emit(result, to: resultPath)
            code = result.status == "completed" ? 0 : 3
        } catch {
            let result = RenderPipeline.failure(nil, key: "unknown", code: "INVALID_REQUEST", "cannot read request: \(error.localizedDescription)")
            emit(result, to: resultPath)
            code = 3
        }
    case "self-test":
        guard let workdir = argValue("--workdir", in: args) else { print(usage); exit(2) }
        let result = await RenderPipeline.selfTest(workDir: URL(fileURLWithPath: workdir, isDirectory: true))
        emit(result, to: argValue("--result", in: args))
        code = result.status == "completed" ? 0 : 3
    case "make-fixtures":
        guard let workdir = argValue("--workdir", in: args), let resultPath = argValue("--result", in: args) else { print(usage); exit(2) }
        do {
            let dir = URL(fileURLWithPath: workdir, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let video = dir.appendingPathComponent("fixture-video.mp4")
            let wav = dir.appendingPathComponent("fixture-master.wav")
            try await SelfTestMedia.makeVideo(at: video, seconds: 8, width: 640, height: 360, fps: 30)
            try SelfTestMedia.makeWav(at: wav, seconds: 10)
            let info: [String: Any] = [
                "videoPath": video.path, "wavPath": wav.path,
                "videoSha256": try Hashing.sha256Hex(of: video), "wavSha256": try Hashing.sha256Hex(of: wav),
                "videoDurationSec": 8, "wavDurationSec": 10, "videoWidth": 640, "videoHeight": 360, "wavSampleRate": 48000,
            ]
            try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]).write(to: URL(fileURLWithPath: resultPath), options: .atomic)
            code = 0
        } catch {
            FileHandle.standardError.write(Data("make-fixtures failed: \(error.localizedDescription)\n".utf8))
            code = 3
        }
    default:
        print(usage)
    }
    exit(code)
}
dispatchMain()
