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

struct UsageError: Error {}

do {
    let options = try parseOptions()
    let result = try HistoryRepairCommand.run(
        stateURL: options.stateURL!,
        manifestURL: options.manifestURL!,
        candidateURL: options.candidateURL,
        apply: options.apply
    )
    let report = result.manifest.report
    print("\(result.manifest.mode) before=\(report.beforeCount) after=\(report.afterCount) removed=\(report.removedIDs.count)")
} catch is UsageError {
    FileHandle.standardError.write(Data(
        "usage: ActiveBreakRepair --state PATH --manifest PATH [--candidate PATH | --apply]\n".utf8
    ))
    exit(64)
} catch {
    FileHandle.standardError.write(Data("ActiveBreakRepair failed: \(error)\n".utf8))
    exit(1)
}
