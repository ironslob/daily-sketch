import XCTest
@testable import DailySketch

@MainActor
final class SubmissionDetailViewModelTests: XCTestCase {
    private func sampleSubmission(
        isOwner: Bool = true,
        liked: Bool = false,
        likeCount: Int = 2,
        reflectionCount: Int = 1
    ) -> SubmissionModel {
        SubmissionModel(
            id: UUID(),
            caption: "Quiet botanical lines for the page title check.",
            status: "published",
            timerMode: "countdown",
            timerSeconds: 600,
            likeCount: likeCount,
            reflectionCount: reflectionCount,
            viewerHasLiked: liked,
            isOwner: isOwner,
            imageURL: URL(string: "https://example.test/display")!,
            thumbnailURL: URL(string: "https://example.test/thumb")!,
            userId: UUID(),
            username: "alexdraws",
            displayName: "Alex Rivers",
            promptWords: ["Leaf", "Green", "Organic"],
            promptDate: Date(timeIntervalSince1970: 1_784_332_800),
            sketchSessionId: UUID(),
            publishedAt: Date()
        )
    }

    private func makeModel(
        submission: SubmissionModel,
        submissionService: RecordingSubmissionRepository = RecordingSubmissionRepository(),
        socialService: RecordingSocialRepository = RecordingSocialRepository(),
        isAuthenticated: @escaping () -> Bool = { true },
        accessTokenProvider: @escaping () -> String? = { "token" },
        onDeleted: (() -> Void)? = nil
    ) -> SubmissionDetailViewModel {
        submissionService.nextSubmission = submission
        return SubmissionDetailViewModel(
            submissionId: submission.id,
            submissionService: submissionService,
            socialService: socialService,
            isAuthenticated: isAuthenticated,
            accessTokenProvider: accessTokenProvider,
            onDeleted: onDeleted
        )
    }

    func testLoadSuccessUsesCaptionDerivedTitle() async {
        let submission = sampleSubmission()
        let model = makeModel(submission: submission)

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
        let submission = sampleSubmission(isOwner: true)
        let repo = RecordingSubmissionRepository()
        var deleted = false
        let model = makeModel(
            submission: submission,
            submissionService: repo,
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
        let submission = sampleSubmission()
        let repo = RecordingSubmissionRepository()
        let model = makeModel(
            submission: submission,
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
        let submission = sampleSubmission()
        let repo = RecordingSubmissionRepository()
        repo.deleteError = PublicationAPIError.underlying("network")
        let model = makeModel(
            submission: submission,
            submissionService: repo
        )
        await model.load()
        await model.deleteSubmission()

        XCTAssertEqual(repo.deleteCallCount, 1)
        XCTAssertEqual(model.deleteErrorMessage, "network")
        guard case .loaded = model.state else {
            return XCTFail("Submission should remain loaded after failed delete")
        }
    }

    func testOptimisticLikeAndRollbackOnFailure() async {
        let submission = sampleSubmission(liked: false, likeCount: 2)
        let social = RecordingSocialRepository()
        social.likeError = SocialAPIError.underlying("network")
        let model = makeModel(submission: submission, socialService: social)
        await model.load()

        await model.toggleLike()

        XCTAssertEqual(social.likeCallCount, 1)
        guard case .loaded(let loaded) = model.state else {
            return XCTFail("Expected loaded after rollback")
        }
        XCTAssertFalse(loaded.viewerHasLiked)
        XCTAssertEqual(loaded.likeCount, 2)
        XCTAssertEqual(model.likeErrorMessage, "network")
    }

    func testOptimisticLikeConfirmsServerState() async {
        let submission = sampleSubmission(liked: false, likeCount: 2)
        let social = RecordingSocialRepository()
        social.nextLikeState = LikeStateModel(liked: true, likeCount: 3)
        let model = makeModel(submission: submission, socialService: social)
        await model.load()

        await model.toggleLike()

        guard case .loaded(let loaded) = model.state else {
            return XCTFail("Expected loaded")
        }
        XCTAssertTrue(loaded.viewerHasLiked)
        XCTAssertEqual(loaded.likeCount, 3)
        XCTAssertNil(model.likeErrorMessage)
    }

    func testGuestLikeTriggersAuthCheckpointThenResumes() async {
        let submission = sampleSubmission()
        let social = RecordingSocialRepository()
        social.nextLikeState = LikeStateModel(liked: true, likeCount: 3)
        var authenticated = false
        let model = makeModel(
            submission: submission,
            socialService: social,
            isAuthenticated: { authenticated },
            accessTokenProvider: { authenticated ? "token" : nil }
        )
        await model.load()

        await model.toggleLike()
        XCTAssertEqual(social.likeCallCount, 0)
        XCTAssertEqual(model.pendingSocialAction, .like)
        XCTAssertTrue(model.showsAuthSheet)

        authenticated = true
        await model.handleAuthenticationCompleted()

        XCTAssertEqual(social.likeCallCount, 1)
        XCTAssertNil(model.pendingSocialAction)
        XCTAssertFalse(model.showsAuthSheet)
        guard case .loaded(let loaded) = model.state else {
            return XCTFail("Expected liked submission")
        }
        XCTAssertTrue(loaded.viewerHasLiked)
    }

    func testReflectionPostPreservesTextOnFailure() async {
        let submission = sampleSubmission(reflectionCount: 0)
        let social = RecordingSocialRepository()
        social.createError = SocialAPIError.underlying("offline")
        let model = makeModel(submission: submission, socialService: social)
        await model.load()
        model.composerText = "Keeping this reflection draft"

        await model.postReflection()

        XCTAssertEqual(social.createCallCount, 1)
        XCTAssertEqual(model.composerText, "Keeping this reflection draft")
        XCTAssertEqual(model.reflectionErrorMessage, "offline")
        guard case .loaded(let loaded) = model.state else {
            return XCTFail("Expected loaded")
        }
        XCTAssertEqual(loaded.reflectionCount, 0)
    }

    func testAuthorDeleteRemovesReflectionAndDecrementsCount() async {
        let submission = sampleSubmission(reflectionCount: 1)
        let social = RecordingSocialRepository()
        let reflection = ReflectionModel(
            id: UUID(),
            submissionId: submission.id,
            userId: UUID(),
            username: "alexdraws",
            displayName: "Alex Rivers",
            avatarURL: nil,
            body: "Nice work",
            createdAt: Date(),
            isAuthor: true
        )
        social.nextPage = ReflectionPage(items: [reflection], nextCursor: nil)
        let model = makeModel(submission: submission, socialService: social)
        await model.load()
        XCTAssertEqual(model.reflections.count, 1)

        await model.deleteReflection(reflection)

        XCTAssertEqual(social.deleteCallCount, 1)
        XCTAssertTrue(model.reflections.isEmpty)
        guard case .loaded(let loaded) = model.state else {
            return XCTFail("Expected loaded")
        }
        XCTAssertEqual(loaded.reflectionCount, 0)
    }
}
