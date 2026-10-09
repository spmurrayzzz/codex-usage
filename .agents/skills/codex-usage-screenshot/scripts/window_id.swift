import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1, let wanted = Int(CommandLine.arguments[1]) else {
    FileHandle.standardError.write("usage: window_id.swift <pid>\n".data(using: .utf8)!)
    exit(2)
}
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == wanted {
    let name = w[kCGWindowName as String] as? String ?? ""
    if let num = w[kCGWindowNumber as String] as? Int, !name.isEmpty {
        print(num)
    }
}
