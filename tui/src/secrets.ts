const SENSITIVE_ENV_KEYS = [
  'OPENROUTER_API_KEY',
  'ANTHROPIC_API_KEY',
  'OPENAI_API_KEY',
  'GOOGLE_API_KEY',
  'GITHUB_TOKEN',
  'GH_TOKEN',
  'NPM_TOKEN',
  'NODE_AUTH_TOKEN',
  'HOMEBREW_GITHUB_API_TOKEN',
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'AWS_SESSION_TOKEN'
].join('|');

const SECRET_PATTERNS = [
  /sk-or-v1-[A-Za-z0-9._-]+/g,
  /sk-[A-Za-z0-9._-]{8,}/g,
  /ghp_[A-Za-z0-9_]{20,}/g,
  /github_pat_[A-Za-z0-9_]{20,}/g,
  /\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/g,
  /AIza[0-9A-Za-z_-]{35}/g,
  new RegExp(
    `(${SENSITIVE_ENV_KEYS})=("(?:\\\\.|[^"\\\\])*"|'(?:\\\\.|[^'\\\\])*'|\\S+)`,
    'gi'
  ),
  new RegExp(
    `["']?(${SENSITIVE_ENV_KEYS})["']?\\s*:\\s*("(?:\\\\.|[^"\\\\])*"|'(?:\\\\.|[^'\\\\])*'|[^"',}\\]\\s]+)`,
    'gi'
  )
];

export function redactSecrets(text: string) {
  return SECRET_PATTERNS.reduce((value, pattern) => value.replace(pattern, '[REDACTED]'), text);
}
