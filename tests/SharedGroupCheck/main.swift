import Foundation

@main
struct SharedGroupCheck {
    static func main() throws {
        let original = "group.com.jevchat.jarvis"
        let first = "group.fixture.resigned.1"
        let second = "group.fixture.resigned.2"
        var passed = 0
        var failed = 0

        func profile(_ groups: Any) throws -> Data {
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["Entitlements": ["com.apple.security.application-groups": groups]],
                format: .xml, options: 0)
            // Model the XML payload inside a CMS envelope; signature verification is the OS's job.
            return Data([0x30, 0x82, 0x01, 0x00]) + plist + Data([0x00, 0x01])
        }

        func resolve(_ data: Data?, _ available: Set<String>) -> String? {
#if JEV_DYNAMIC_GROUP
            return JevStore.resolveAppGroup(profileData: data, isAvailable: { available.contains($0) })
#else
            // Baseline adapter for the original implementation's fixed group selection.
            return JevStore.appGroupID
#endif
        }

        func check(_ name: String, _ data: Data?, _ available: Set<String>, _ expected: String?) {
            let actual = resolve(data, available)
            if actual == expected {
                passed += 1
                print("PASS \(name)")
            } else {
                failed += 1
                print("FAIL \(name): got \(actual ?? "nil"), expected \(expected ?? "nil")")
            }
        }

        let mainProfile = try profile([second, first])
        let keyboardProfile = try profile([first, second])
        check("original-group-without-profile", nil, [original], original)
        check("prefer-working-original-group", mainProfile, [original, first, second], original)
        check("resigned-main-selects-authorized-group", mainProfile, [first, second], first)
        check("resigned-keyboard-matches-main-despite-order", keyboardProfile, [first, second], first)
        check("skip-group-without-runtime-permission", mainProfile, [second], second)
        check("profile-cannot-grant-runtime-permission", mainProfile, [], nil)
        check("no-profile-and-no-original-permission", nil, [], nil)
        check("invalid-profile", Data("not a profile".utf8), [first], nil)
        check("truncated-profile", Data("<?xml <plist>".utf8), [first], nil)
        check("malformed-group-list", try profile("not-an-array"), [first], nil)
        check("ignore-non-group-identifier", try profile(["unrelated.domain", first]), ["unrelated.domain", first], first)
        check("duplicate-groups", try profile([second, first, first]), [first, second], first)
        check("missing-entitlements", try PropertyListSerialization.data(fromPropertyList: ["Name": "fixture"], format: .xml, options: 0), [first], nil)
        check("original-survives-malformed-profile", Data("broken".utf8), [original], original)
        print("Shared group checks: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
