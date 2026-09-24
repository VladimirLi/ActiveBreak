import ActiveBreakCore
import Foundation

struct Options {
    var stateURL: URL?
    var manifestURL: URL?
    var candidateURL: URL?
    var apply = false
}

func parseOptions() throws -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while let argument = arguments.first {
        arguments.removeFirst()
        switch argument {
        case "--state":
            guard let value = arguments.first else { throw UsageError() }
            arguments.removeFirst()
            options.stateURL = URL(fileURLWithPath: value)
        case "--manifest":
            guard let value = arguments.first else { throw UsageError() }
            arguments.removeFirst()
            options.manifestURL = URL(fileURLWithPath: value)
        case "--candidate":
            guard let value = arguments.first else { throw UsageError() }
            arguments.removeFirst()
            options.candidateURL = URL(fileURLWithPath: value)
        case "--apply":
            options.apply = true
        default:
            throw UsageError()
        }
    }
    guard options.stateURL != nil, options.manifestURL != nil else { throw UsageError() }
    return options
}

struct Manifest: Codable {
    let mode: String
    let statePath: String
    let candidatePath: String?
    let backupPath: String?
    let report: HistoryRepairReport
}

struct UsageError: Error {}

do {
    let options = try parseOptions()
    let stateURL = options.stateURL!
    let manifestURL = options.manifestURL!
    let result: HistoryRepairResult
    let backupURL: URL?
    if options.apply {
        let applied = try HistoryRepair.apply(to: stateURL)
        result = HistoryRepair.preview(try HistoryStore(url: stateURL).load())
        backupURL = applied.backupURL
        let manifest = Manifest(
            mode: "apply",
            statePath: stateURL.path,
            candidatePath: nil,
            backupPath: backupURL?.path,
            report: applied.report
        )
        try JSONEncoder.activeBreak.encode(manifest).write(to: manifestURL, options: .atomic)
        print("apply before=\(applied.report.beforeCount) after=\(applied.report.afterCount) removed=\(applied.report.removedIDs.count)")
    } else {
        result = HistoryRepair.preview(try HistoryStore(url: stateURL).load())
        if let candidateURL = options.candidateURL {
            try HistoryStore(url: candidateURL).save(result.data)
        }
        let manifest = Manifest(
            mode: "preview",
            statePath: stateURL.path,
            candidatePath: options.candidateURL?.path,
            backupPath: nil,
            report: result.report
        )
        try JSONEncoder.activeBreak.encode(manifest).write(to: manifestURL, options: .atomic)
        print("preview before=\(result.report.beforeCount) after=\(result.report.afterCount) removed=\(result.report.removedIDs.count)")
    }
} catch is UsageError {
    FileHandle.standardError.write(Data(
        "usage: ActiveBreakRepair --state PATH --manifest PATH [--candidate PATH | --apply]\n".utf8
    ))
    exit(64)
} catch {
    FileHandle.standardError.write(Data("ActiveBreakRepair failed: \(error)\n".utf8))
    exit(1)
}
