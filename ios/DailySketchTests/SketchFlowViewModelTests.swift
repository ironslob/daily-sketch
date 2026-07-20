import UIKit
import XCTest
@testable import DailySketch

@MainActor
final class SketchFlowViewModelTests: XCTestCase {
    private let prompt = DailyPromptModel(
        id: UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-ef1234567890")!,
        promptDate: Date(timeIntervalSince1970: 1_784_332_800),
        word1: "Chocolate",
        word2: "Coffee",
        word3: "Banana",
        status: "published",
        publishedAt: Date(timeIntervalSince1970: 1_784_246_400)
    )

    private func makeFlow(
        guestStore: InMemoryGuestTimerPreferenceStore = InMemoryGuestTimerPreferenceStore(),
        activeStore: InMemoryActiveSessionStore = InMemoryActiveSessionStore(),
        draftStore: InMemoryDraftStore = InMemoryDraftStore(),
        imageStore: InMemoryDraftImageStore = InMemoryDraftImageStore(),
        camera: FakeCameraAuthorizer = FakeCameraAuthorizer()
    ) -> SketchFlowViewModel {
        let profile = CurrentUserProfile(
            id: UUID(),
            username: nil,
            displayName: "Guest",
            profileCompleted: false,
            status: "incomplete"
        )
        let auth = AuthSessionStore(
            authService: MockAuthService(),
            meFetcher: RecordingMeFetcher(profile: profile)
        )
        return SketchFlowViewModel(
            auth: auth,
            preferencesService: RecordingMeFetcher(profile: profile),
            guestTimerStore: guestStore,
            activeSessionStore: activeStore,
            sessionService: RecordingSketchSessionRepository(),
            draftStore: draftStore,
            imageStore: imageStore,
            cameraAuthorizer: camera
        )
    }

    func testSheetAppearsByDefault() async {
        let flow = makeFlow()
        flow.startSketch(prompt: prompt)

        let deadline = Date().addingTimeInterval(1)
        while !flow.showsTimerSelection, Date() < deadline {
            await Task.yield()
        }

        XCTAssertTrue(flow.showsTimerSelection)
        XCTAssertFalse(flow.showsActiveSession)
    }

    func testRememberedTimerBypassesSheet() async {
        let guestStore = InMemoryGuestTimerPreferenceStore()
        guestStore.save(.threeMinutes)
        let flow = makeFlow(guestStore: guestStore)

        flow.startSketch(prompt: prompt)

        let deadline = Date().addingTimeInterval(1)
        while !flow.showsActiveSession, Date() < deadline {
            await Task.yield()
        }

        XCTAssertFalse(flow.showsTimerSelection)
        XCTAssertTrue(flow.showsActiveSession)
        XCTAssertEqual(flow.sessionViewModel?.timerOption, .threeMinutes)
        XCTAssertTrue(flow.changeTimerHintVisible)
    }

    func testNoTimerCanBeRemembered() async {
        let guestStore = InMemoryGuestTimerPreferenceStore()
        let flow = makeFlow(guestStore: guestStore)
        flow.selectedTimerOption = .noTimer
        flow.rememberChoice = true
        flow.confirmTimerSelection(prompt: prompt)

        let deadline = Date().addingTimeInterval(1)
        while !flow.showsActiveSession, Date() < deadline {
            await Task.yield()
        }

        XCTAssertEqual(guestStore.load(), .noTimer)
        XCTAssertEqual(flow.sessionViewModel?.timerOption, .noTimer)
    }

    func testCaptureCreatesDraftAndOpensReview() async throws {
        let draftStore = InMemoryDraftStore()
        let imageStore = InMemoryDraftImageStore()
        let flow = makeFlow(draftStore: draftStore, imageStore: imageStore)
        flow.selectedTimerOption = .oneMinute
        flow.confirmTimerSelection(prompt: prompt)

        let started = Date().addingTimeInterval(1)
        while flow.sessionViewModel == nil, Date() < started {
            await Task.yield()
        }
        guard let session = flow.sessionViewModel else {
            return XCTFail("Expected active session")
        }

        session.finish()
        let captureDeadline = Date().addingTimeInterval(1)
        while !flow.showsCaptureSource, Date() < captureDeadline {
            await Task.yield()
        }
        XCTAssertTrue(flow.showsCaptureSource)

        let jpeg = makeTestJPEGData()
        flow.handleCapturedImageData(jpeg)

        XCTAssertTrue(flow.showsReviewSubmission)
        XCTAssertNotNil(flow.reviewViewModel)
        XCTAssertEqual(try draftStore.list().count, 1)
        let draft = try draftStore.list()[0]
        XCTAssertTrue(imageStore.contains(draft.imageFileName))
    }

    func testContinueLaterReturnsHomeWithDraft() async throws {
        let draftStore = InMemoryDraftStore()
        let imageStore = InMemoryDraftImageStore()
        let flow = makeFlow(draftStore: draftStore, imageStore: imageStore)
        flow.selectedTimerOption = .oneMinute
        flow.confirmTimerSelection(prompt: prompt)

        let started = Date().addingTimeInterval(1)
        while flow.sessionViewModel == nil, Date() < started {
            await Task.yield()
        }
        flow.sessionViewModel?.finish()
        let captureDeadline = Date().addingTimeInterval(1)
        while !flow.showsCaptureSource, Date() < captureDeadline {
            await Task.yield()
        }
        flow.handleCapturedImageData(makeTestJPEGData())

        flow.handleReviewOutcome(.needsAuthentication)
        XCTAssertTrue(flow.showsSaveYourCreativity)

        flow.continueLaterFromCreativity()
        XCTAssertFalse(flow.showsReviewSubmission)
        XCTAssertFalse(flow.showsSaveYourCreativity)
        XCTAssertNotNil(flow.recoverableDraft)
        XCTAssertEqual(try draftStore.list().count, 1)
    }

    func testDiscardRemovesLocalFile() throws {
        let draftStore = InMemoryDraftStore()
        let imageStore = InMemoryDraftImageStore()
        let flow = makeFlow(draftStore: draftStore, imageStore: imageStore)
        let fileName = try imageStore.write(makeTestJPEGData())
        let draft = LocalDraft(
            id: UUID(),
            localSessionId: UUID(),
            serverSessionId: nil,
            promptId: prompt.id,
            promptWords: prompt.words,
            promptAccessibilityLabel: prompt.accessibilityLabel,
            promptDate: prompt.promptDate,
            timerMode: "countdown",
            selectedTimerSeconds: 60,
            sessionStartedAt: Date(),
            imageFileName: fileName,
            caption: "keep me",
            createdAt: Date(),
            updatedAt: Date(),
            pendingAuthentication: true,
            pendingPublication: false
        )
        try draftStore.save(draft)
        flow.refreshDraftState()

        flow.discardDraft(draft)

        XCTAssertTrue(try draftStore.list().isEmpty)
        XCTAssertFalse(imageStore.contains(fileName))
        XCTAssertNil(flow.recoverableDraft)
    }

    func testCameraPermissionDeniedStillOffersLibrary() {
        let camera = FakeCameraAuthorizer(status: .denied, isCameraAvailable: false)
        let flow = makeFlow(camera: camera)
        XCTAssertEqual(flow.cameraAuthorizerForCapture.status, .denied)
        XCTAssertFalse(flow.cameraAuthorizerForCapture.isCameraAvailable)
    }

    func testPublishedOutcomeDeletesDraftAndRecordsSubmissionId() throws {
        let draftStore = InMemoryDraftStore()
        let imageStore = InMemoryDraftImageStore()
        let fileName = try imageStore.write(makeTestJPEGData())
        let draft = LocalDraft(
            id: UUID(),
            localSessionId: UUID(),
            serverSessionId: UUID(),
            promptId: prompt.id,
            promptWords: prompt.words,
            promptAccessibilityLabel: prompt.accessibilityLabel,
            promptDate: prompt.promptDate,
            timerMode: "countdown",
            selectedTimerSeconds: 180,
            sessionStartedAt: Date(),
            imageFileName: fileName,
            caption: "shipped",
            createdAt: Date(),
            updatedAt: Date(),
            pendingAuthentication: false,
            pendingPublication: true
        )
        try draftStore.save(draft)
        let flow = makeFlow(draftStore: draftStore, imageStore: imageStore)
        flow.reopenDraft(draft)
        XCTAssertTrue(flow.showsReviewSubmission)

        let submission = SubmissionModel(
            id: UUID(),
            caption: "shipped",
            status: "published",
            timerMode: "countdown",
            timerSeconds: 180,
            likeCount: 0,
            reflectionCount: 0,
            viewerHasLiked: false,
            isOwner: true,
            imageURL: URL(string: "https://example.test/display")!,
            thumbnailURL: URL(string: "https://example.test/thumb")!,
            userId: UUID(),
            username: "sketchy",
            displayName: "Sketcher",
            promptWords: prompt.words,
            promptDate: prompt.promptDate,
            sketchSessionId: draft.serverSessionId!,
            publishedAt: Date()
        )
        flow.handleReviewOutcome(.published(submission))

        XCTAssertTrue(try draftStore.list().isEmpty)
        XCTAssertFalse(imageStore.contains(fileName))
        XCTAssertFalse(flow.showsReviewSubmission)
        XCTAssertEqual(flow.lastPublishedSubmissionId, submission.id)
        XCTAssertNil(flow.reviewViewModel)
    }

    private func makeTestJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }
}
