import Foundation

if CommandLine.arguments.dropFirst().contains("--dump") {
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        defer { done.signal() }
        do {
            let result = try await CodexUsageService().fetch()
            UsageDumper.dump(result)
        } catch {
            FileHandle.standardError.write(Data("codex-usage: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    done.wait()
    exit(0)
}

CodexUsageApp.main()
