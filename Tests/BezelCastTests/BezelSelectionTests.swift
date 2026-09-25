import AppKit
import XCTest
@testable import BezelCast

@MainActor
final class BezelSelectionTests: XCTestCase {
    func testAutomaticAppliesAFrameWithoutImporting() async throws {
        try await withCapture { capture, _ in
            try await waitUntil { capture.customFrame != nil }
            XCTAssertEqual(capture.selectedBezelID, "automatic")
            XCTAssertEqual(capture.customFrameName, "iPhone 18 Pro Max · Black")
        }
    }

    func testLatestChoiceWinsDuringRapidSwitchesAndRotation() async throws {
        try await withCapture { capture, _ in
            capture.handleFrameSize(CGSize(width: 1320, height: 2868))
            capture.selectBezel("iphone-17-pro/cosmic-orange")
            capture.selectBezel("iphone-air/sky-blue")
            capture.handleFrameSize(CGSize(width: 2868, height: 1320))
            try await waitUntil { capture.customFrameName == "iPhone Air · Sky Blue" }
            XCTAssertEqual(capture.profile.id, "iphone-air")
            XCTAssertTrue(capture.profile.isLandscape)
            XCTAssertEqual(capture.customFrame?.geometry.screenRect.size, capture.profile.screenSize)

            capture.selectBezel("iphone-18-pro/silver")
            capture.selectBezel("none")
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(capture.selectedBezelID, "none")
            XCTAssertNil(capture.customFrame)
            XCTAssertNil(capture.customFrameName)
        }
    }

    func testModelCanSwitchBackBeforeFirstChoiceFinishesLoading() async throws {
        try await withCapture { capture, _ in
            try await waitUntil { capture.customFrame != nil }
            let first = capture.profile
            let second = try XCTUnwrap(DeviceProfile.catalog.first { $0.id == "iphone-air" })
            capture.selectProfile(second)
            capture.selectProfile(first)
            try await waitUntil { capture.customFrameName == "\(first.displayName) · Black" }
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(capture.profile.id, first.id)
        }
    }

    func testSavedBezelRestoresAndIncompatibleDeviceFallsBackToAutomatic() async throws {
        try await withCapture { capture, defaults in
            capture.selectBezel("iphone-air/cloud-white")
            let restored = DeviceCapture(preferences: defaults, startCapture: false)
            try await waitUntil { restored.customFrameName == "iPhone Air · Cloud White" }
            XCTAssertEqual(restored.selectedBezelID, "iphone-air/cloud-white")
            restored.handleFrameSize(CGSize(width: 750, height: 1334))
            try await waitUntil { restored.profile.id == "iphone-se" }
            XCTAssertEqual(restored.selectedBezelID, "automatic")
            XCTAssertEqual(restored.customFrameName, "iPhone SE · Midnight")
        }
    }

    func testDeviceFamiliesRememberIndependentPreferences() async throws {
        try await withCapture { capture, _ in
            capture.selectBezel("none")
            capture.handleFrameSize(CGSize(width: 2064, height: 2752))
            try await waitUntil { capture.profile.family == .iPad }
            XCTAssertEqual(capture.selectedBezelID, "automatic")
            capture.selectBezel("ipad-pro-13/silver")
            capture.handleFrameSize(CGSize(width: 1320, height: 2868))
            XCTAssertEqual(capture.selectedBezelID, "none")
            XCTAssertNil(capture.customFrame)
        }
    }

    func testRemovedGenericFinishMigratesToReleasedFinishOnSameModel() async throws {
        try await withCapture { _, defaults in
            defaults.set("iphone-17-pro/copper", forKey: "BezelCast.bezel.iphone")
            let restored = DeviceCapture(preferences: defaults, startCapture: false)
            try await waitUntil { restored.customFrameName == "iPhone 17 Pro · Silver" }
            XCTAssertEqual(restored.selectedBezelID, "iphone-17-pro/silver")
            XCTAssertEqual(restored.profile.id, "iphone-17-pro")
            XCTAssertEqual(defaults.string(forKey: "BezelCast.bezel.iphone"), "iphone-17-pro/silver")
        }
    }

    func testModelSwitchKeepsOnlyFinishesReleasedForTheNextModel() async throws {
        try await withCapture { capture, _ in
            capture.selectBezel("iphone-13-pro/graphite")
            let pro17 = try XCTUnwrap(DeviceProfile.catalog.first { $0.id == "iphone-17-pro" })
            capture.selectProfile(pro17)
            try await waitUntil { capture.customFrameName == "iPhone 17 Pro · Silver" }
            XCTAssertEqual(capture.selectedBezelID, "iphone-17-pro/silver")

            // Silver exists on both these models and can carry over unchanged.
            let pro18 = try XCTUnwrap(DeviceProfile.catalog.first { $0.id == "iphone-18-pro" })
            capture.selectProfile(pro18)
            try await waitUntil { capture.customFrameName == "iPhone 18 Pro · Silver" }
            XCTAssertEqual(capture.selectedBezelID, "iphone-18-pro/silver")
            capture.selectBezel("iphone-18-pro/copper")
            XCTAssertEqual(capture.selectedBezelID, "iphone-18-pro/silver")
        }
    }

    func testImportedFrameUsesItsOwnGeometryAndCanBeReselected() async throws {
        try await withCapture { capture, _ in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID()).png")
            defer { try? FileManager.default.removeItem(at: url) }
            let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 160,
                                                  bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 160))
            context.clear(CGRect(x: 20, y: 30, width: 46, height: 100))
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
            capture.loadCustomFrame(from: url)
            XCTAssertNil(capture.customFrameError)
            XCTAssertTrue(capture.hasImportedFrame)
            XCTAssertEqual(capture.selectedBezelID, "custom")
            XCTAssertEqual(capture.customFrame?.geometry.frameSize, CGSize(width: 100, height: 160))
            let name = capture.customFrameName
            capture.selectBezel("none")
            capture.selectBezel("custom")
            XCTAssertEqual(capture.customFrameName, name)
            XCTAssertNotNil(capture.customFrame)

            // Opaque files must not be accepted just because their canvas has a matching aspect.
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 160))
            let opaque = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
            try XCTUnwrap(opaque.representation(using: .png, properties: [:])).write(to: url)
            capture.loadCustomFrame(from: url)
            XCTAssertNotNil(capture.customFrameError)
            XCTAssertEqual(capture.customFrameName, name)
            XCTAssertEqual(capture.selectedBezelID, "custom")
        }
    }

    private func withCapture(_ body: (DeviceCapture, UserDefaults) async throws -> Void) async throws {
        let suite = "BezelCastTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let capture = DeviceCapture(preferences: defaults, startCapture: false)
        try await body(capture, defaults)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "Bezel did not finish loading")
    }
}
