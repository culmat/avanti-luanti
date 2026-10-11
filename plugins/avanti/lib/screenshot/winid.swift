// Print the window number of the first on-screen window owned by a process whose name contains the argument.
import CoreGraphics
import Foundation
let needle = CommandLine.arguments.count > 1 ? CommandLine.arguments[1].lowercased() : "luanti"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let owner = (w[kCGWindowOwnerName as String] as? String ?? "").lowercased()
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    if owner.contains(needle) && layer == 0, let num = w[kCGWindowNumber as String] as? Int {
        print(num)
        exit(0)
    }
}
exit(1)
