import Foundation
import Observation

@Observable
@MainActor
final class DeleteAccountViewModel {
    private let accountDeleter: any AccountDeleting
    private let auth: AuthSessionStore
    private let draftStore: any DraftStoring
    private let draftImageStore: any DraftImageStoring

    var isDeleting = false
    var errorMessage: String?
    var didComplete = false

    init(
        accountDeleter: any AccountDeleting,
        auth: AuthSessionStore,
        draftStore: any DraftStoring,
        draftImageStore: any DraftImageStoring
    ) {
        self.accountDeleter = accountDeleter
        self.auth = auth
        self.draftStore = draftStore
        self.draftImageStore = draftImageStore
    }

    func confirmDeletion() async {
        guard let token = auth.accessToken else {
            errorMessage = "Sign in to delete your account."
            return
        }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await accountDeleter.deleteAccount(
                accessToken: token,
                idempotencyKey: UUID().uuidString
            )
            let drafts = (try? draftStore.list()) ?? []
            for draft in drafts {
                try? draftImageStore.delete(fileName: draft.imageFileName)
                try? draftStore.delete(id: draft.id)
            }
            await auth.signOut()
            didComplete = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
