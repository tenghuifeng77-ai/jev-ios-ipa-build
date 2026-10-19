import Foundation

@main
struct RequestCheck {
    static func main() async {
        let base = CommandLine.arguments[1]
        let scenarios: [(String, APIKind, String, String)] = [
            ("sol-defaults", .openai, "gpt-6.1-sol", ""),
            ("sol-medium-old-json", .openai, "gpt-6.1-sol",
             #"{"max_tokens":null,"temperature":null,"max_completion_tokens":4096,"reasoning_effort":"medium"}"#),
            ("sol-high", .openai, "gpt-6.1-sol",
             #"{"max_completion_tokens":8192,"reasoning_effort":"high","top_p":0.8,"logprobs":true,"top_logprobs":2}"#),
            ("sol-low", .openai, "gpt-6.1-sol", #"{"reasoning_effort":"low"}"#),
            ("sol-delayed", .openai, "gpt-6.1-sol", ""),
            ("legacy-glm", .openai, "glm-4-flash", ""),
            ("legacy-custom", .openai, "glm-4-flash", #"{"max_tokens":120,"temperature":0.5}"#),
            ("anthropic", .anthropic, "test-anthropic", "")
        ]
        var failed = 0
        for (name, kind, model, extra) in scenarios {
            var config = JevConfig()
            config.genKind = kind
            config.genBase = base + "/" + name
            config.genKey = "local-test-key"
            config.genModel = model
            config.genExtraJSON = extra
            do {
                let reply = try await JevDraft(cfg: config).call(prompt: "回复两个字：收到")
                if reply == "收到" {
                    print("PASS \(name)")
                } else {
                    print("FAIL \(name): unexpected parsed reply")
                    failed += 1
                }
            } catch {
                print("FAIL \(name): \(error.localizedDescription)")
                failed += 1
            }
        }
        print("Request integration checks: \(scenarios.count - failed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
