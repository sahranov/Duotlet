import Foundation
import os

/// Read with:
///
///     log show --last 5m --predicate 'subsystem == "to.maki.Duotlet"'
///
/// Notice level, not info: info level lives only in memory, and `log show`
/// reads the on-disk store.
enum Diagnostics {
    static let geometry = Logger(subsystem: "to.maki.Duotlet", category: "geometry")
    static let lid = Logger(subsystem: "to.maki.Duotlet", category: "lid")
}
