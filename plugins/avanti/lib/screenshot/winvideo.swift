// winvideo <window-id> <client.log> <ack-file> <shot-index> <out.mp4> <width> <height> [out.gif]
//
// Lockstep video capture for avanti_camera: waits for "[avanti_camera] VIDEO <idx> <frames> <fps> <name>"
// in the log, then for each "[avanti_camera] FRAME <k>" captures the window, crops off the title bar
// and rounded corners (like cropbottom), scales to width x height, appends the frame to an H.264 MP4
// (and every n-th frame to a 600 px GIF at <= 15 fps), and writes k to the ack file so the mod moves
// the camera on. Exits 0 after the last frame, 1 on errors or when nothing happens for 60 s.
import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count >= 8, let wid = UInt32(a[1]), let width = Int(a[6]), let height = Int(a[7]) else {
	FileHandle.standardError.write("usage: winvideo <wid> <log> <ack> <idx> <out.mp4> <w> <h> [out.gif]\n".data(using: .utf8)!)
	exit(2)
}
let logPath = a[2], ackPath = a[3], idx = a[4], outPath = a[5]
let gifPath = a.count > 8 && !a[8].isEmpty ? a[8] : nil

func fail(_ msg: String) -> Never {
	FileHandle.standardError.write("winvideo: \(msg)\n".data(using: .utf8)!)
	exit(1)
}

// ------------------------------------------------------------------ window capture

_ = NSApplication.shared // connects to the window server; ScreenCaptureKit asserts without it

var captureWindow: () async throws -> CGImage

if #available(macOS 14.0, *) {
	let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
	guard let win = content.windows.first(where: { $0.windowID == wid }) else { fail("window \(wid) not found") }
	let filter = SCContentFilter(desktopIndependentWindow: win)
	let cfg = SCStreamConfiguration()
	cfg.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
	cfg.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
	cfg.showsCursor = false
	cfg.ignoreShadowsSingleWindow = true
	captureWindow = { try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) }
} else {
	let tmp = NSTemporaryDirectory() + "winvideo-\(getpid()).png"
	captureWindow = {
		let p = Process()
		p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
		p.arguments = ["-x", "-o", "-l\(wid)", tmp]
		try p.run()
		p.waitUntilExit()
		guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: tmp) as CFURL, nil),
			let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
		else { throw NSError(domain: "winvideo", code: 1) }
		return img
	}
}

// Keep the bottom-left client area minus an 18 pt inset (title bar, rounded corners), aspect preserved.
func crop(_ img: CGImage) -> CGImage {
	let scale = CGFloat(img.width) / CGFloat(width)
	let inset = 18 * scale
	let cw = (CGFloat(width) - 36) * scale
	let ch = cw * CGFloat(height) / CGFloat(width)
	return img.cropping(to: CGRect(x: inset, y: CGFloat(img.height) - ch - inset, width: cw, height: ch).integral) ?? img
}

func draw(_ img: CGImage, into ctx: CGContext, _ w: Int, _ h: Int) {
	ctx.interpolationQuality = .high
	ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
}

// ------------------------------------------------------------------ log follower

var logOffset: UInt64 = 0
var partial = ""

func newLogLines() -> [String] {
	guard let fh = FileHandle(forReadingAtPath: logPath) else { return [] }
	defer { try? fh.close() }
	try? fh.seek(toOffset: logOffset)
	let data = fh.readDataToEndOfFile()
	logOffset += UInt64(data.count)
	var lines = (partial + String(decoding: data, as: UTF8.self)).components(separatedBy: "\n")
	partial = lines.removeLast()
	return lines
}

func fields(after marker: String, in line: String) -> [String]? {
	guard let r = line.range(of: marker) else { return nil }
	return line[r.upperBound...].split(separator: " ", maxSplits: 3).map(String.init)
}

// ------------------------------------------------------------------ encoders

var writer: AVAssetWriter!
var input: AVAssetWriterInput!
var adaptor: AVAssetWriterInputPixelBufferAdaptor!
var gif: CGImageDestination?
var gifStep = 1, gifW = 600, gifH = 400
var frames = -1, fps = 30, next = 0, duplicates = 0
var lastHash: UInt64 = 0

func start(_ f: Int, _ r: Int) {
	frames = f
	fps = max(1, r)
	try? FileManager.default.removeItem(atPath: outPath)
	do { writer = try AVAssetWriter(outputURL: URL(fileURLWithPath: outPath), fileType: .mp4) } catch { fail("\(error)") }
	input = AVAssetWriterInput(mediaType: .video, outputSettings: [
		AVVideoCodecKey: AVVideoCodecType.h264,
		AVVideoWidthKey: width,
		AVVideoHeightKey: height,
		AVVideoCompressionPropertiesKey: [
			AVVideoAverageBitRateKey: width * height * 3, // ~4.5 Mbit/s at 1500x1000
			AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
		],
	])
	input.expectsMediaDataInRealTime = false
	adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
		kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
		kCVPixelBufferWidthKey as String: width,
		kCVPixelBufferHeightKey as String: height,
	])
	writer.add(input)
	guard writer.startWriting() else { fail("can't write \(outPath): \(String(describing: writer.error))") }
	writer.startSession(atSourceTime: .zero)
	if let gifPath {
		gifStep = max(1, Int((Double(fps) / 15).rounded()))
		gifH = gifW * height / width
		gif = CGImageDestinationCreateWithURL(URL(fileURLWithPath: gifPath) as CFURL, UTType.gif.identifier as CFString,
			(frames - 1) / gifStep + 1, nil)
		CGImageDestinationSetProperties(gif!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
	}
}

func append(_ k: Int, _ img: CGImage) {
	while !input.isReadyForMoreMediaData { usleep(2000) }
	var pb: CVPixelBuffer?
	CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
	guard let buf = pb else { fail("no pixel buffer") }
	CVPixelBufferLockBaseAddress(buf, [])
	let base = CVPixelBufferGetBaseAddress(buf)!
	let bpr = CVPixelBufferGetBytesPerRow(buf)
	let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
		space: CGColorSpace(name: CGColorSpace.sRGB)!,
		bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
	draw(img, into: ctx, width, height)
	// Cheap fingerprint to spot frames where the client hadn't rendered the new camera yet.
	var hash: UInt64 = 1469598103934665603
	let bytes = base.assumingMemoryBound(to: UInt8.self)
	for i in stride(from: 0, to: bpr * height, by: 4093) { hash = (hash ^ UInt64(bytes[i])) &* 1099511628211 }
	if k > 0 && hash == lastHash { duplicates += 1 }
	lastHash = hash
	CVPixelBufferUnlockBaseAddress(buf, [])
	adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(k), timescale: CMTimeScale(fps)))
	if let gif, k % gifStep == 0 {
		let g = CGContext(data: nil, width: gifW, height: gifH, bitsPerComponent: 8, bytesPerRow: 0,
			space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
		draw(img, into: g, gifW, gifH)
		CGImageDestinationAddImage(gif, g.makeImage()!, [kCGImagePropertyGIFDictionary:
			[kCGImagePropertyGIFDelayTime: Double(gifStep) / Double(fps)]] as CFDictionary)
	}
}

// ------------------------------------------------------------------ main loop

var idle = Date()
while true {
	for line in newLogLines() {
		if frames < 0, let f = fields(after: "[avanti_camera] VIDEO ", in: line), f.count >= 3, f[0] == idx {
			start(Int(f[1]) ?? 1, Int(f[2]) ?? 30)
		} else if frames >= 0, let f = fields(after: "[avanti_camera] FRAME ", in: line), let k = Int(f.first ?? ""), k == next {
			append(k, crop(try await captureWindow()))
			try? "\(k)\n".write(toFile: ackPath, atomically: true, encoding: .utf8)
			next += 1
			idle = Date()
		}
	}
	if frames >= 0 && next >= frames { break }
	if Date().timeIntervalSince(idle) > 60 { fail("no frame for 60 s (got \(next) of \(max(frames, 0)))") }
	usleep(5000)
}

input.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else { fail("encoding failed: \(String(describing: writer.error))") }
if let gif, !CGImageDestinationFinalize(gif) { fail("GIF encoding failed") }
if duplicates > 0 { print("duplicates \(duplicates)") }
