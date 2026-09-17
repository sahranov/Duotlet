import Foundation

// Integration check for the installed app, launched with --profile-animation.
// Uses its existing preview IPC and actual drawable presentation timestamps.
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(CommandLine.arguments.count > 1 ? "to.maki.Duotlet.profileScenario" : "to.maki.Duotlet.preview"),
    object: CommandLine.arguments.dropFirst().first, userInfo: nil, deliverImmediately: true)
Thread.sleep(forTimeInterval: 5)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
process.arguments = ["show", "--last", "6s", "--style", "compact", "--predicate",
    "subsystem == \"to.maki.Duotlet\" AND (eventMessage CONTAINS \"profile:\" OR eventMessage CONTAINS \"wake:\")"]
let pipe = Pipe()
process.standardOutput = pipe
try process.run()
let data = pipe.fileHandleForReading.readDataToEndOfFile()
process.waitUntilExit()
let output = String(decoding: data, as: UTF8.self)
print(output)
let expression = try NSRegularExpression(pattern:
    "presentation median ([0-9.]+) ms, p95 ([0-9.]+) ms, max ([0-9.]+) ms, gaps>25ms ([0-9]+)")
guard let match = expression.matches(in: output, range: NSRange(output.startIndex..., in: output)).last else {
    print("FAIL: no presentation profile; check app launch flag, screen access and enabled effect")
    exit(1)
}
func number(_ index: Int) -> Double {
    Double(output[Range(match.range(at: index), in: output)!])!
}
let wakePassed = CommandLine.arguments.dropFirst().first != "wake"
    || output.contains("wake: fresh picture ready, returning saved effect")
let passed = number(2) < 18.5 && number(3) < 25 && number(4) == 0 && wakePassed
print(passed ? "PASS: evenly presented 60 Hz preview, no gaps over 25 ms" : "FAIL: visible frame gaps remain")
exit(passed ? 0 : 1)
