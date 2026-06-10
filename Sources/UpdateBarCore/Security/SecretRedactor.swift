import Foundation

public enum SecretRedactor {
    public static func redact(_ text: String) -> String {
        var output = text
        let patterns = [
            #"sk-or-v1-[A-Za-z0-9._-]+"#,
            #"sk-[A-Za-z0-9._-]{8,}"#,
            #"ghp_[A-Za-z0-9_]{20,}"#,
            #"github_pat_[A-Za-z0-9_]{20,}"#,
            #"(?i)(OPENROUTER_API_KEY|ANTHROPIC_API_KEY|OPENAI_API_KEY|GOOGLE_API_KEY|GITHUB_TOKEN|GH_TOKEN)=\S+"#
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
