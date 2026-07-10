import Foundation
import Testing

struct BuildScriptPackagingTests {
    @Test("运行脚本按标准 app bundle 结构放置菜单栏图标")
    func runScriptPlacesMenuBarIconInContentsResources() throws {
        let script = try String(contentsOfFile: "script/build_and_run.sh", encoding: .utf8)

        #expect(script.contains("cp \"$ROOT_DIR/Sources/CodexQ/Resources/MenuBarIcon.png\" \"$APP_RESOURCES/MenuBarIcon.png\""))
        #expect(script.contains("/usr/bin/codesign --force --sign - \"$APP_BUNDLE\""))
        #expect(script.contains("/usr/bin/codesign --verify --strict --verbose=2 \"$APP_BUNDLE\""))
        #expect(!script.contains("cp -R \"$RESOURCE_BUNDLE\" \"$APP_BUNDLE/\""))
    }

    @Test("发布脚本生成匹配目标架构的 Release zip")
    func releaseScriptCreatesArchitectureZip() throws {
        let script = try String(contentsOfFile: "script/package_release.sh", encoding: .utf8)

        #expect(script.contains("ARCH=\"${2:-$(uname -m)}\""))
        #expect(script.contains("[[ \"$VERSION\" =~ ^[0-9A-Za-z._-]+$ ]]"))
        #expect(script.contains("swift build -c release --arch \"$ARCH\""))
        #expect(script.contains("CodexQ-${VERSION}-${ARCH}.zip"))
        #expect(script.contains("/usr/bin/ditto -c -k --sequesterRsrc --keepParent"))
        #expect(script.contains("cp \"$ROOT_DIR/Sources/CodexQ/Resources/MenuBarIcon.png\" \"$APP_RESOURCES/MenuBarIcon.png\""))
        #expect(!script.contains("cp -R \"$RESOURCE_BUNDLE\" \"$APP_BUNDLE/\""))
    }
}
