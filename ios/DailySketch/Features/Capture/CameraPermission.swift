import AVFoundation
import Foundation

enum CameraAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

protocol CameraAuthorizing: Sendable {
    var status: CameraAuthorizationStatus { get }
    var isCameraAvailable: Bool { get }
    func requestAccess() async -> Bool
}

struct SystemCameraAuthorizer: CameraAuthorizing {
    var status: CameraAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    var isCameraAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

final class FakeCameraAuthorizer: CameraAuthorizing, @unchecked Sendable {
    var status: CameraAuthorizationStatus
    var isCameraAvailable: Bool
    var requestAccessResult: Bool
    private(set) var requestAccessCallCount = 0

    init(
        status: CameraAuthorizationStatus = .authorized,
        isCameraAvailable: Bool = true,
        requestAccessResult: Bool = true
    ) {
        self.status = status
        self.isCameraAvailable = isCameraAvailable
        self.requestAccessResult = requestAccessResult
    }

    func requestAccess() async -> Bool {
        requestAccessCallCount += 1
        if requestAccessResult {
            status = .authorized
        } else {
            status = .denied
        }
        return requestAccessResult
    }
}
