import DescopeKit
import SwiftUI
import UIKit

/// Hosts a Descope Flow for sign-up / sign-in when a real project ID is configured.
struct DescopeFlowHost: UIViewControllerRepresentable {
    let projectID: String
    var mode: AuthenticationView.Mode = .signUp
    var flowEpoch: Int = 0
    var onFinished: (AuthenticationResponse) -> Void
    var onCancelled: (() -> Void)?
    var onFailed: ((String) -> Void)?

    func makeUIViewController(context: Context) -> DescopeFlowViewController {
        let controller = DescopeFlowViewController()
        controller.delegate = context.coordinator
        startFlow(on: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: DescopeFlowViewController, context: Context) {
        context.coordinator.onFinished = onFinished
        context.coordinator.onCancelled = onCancelled
        context.coordinator.onFailed = onFailed
        if context.coordinator.flowEpoch != flowEpoch {
            context.coordinator.flowEpoch = flowEpoch
            startFlow(on: uiViewController)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onFinished: onFinished,
            onCancelled: onCancelled,
            onFailed: onFailed,
            flowEpoch: flowEpoch
        )
    }

    private func startFlow(on controller: DescopeFlowViewController) {
        let flowName = mode == .signIn ? "sign-in" : "sign-up-or-in"
        let flowURL = "https://api.descope.com/login/\(projectID)?flow=\(flowName)"
        let flow = DescopeFlow(url: flowURL)
        controller.start(flow: flow)
    }

    final class Coordinator: NSObject, DescopeFlowViewControllerDelegate {
        var onFinished: (AuthenticationResponse) -> Void
        var onCancelled: (() -> Void)?
        var onFailed: ((String) -> Void)?
        var flowEpoch: Int

        init(
            onFinished: @escaping (AuthenticationResponse) -> Void,
            onCancelled: (() -> Void)?,
            onFailed: ((String) -> Void)?,
            flowEpoch: Int
        ) {
            self.onFinished = onFinished
            self.onCancelled = onCancelled
            self.onFailed = onFailed
            self.flowEpoch = flowEpoch
        }

        func flowViewControllerDidUpdateState(
            _ controller: DescopeFlowViewController,
            to state: DescopeFlowState,
            from previous: DescopeFlowState
        ) {}

        func flowViewControllerDidBecomeReady(_ controller: DescopeFlowViewController) {}

        func flowViewControllerShouldShowURL(
            _ controller: DescopeFlowViewController,
            url: URL,
            external: Bool
        ) -> Bool {
            true
        }

        func flowViewControllerDidCancel(_ controller: DescopeFlowViewController) {
            onCancelled?()
        }

        func flowViewControllerDidFail(_ controller: DescopeFlowViewController, error: DescopeError) {
            onFailed?(error.errorDescription ?? "Descope sign-in failed. Please try again.")
        }

        func flowViewControllerDidFinish(
            _ controller: DescopeFlowViewController,
            response: AuthenticationResponse
        ) {
            onFinished(response)
        }
    }
}
