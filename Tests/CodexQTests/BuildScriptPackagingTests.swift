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

        #expect(script.contains("ARCH=\"${2:-arm64}\""))
        #expect(script.contains("[[ \"$VERSION\" =~ ^[0-9A-Za-z._-]+$ ]]"))
        #expect(script.contains("swift build -c release --arch \"$ARCH\""))
        #expect(script.contains("CodexQ-${VERSION}-${ARCH}.zip"))
        #expect(script.contains("/usr/bin/ditto -c -k --sequesterRsrc --keepParent"))
        #expect(script.contains("cp \"$ROOT_DIR/Sources/CodexQ/Resources/MenuBarIcon.png\" \"$APP_RESOURCES/MenuBarIcon.png\""))
        #expect(!script.contains("cp -R \"$RESOURCE_BUNDLE\" \"$APP_BUNDLE/\""))
    }

    @Test("全球发行只声明官方依赖支持的平台")
    func globalReleaseUsesSupportedPlatformContract() throws {
        let package = try String(contentsOfFile: "Package.swift", encoding: .utf8)
        let runScript = try String(contentsOfFile: "script/build_and_run.sh", encoding: .utf8)
        let releaseScript = try String(contentsOfFile: "script/package_release.sh", encoding: .utf8)
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let englishReadme = try String(contentsOfFile: "README.en.md", encoding: .utf8)

        #expect(package.contains("platforms: [.macOS(.v14)]"))
        #expect(runScript.contains("MIN_SYSTEM_VERSION=\"14.0\""))
        #expect(releaseScript.contains("MIN_SYSTEM_VERSION=\"14.0\""))
        #expect(releaseScript.contains("arm64)"))
        #expect(!releaseScript.contains("arm64|x86_64"))
        #expect(readme.contains("macOS 14"))
        #expect(readme.contains("Apple Silicon"))
        #expect(!readme.contains("x86_64"))
        #expect(englishReadme.contains("macOS 14"))
        #expect(englishReadme.contains("Apple Silicon"))
        #expect(!englishReadme.contains("x86_64"))
    }

    @Test("公开发布默认要求 Developer ID 签名与公证")
    func publicReleaseRequiresSigningAndNotarization() throws {
        let script = try String(contentsOfFile: "script/package_release.sh", encoding: .utf8)

        #expect(script.contains("CODE_SIGN_IDENTITY=\"${CODE_SIGN_IDENTITY:-}\""))
        #expect(script.contains("NOTARY_PROFILE=\"${NOTARY_PROFILE:-}\""))
        #expect(script.contains("ALLOW_ADHOC=\"${ALLOW_ADHOC:-0}\""))
        #expect(script.contains("--options runtime --timestamp"))
        #expect(script.contains("notarytool submit"))
        #expect(script.contains("stapler staple"))
        #expect(script.contains("stapler validate"))
        #expect(script.contains("spctl --assess --type execute"))
    }
}
