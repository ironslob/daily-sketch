import XCTest
@testable import DailySketch

@MainActor
final class SubmissionDetailViewModelTests: XCTestCase {
    private func sampleSubmission(isOwner: Bool = true) -> SubmissionModel {
        SubmissionModel(
            id: UUID(),
            caption: "Quiet botanical lines for the page title check.",
            status: "published",
            timerMode: "countdown",
            timerSeconds: 600,
            likeCount: 2,
            reflectionCount: 1,
            viewerHasLiked: false,
            isOwner: isOwner,
            imageURL: URL(string: "https://example.test/display")!,
            thumbnailURL: URL(string: "https://example.test/thumb")!,
            username: "alexdraws",
            displayName: "Alex Rivers",
            promptWords: ["Leaf", "Green", "Organic"],
            promptDate: Date(timeIntervalSince1970: 1_784_332_800),
            sketchSessionId: UUID(),
            publishedAt: Date()
        )
    }

    func testLoadSuccessUsesCaptionDerivedTitle() async {
        let repo = RecordingSubmissionRepository()
        let submission = sampleSubmission()
        repo.nextSubmission = submission
        let model = SubmissionDetailViewModel(
            submissionId: submission.id,
            submissionService: repo,
            accessTokenProvider: { "token" }
        )

        await model.load()

        guard case .loaded(let loaded) = model.state else {
            return XCTFail("Expected loaded submission")
        }
        XCTAssertEqual(loaded.id, submission.id)
        XCTAssertEqual(model.timerLabel, "10 min")
        XCTAssertTrue(model.navigationTitle.hasPrefix("Quiet botanical lines"))
        XCTAssertTrue(model.navigationTitle.hasSuffix("…"))
        XCTAssertTrue(model.isOwner)
    }

    func testDeleteSubmissionSucceedsAndInvokesCallback() async {
        let repo = RecordingSubmissionRepository()
        let submission = sampleSubmission(isOwner: true)
        repo.nextSubmission = submission
        var deleted = false
        let model = SubmissionDetailViewModel(
            submissionId: submission.id,
            submissionService: repo,
            accessTokenProvider: { "token" },
            onDeleted: { deleted = true }
        )
        await model.load()
        await model.deleteSubmission()

        XCTAssertEqual(repo.deleteCallCount, 1)
        XCTAssertEqual(repo.lastDeletedSubmissionId, submission.id)
        XCTAssertEqual(model.state, .deleted)
        XCTAssertTrue(deleted)
    }

    func testDeleteWithoutTokenSurfacesError() async {
        let repo = RecordingSubmissionRepository()
        let submission = sampleSubmission()
        repo.nextSubmission = submission
        let model = SubmissionDetailViewModel(
            submissionId: submission.id,
            submissionService: repo,
            accessTokenProvider: { nil }
        )
        await model.load()
        await model.deleteSubmission()

        XCTAssertEqual(repo.deleteCallCount, 0)
        XCTAssertEqual(model.deleteErrorMessage, "Sign in to delete this sketch.")
        guard case .loaded = model.state else {
            return XCTFail("Submission should remain loaded")
        }
    }

    func testDeleteFailurePreservesSubmission() async {
        let repo = RecordingSubmissionRepository()
        let submission = sampleSubmission()
        repo.nextSubmission = submission
        repo.deleteError = PublicationAPIError.underlying("network")
        let model = SubmissionDetailViewModel(
            submissionId: submission.id,
            submissionService: repo,
            accessTokenProvider: { "token" }
        )
        await model.load()
        await model.deleteSubmission()

        XCTAssertEqual(repo.deleteCallCount, 1)
        XCTAssertEqual(model.deleteErrorMessage, "network")
        guard case .loaded = model.state else {
            return XCTFail("Submission should remain loaded after failed delete")
        }
    }
}
