import Foundation
import Observation

@Observable
@MainActor
final class BlockedUsersViewModel {
    enum State: Equatable {
        case loading
        case empty
        case loaded
        case failed(String)
    }

    private let safetyService: any SafetyServing
    private let accessTokenProvider: () -> String?

    var state: State = .loading
    var users: [BlockedUserModel] = []
    var actionError: String?

    init(
        safetyService: any SafetyServing,
        accessTokenProvider: @escaping () -> String?
    ) {
        self.safetyService = safetyService
        self.accessTokenProvider = accessTokenProvider
    }

    func load() async {
        guard let token = accessTokenProvider() else {
            state = .failed("Sign in to manage blocked users.")
            return
        }
        state = .loading
        do {
            users = try await safetyService.listBlockedUsers(accessToken: token)
            state = users.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func unblock(_ user: BlockedUserModel) async {
        guard let token = accessTokenProvider() else { return }
        actionError = nil
        do {
            _ = try await safetyService.unblockUser(accessToken: token, userId: user.id)
            users.removeAll { $0.id == user.id }
            state = users.isEmpty ? .empty : .loaded
        } catch {
            actionError = error.localizedDescription
        }
    }
}
