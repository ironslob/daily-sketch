import SwiftUI

@main
struct DailySketchApp: App {
    @State private var dependencies = AppDependencies.live

    init() {
        let memoryCapacity = 32 * 1024 * 1024
        let diskCapacity = 256 * 1024 * 1024
        URLCache.shared = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: "daily-sketch-image-cache"
        )
    }

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
