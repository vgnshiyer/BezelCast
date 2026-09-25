@preconcurrency import AVFoundation
import AppKit
import CoreImage
import VideoToolbox
import XCTest
@testable import BezelCast

final class BezelRecorderTests: XCTestCase {
    func testLiveBezelChangesReachMovieWithoutChangingItsCanvas() async throws {
        try requireAlphaEncoder()
        let profile = DeviceProfile(id: "test-recorder", displayName: "Test", family: .iPhone,
                                    screenSize: CGSize(width: 180, height: 320), displayScale: 1,
                                    frameSize: CGSize(width: 180, height: 320), screenOffset: .zero,
                                    screenCornerRadius: 0, displayCutout: .none)
        let frame = try redFrame(profile: profile)
        let buffer = try blueBuffer(size: profile.screenSize)
        let renderer = BezelRenderer(ciContext: CIContext())

        // Exercise both a larger bezel entering a screen-only recording and
        // removing a bezel from a recording that started with a larger canvas.
        for startsFramed in [false, true] {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("BezelRecorderTests-\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let initialFrame = startsFramed ? frame : nil
            let outputSize = initialFrame?.geometry.frameSize ?? profile.screenSize
            let recorder = BezelRecorder(url: url, renderer: renderer, profile: profile,
                                          customFrame: initialFrame)
            let framedPhases = [startsFramed, !startsFramed, startsFramed]
            for phase in framedPhases.indices {
                recorder.setConfiguration(profile: profile,
                                          customFrame: framedPhases[phase] ? frame : nil)
                // Pace input so the writer can become ready, while allowing
                // occasional frame drops just as the live capture pipeline does.
                for index in 0..<10 {
                    recorder.receive(buffer: buffer,
                                     presentationTime: CMTime(value: Int64(phase * 30 + index), timescale: 30))
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
            }
            let finished = expectation(description: "Movie finishes encoding")
            let result = RecordingResult()
            recorder.stop { output in
                result.store(output)
                finished.fulfill()
            }
            await fulfillment(of: [finished], timeout: 10)
            let movie = try XCTUnwrap(result.read(), "An available encoder must finish the recording")
            try await verify(movie: movie, outputSize: outputSize, framedPhases: framedPhases)
        }
    }

    private func requireAlphaEncoder() throws {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: 180, height: 320,
                                                codecType: kCMVideoCodecType_HEVCWithAlpha,
                                                encoderSpecification: nil, imageBufferAttributes: nil,
                                                compressedDataAllocator: nil, outputCallback: nil,
                                                refcon: nil, compressionSessionOut: &session)
        if let session { VTCompressionSessionInvalidate(session) }
        guard status == noErr, session != nil else {
            throw XCTSkip("HEVC with alpha encoding is unavailable on this host (\(status))")
        }
    }

    private func redFrame(profile: DeviceProfile) throws -> CustomFrame {
        let geometry = FrameGeometry(frameSize: CGSize(width: 216, height: 384),
                                     screenRect: CGRect(x: 18, y: 32, width: 180, height: 320))
        let context = try XCTUnwrap(CGContext(data: nil, width: 216, height: 384,
                                             bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: geometry.frameSize))
        context.clear(geometry.screenRect)
        let image = try XCTUnwrap(context.makeImage())
        return try XCTUnwrap(CustomFrame.make(name: "Red test bezel",
                                              image: NSImage(cgImage: image, size: geometry.frameSize),
                                              cgImage: image, geometry: geometry, profile: profile))
    }

    private func blueBuffer(size: CGSize) throws -> CVPixelBuffer {
        var optional: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                          kCVPixelFormatType_32BGRA, nil, &optional)
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(optional)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                let offset = y * stride + x * 4
                bytes[offset] = 255
                bytes[offset + 1] = 0
                bytes[offset + 2] = 0
                bytes[offset + 3] = 255
            }
        }
        return buffer
    }

    private func verify(movie: URL, outputSize: CGSize, framedPhases: [Bool]) async throws {
        let asset = AVURLAsset(url: movie)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track,
                                              outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                                               kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var samplesPerPhase = [Int](repeating: 0, count: framedPhases.count)
        while let sample = output.copyNextSampleBuffer() {
            let phase = Int(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            XCTAssertTrue(framedPhases.indices.contains(phase))
            guard framedPhases.indices.contains(phase) else { continue }
            samplesPerPhase[phase] += 1
            let buffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            XCTAssertEqual(CVPixelBufferGetWidth(buffer), Int(outputSize.width))
            XCTAssertEqual(CVPixelBufferGetHeight(buffer), Int(outputSize.height))
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
            let middleRow = Int(outputSize.height) / 2 * CVPixelBufferGetBytesPerRow(buffer)
            let border = middleRow + 4 * 4
            let center = middleRow + Int(outputSize.width) / 2 * 4
            // Sample well inside solid regions to avoid chroma edge artifacts.
            XCTAssertGreaterThan(bytes[center], 220, "Screen stays blue in phase \(phase)")
            XCTAssertLessThan(bytes[center + 2], 35)
            if framedPhases[phase] {
                XCTAssertGreaterThan(bytes[border + 2], 220, "Updated red bezel reaches phase \(phase)")
                XCTAssertLessThan(bytes[border], 35)
            } else {
                XCTAssertGreaterThan(bytes[border], 220, "Removing bezel restores blue screen in phase \(phase)")
                XCTAssertLessThan(bytes[border + 2], 35)
            }
        }
        XCTAssertEqual(reader.status, .completed, "\(String(describing: reader.error))")
        XCTAssertTrue(samplesPerPhase.allSatisfy { $0 > 0 }, "Every selection needs decoded evidence: \(samplesPerPhase)")
    }

    private final class RecordingResult: @unchecked Sendable {
        private let lock = NSLock()
        private var url: URL?

        func store(_ url: URL?) {
            lock.lock(); defer { lock.unlock() }
            self.url = url
        }

        func read() -> URL? {
            lock.lock(); defer { lock.unlock() }
            return url
        }
    }
}
