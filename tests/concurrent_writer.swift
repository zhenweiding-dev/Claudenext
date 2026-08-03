// Half of the concurrency test driven by run-tests.sh: hammers a project's
// rules file with intercept writes while the Python hook appends rules to the
// same file. Both sides take the same flock, so neither may lose the other's
// changes and the file must never be observed half-written.

import Foundation

@main
enum ConcurrentWriter {
    static func main() {
        guard CommandLine.arguments.count > 2,
              let rounds = Int(CommandLine.arguments[2]) else {
            FileHandle.standardError.write(Data("usage: <cwd> <rounds>\n".utf8))
            exit(1)
        }
        let cwd = CommandLine.arguments[1]
        for i in 0..<rounds {
            ProjectScope.setIntercept(["Bash", "Tool\(i)"], cwd: cwd)
        }
    }
}
