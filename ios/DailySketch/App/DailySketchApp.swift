import SwiftUI

@main
struct DailySketchApp: App {
    @State private var dependencies = AppDependencies.live

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(dependencies)
                .preferredColorScheme(nil)
                .task {
                    await dependencies.auth.bootstrap()
                }
        }
    }
}
