import Foundation
import Testing

struct BuildScriptPackagingTests {
    @Test("运行脚本按标准 app bundle 结构放置菜单栏图标")
    func runScriptPlacesMenuBarIconInContentsResources() throws {
        let script = try String(contentsOfFile: "script/build_and_run.sh", encoding: .utf8)

        #expect(script.contains("cp \"$ROOT_DIR/Sources/CodexQ/Resources/MenuBarIcon.png\" \"$APP_RESOURCES/MenuBarIcon.png\""))
        #expect(!script.contains("cp -R \"$RESOURCE_BUNDLE\" \"$APP_BUNDLE/\""))
    }

    @Test("发布脚本生成可上传 Release 的 arm64 zip")
    func releaseScriptCreatesArm64Zip() throws {
        let script = try String(contentsOfFile: "script/package_release.sh", encoding: .utf8)

        #expect(script.contains("swift build -c release"))
        #expect(script.contains("CodexQ-${VERSION}-arm64.zip"))
        #expect(script.contains("/usr/bin/ditto -c -k --sequesterRsrc --keepParent"))
        #expect(script.contains("cp \"$ROOT_DIR/Sources/CodexQ/Resources/MenuBarIcon.png\" \"$APP_RESOURCES/MenuBarIcon.png\""))
        #expect(!script.contains("cp -R \"$RESOURCE_BUNDLE\" \"$APP_BUNDLE/\""))
    }
}
