import XCTest
@testable import DailySketch

@MainActor
final class ReportViewModelTests: XCTestCase {
    func testSubmitReportSuccessOffersBlockWhenUserIdPresent() async {
        let safety = RecordingSafetyRepository()
        let targetId = UUID()
        let blockable = UUID()
        let model = ReportViewModel(
            targetType: .submission,
            targetId: targetId,
            blockableUserId: blockable,
            safetyService: safety,
            accessTokenProvider: { "token" }
        )
        model.selectedReason = .spam
        await model.submit()

        XCTAssertEqual(safety.reportCallCount, 1)
        XCTAssertEqual(safety.lastReportTargetId, targetId)
        XCTAssertTrue(model.offeredBlockAfterReport)
        if case .success = model.phase {
            // ok
        } else {
            XCTFail("Expected success phase, got \(model.phase)")
        }
    }

    func testOtherReasonRequiresNotes() async {
        let model = ReportViewModel(
            targetType: .reflection,
            targetId: UUID(),
            safetyService: RecordingSafetyRepository(),
            accessTokenProvider: { "token" }
        )
        model.selectedReason = .other
        XCTAssertFalse(model.canSubmit)
        model.notes = "Harmful reply"
        XCTAssertTrue(model.canSubmit)
    }
}

@MainActor
final class BlockSafetyViewModelTests: XCTestCase {
    func testBlockAuthorRemovesContentAndInvokesCallback() async {
        let safety = RecordingSafetyRepository()
        let submissions = RecordingSubmissionRepository()
        let authorId = UUID()
        let submission = SubmissionModel(
            id: UUID(),
            caption: nil,
            status: "published",
            timerMode: "no_timer",
            timerSeconds: nil,
            likeCount: 0,
            reflectionCount: 0,
            viewerHasLiked: false,
            isOwner: false,
            imageURL: URL(string: "https://example.test/d")!,
            thumbnailURL: URL(string: "https://example.test/t")!,
            userId: authorId,
            username: "blocked",
            displayName: "Blocked",
            promptWords: ["A", "B", "C"],
            promptDate: Date(),
            sketchSessionId: UUID(),
            publishedAt: Date()
        )
        submissions.nextSubmission = submission
        var blockedUserId: UUID?
        let model = SubmissionDetailViewModel(
            submissionId: submission.id,
            submissionService: submissions,
            socialService: RecordingSocialRepository(),
            safetyService: safety,
            accessTokenProvider: { "token" },
            onBlockedUser: { blockedUserId = $0 }
        )
        await model.load()
        await model.blockAuthor(userId: authorId)

        XCTAssertEqual(safety.blockCallCount, 1)
        XCTAssertEqual(safety.lastBlockedUserId, authorId)
        XCTAssertEqual(blockedUserId, authorId)
        XCTAssertTrue(model.didBlockAuthor)
        if case .deleted = model.state {
            // ok
        } else {
            XCTFail("Expected deleted state after block")
        }
    }
}

@MainActor
final class DeleteAccountViewModelTests: XCTestCase {
    func testDeleteAccountSignsOut() async {
        let safety = RecordingSafetyRepository()
        let me = RecordingMeFetcher(
            profile: CurrentUserProfile(
                id: UUID(),
                username: "deleteme",
                displayName: "Delete Me",
                profileCompleted: true,
                status: "active"
            )
        )
        let auth = AuthSessionStore(
            authService: MockAuthService(),
            meFetcher: me,
            profileUpdater: me
        )
        await auth.signIn(displayName: "Delete Me")
        XCTAssertTrue(auth.isAuthenticated)

        let model = DeleteAccountViewModel(
            accountDeleter: safety,
            auth: auth,
            draftStore: InMemoryDraftStore(),
            draftImageStore: InMemoryDraftImageStore()
        )
        await model.confirmDeletion()
        XCTAssertEqual(safety.deleteAccountCallCount, 1)
        XCTAssertTrue(model.didComplete)
        XCTAssertFalse(auth.isAuthenticated)
    }
}
