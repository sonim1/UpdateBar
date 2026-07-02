import Foundation

public enum SecretRedactor {
    private static let sensitiveEnvironmentKeyPattern = [
        "OPENROUTER_API_KEY",
        "ANTHROPIC_API_KEY",
        "OPENAI_API_KEY",
        "GOOGLE_API_KEY",
        "GITHUB_TOKEN",
        "GH_TOKEN",
        "NPM_TOKEN",
        "NODE_AUTH_TOKEN",
        "HOMEBREW_GITHUB_API_TOKEN",
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN",
    ].joined(separator: "|")

    public static func redact(_ text: String) -> String {
        var output = text
        let patterns = [
            #"sk-or-v1-[A-Za-z0-9._-]+"#,
            #"sk-[A-Za-z0-9._-]{8,}"#,
            #"ghp_[A-Za-z0-9_]{20,}"#,
            #"github_pat_[A-Za-z0-9_]{20,}"#,
            #"(?i)(\#(sensitiveEnvironmentKeyPattern))=\S+"#,
            #"(?i)["']?(\#(sensitiveEnvironmentKeyPattern))["']?\s*:\s*["']?[^"',}\]\s]+["']?"#,
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "[REDACTED]",
                options: .regularExpression
            )
        }
        return output
    }
}
