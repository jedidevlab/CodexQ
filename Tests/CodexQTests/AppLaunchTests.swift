import Foundation
import Testing

struct AppLaunchTests {
    @Test("应用启动完成后在下一次主线程调度创建状态栏")
    func statusBarCreationIsDeferredUntilLaunchLayoutFinishes() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/CodexQApp.swift",
            encoding: .utf8
        )

        #expect(source.contains("DispatchQueue.main.async"))
        #expect(!source.contains("await Task.yield()"))
        #expect(source.contains("statusController = StatusBarController()"))
    }
}
