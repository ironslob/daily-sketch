import DescopeKit
import SwiftUI
import UIKit

/// Hosts a Descope Flow for sign-up / sign-in when a real project ID is configured.
struct DescopeFlowHost: UIViewControllerRepresentable {
    let projectID: String
    var onFinished: (AuthenticationResponse) -> Void

    func makeUIViewController(context: Context) -> DescopeFlowViewController {
        let controller = DescopeFlowViewController()
        controller.delegate = context.coordinator
        let flowURL = "https://api.descope.com/login/\(projectID)?flow=sign-up-or-in"
        let flow = DescopeFlow(url: flowURL)
        controller.start(flow: flow)
        return controller
    }

    func updateUIViewController(_ uiViewController: DescopeFlowViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    final class Coordinator: NSObject, DescopeFlowViewControllerDelegate {
        let onFinished: (AuthenticationResponse) -> Void

        init(onFinished: @escaping (AuthenticationResponse) -> Void) {
            self.onFinished = onFinished
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

        func flowViewControllerDidCancel(_ controller: DescopeFlowViewController) {}

        func flowViewControllerDidFail(_ controller: DescopeFlowViewController, error: DescopeError) {}

        func flowViewControllerDidFinish(
            _ controller: DescopeFlowViewController,
            response: AuthenticationResponse
        ) {
            onFinished(response)
        }
    }
}
