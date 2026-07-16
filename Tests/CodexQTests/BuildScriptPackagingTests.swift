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

    @Test("全球发行同时提供 Apple Silicon 与 Intel 安装包")
    func globalReleaseDocumentsBothMacArchitectures() throws {
        let package = try String(contentsOfFile: "Package.swift", encoding: .utf8)
        let runScript = try String(contentsOfFile: "script/build_and_run.sh", encoding: .utf8)
        let releaseScript = try String(contentsOfFile: "script/package_release.sh", encoding: .utf8)
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let englishReadme = try String(contentsOfFile: "README.en.md", encoding: .utf8)

        #expect(package.contains("platforms: [.macOS(.v14)]"))
        #expect(runScript.contains("MIN_SYSTEM_VERSION=\"14.0\""))
        #expect(releaseScript.contains("MIN_SYSTEM_VERSION=\"14.0\""))
        #expect(releaseScript.contains("arm64|x86_64"))
        #expect(readme.contains("macOS 14"))
        #expect(readme.contains("Apple Silicon"))
        #expect(readme.contains("CodexQ-1.0.10-arm64.zip"))
        #expect(readme.contains("CodexQ-1.0.10-x86_64.zip"))
        #expect(readme.contains("| Intel |"))
        #expect(readme.contains("隐私与安全"))
        #expect(readme.contains("仍要打开"))
        #expect(englishReadme.contains("macOS 14"))
        #expect(englishReadme.contains("Apple Silicon"))
        #expect(englishReadme.contains("CodexQ-1.0.10-arm64.zip"))
        #expect(englishReadme.contains("CodexQ-1.0.10-x86_64.zip"))
        #expect(englishReadme.contains("| Intel |"))
        #expect(englishReadme.contains("Privacy & Security"))
        #expect(englishReadme.contains("Open Anyway"))
    }

    @Test("发布脚本沿用无需开发者账号的 ad-hoc 签名")
    func releaseUsesAdHocSigningWithoutDeveloperAccount() throws {
        let script = try String(contentsOfFile: "script/package_release.sh", encoding: .utf8)

        #expect(script.contains("/usr/bin/codesign --force --sign - \"$APP_BUNDLE\""))
        #expect(!script.contains("CODE_SIGN_IDENTITY"))
        #expect(!script.contains("NOTARY_PROFILE"))
        #expect(!script.contains("ALLOW_ADHOC"))
        #expect(!script.contains("notarytool submit"))
    }
}
