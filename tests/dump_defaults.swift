// Writes a pristine AppConfig to disk so run-tests.sh can diff the app's
// defaults against the hook's DEFAULT_CONFIG.
//
// The two programs share one config file and each falls back to its own
// defaults for anything missing from it. Drift between them is silent, and it
// can fail toward "the panel says a tool is being reviewed while the hook lets
// it through" — so it gets asserted rather than eyeballed.

import Foundation

@main
enum DumpDefaults {
    static func main() {
        precondition(ProcessInfo.processInfo.environment["CLAUDENEXT_HOME"] != nil,
                     "set CLAUDENEXT_HOME; this writes a file")
        AppConfig().save()
        print(AppConfig.configURL.path)
    }
}
