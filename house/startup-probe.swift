import AppKit
import CoreGraphics

// Start-up probe for an SDL FreeRDP client on macOS (extends /tmp/space-probe.swift).
//
// Launches <binary> against the dead port 127.0.0.1:9 (no RDP session is ever made) and, every ~2 ms (the SPACES=0 probe window lives ~13 ms):
//   * reads the active Space id (CGSGetActiveSpace, read-only) and counts changes;
//   * lists on-screen windows owned by the client's PID (CGWindowListCopyWindowInfo) and tracks
//     every window whose bounds equal a display's bounds ("display-covering"), how long it stays
//     visible, plus windows covering >= 90 % of a display (a Spaces full-screen window can sit
//     below the camera notch and so not equal the display rect).
// The "connection failed" dialog is the end marker: the client is terminated 1 s after the first
// non-covering window of at least 200x100 pt shows up, or at the cap.
//
// usage: space-probe <binary> [--spaces <value>] [--log <file>] [--log-level <LEVEL>] [--cap <s>]
//   --spaces    value for SDL_VIDEO_MAC_FULLSCREEN_SPACES; omitted = variable removed from the env
//   --log       file receiving the client's stdout+stderr (default: discarded)
//   --log-level FreeRDP /log-level: value (default OFF; DEBUG prints SdlWindow::query monitor fields)

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") func CGSGetActiveSpace(_ cid: Int32) -> Int

func die(_ msg: String) -> Never {
  FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
  exit(2)
}

var argv = Array(CommandLine.arguments.dropFirst())
guard let binary = argv.first, !binary.hasPrefix("--") else {
  die("usage: space-probe <binary> [--spaces <value>] [--log <file>] [--log-level <LEVEL>] [--cap <s>]")
}
argv.removeFirst()
var spaces: String? = nil
var logPath: String? = nil
var logLevel = "OFF"
var cap = 12.0
while !argv.isEmpty {
  let key = argv.removeFirst()
  guard let val = argv.first else { die("missing value for \(key)") }
  argv.removeFirst()
  switch key {
  case "--spaces": spaces = val
  case "--log": logPath = val
  case "--log-level": logLevel = val
  case "--cap": cap = Double(val) ?? cap
  default: die("unknown option \(key)")
  }
}

// Displays in CG global coordinates (points, top-left origin): the same space as kCGWindowBounds.
var count: UInt32 = 0
CGGetActiveDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetActiveDisplayList(count, &ids, &count)
let displays: [(id: CGDirectDisplayID, bounds: CGRect)] = ids.map { ($0, CGDisplayBounds($0)) }

struct Seen {
  var first: Double
  var last: Double
  var samples: Int
  var bounds: CGRect
  var display: Int
  var exact: Bool
  var cover: Double
  var layer: Int
}

let cid = CGSMainConnectionID()
var lastSpace = CGSGetActiveSpace(cid)
var spaceChanges = 0
var spacesSeen = [lastSpace]
var spaceLog: [(Double, Int)] = []
var windows: [Int: Seen] = [:]

let p = Process()
p.executableURL = URL(fileURLWithPath: binary)
p.arguments = ["/v:127.0.0.1:9", "/u:probe", "/p:not-a-secret", "/cert:ignore", "/log-level:\(logLevel)"]
var env = ProcessInfo.processInfo.environment
env.removeValue(forKey: "SDL_VIDEO_MAC_FULLSCREEN_SPACES")
if let s = spaces { env["SDL_VIDEO_MAC_FULLSCREEN_SPACES"] = s }
p.environment = env
if let path = logPath {
  FileManager.default.createFile(atPath: path, contents: nil)
  let fh = FileHandle(forWritingAtPath: path)!
  p.standardOutput = fh
  p.standardError = fh
} else {
  p.standardOutput = FileHandle.nullDevice
  p.standardError = FileHandle.nullDevice
}

let t0 = Date()
func ms() -> Double { Date().timeIntervalSince(t0) * 1000.0 }
try! p.run()
let pid = p.processIdentifier

var dialogAt: Double? = nil
var exitedAt: Double? = nil
var terminatedBy = "cap"
var polls = 0
while true {
  let t = ms()
  let now = CGSGetActiveSpace(cid)
  if now != lastSpace {
    spaceChanges += 1
    lastSpace = now
    spacesSeen.append(now)
    spaceLog.append((t, now))
  }
  if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
    for w in list {
      guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
            let num = w[kCGWindowNumber as String] as? Int,
            let bd = w[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
      var best = -1
      var bestCover = 0.0
      var exact = false
      for (i, d) in displays.enumerated() {
        let inter = rect.intersection(d.bounds)
        let cover = inter.isNull ? 0 : Double(inter.width * inter.height) / Double(d.bounds.width * d.bounds.height)
        if rect.integral == d.bounds.integral { exact = true; best = i; bestCover = 1.0; break }
        if cover > bestCover { bestCover = cover; best = i }
      }
      let layer = w[kCGWindowLayer as String] as? Int ?? 0
      if var s = windows[num] {
        s.last = t; s.samples += 1; s.bounds = rect; s.display = best
        s.exact = s.exact || exact; s.cover = max(s.cover, bestCover)
        windows[num] = s
      } else {
        windows[num] = Seen(first: t, last: t, samples: 1, bounds: rect, display: best,
                            exact: exact, cover: bestCover, layer: layer)
      }
      if dialogAt == nil && bestCover < 0.5 && rect.width > 200 && rect.height > 100 { dialogAt = t }
    }
  }
  if !p.isRunning && exitedAt == nil { exitedAt = t }
  if let e = exitedAt, t > e + 2000 { terminatedBy = "exited"; break }
  if let d = dialogAt, t > d + 1000 { terminatedBy = "dialog+1s"; break }
  if t > cap * 1000 { break }
  polls += 1
  usleep(2_000)
}
let loopMs = ms()
if p.isRunning {
  p.terminate()
  let until = Date().addingTimeInterval(2)
  while p.isRunning && Date() < until { usleep(10_000) }
  if p.isRunning { kill(pid, SIGKILL) }
}

let pollMs = loopMs / Double(max(polls, 1))
func fmt(_ r: CGRect) -> String { "\(Int(r.width))x\(Int(r.height))+\(Int(r.minX))+\(Int(r.minY))" }
print("binary=\(binary)")
print("SDL_VIDEO_MAC_FULLSCREEN_SPACES=\(spaces ?? "unset") end=\(terminatedBy) wall_ms=\(Int(ms()))")
for (i, d) in displays.enumerated() { print("display[\(i)] cg_id=\(d.id) bounds=\(fmt(d.bounds))") }
print(String(format: "poll_interval_ms=%.2f polls=%d", pollMs, polls))
print("space_changes=\(spaceChanges) spaces_seen=\(spacesSeen) space_log_ms=\(spaceLog.map { "\(Int($0.0)):\($0.1)" })")
let sorted = windows.sorted { $0.value.first < $1.value.first }
var exactCount = 0, near = 0, exactVisible = 0.0
for (num, s) in sorted {
  let vis = s.last - s.first + pollMs
  let kind = s.exact ? "COVERS-DISPLAY" : (s.cover >= 0.9 ? "covers>=90%" : "other")
  if s.exact { exactCount += 1; exactVisible += vis }
  if !s.exact && s.cover >= 0.9 { near += 1 }
  print("window #\(num) \(kind) display=\(s.display) bounds=\(fmt(s.bounds)) layer=\(s.layer) cover=\(String(format: "%.3f", s.cover)) first_ms=\(Int(s.first)) last_ms=\(Int(s.last)) samples=\(s.samples) visible_ms~\(Int(vis))")
}
print("SUMMARY display_covering_windows=\(exactCount) covering_visible_ms_total~\(Int(exactVisible)) near_covering_windows=\(near) all_windows=\(windows.count) space_changes=\(spaceChanges) dialog_ms=\(dialogAt.map { String(Int($0)) } ?? "none")")
