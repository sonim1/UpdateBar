import {describe, expect, it} from 'vitest';
import {redactSecrets} from '../secrets.js';

describe('redactSecrets', () => {
  it('masks provider and cloud token literals without environment key names', () => {
    expect(redactSecrets('token sk-or-v1-secret-value')).toBe('token [REDACTED]');
    expect(redactSecrets('token sk-1234567890abcdef')).toBe('token [REDACTED]');
    expect(redactSecrets('aws AKIAIOSFODNN7EXAMPLE')).toBe('aws [REDACTED]');
    expect(redactSecrets('google AIzaSyA1234567890abcdefghijklmnopqrstuv')).toBe(
      'google [REDACTED]'
    );
  });

  it('masks GitHub token prefixes without environment key names', () => {
    for (const prefix of ['ghp', 'gho', 'ghu', 'ghs', 'ghr']) {
      expect(redactSecrets(`Authorization: Bearer ${prefix}_1234567890abcdefghijklmnopqrstuvwxyz`)).toBe(
        'Authorization: Bearer [REDACTED]'
      );
    }
    expect(redactSecrets('token github_pat_11ABCDEF_abcdefghijklmnopqrstuvwxyz0123456789')).toBe(
      'token [REDACTED]'
    );
  });

  it('masks sensitive environment assignments and JSON properties', () => {
    expect(
      redactSecrets(
        'NPM_TOKEN=npm-secret HOMEBREW_GITHUB_API_TOKEN=brew-secret AWS_SECRET_ACCESS_KEY=aws-secret'
      )
    ).toBe('[REDACTED] [REDACTED] [REDACTED]');

    const redacted = redactSecrets(
      '{"env":{"NPM_TOKEN":"npm-secret","AWS_SESSION_TOKEN":"aws-secret"}}'
    );
    expect(redacted).toContain('[REDACTED]');
    expect(redacted).not.toContain('npm-secret');
    expect(redacted).not.toContain('aws-secret');
  });

  it('masks deployment token environment names', () => {
    const redacted = redactSecrets(
      'CLOUDFLARE_API_TOKEN=cf-secret CF_API_TOKEN=cf-short VERCEL_TOKEN=vercel-secret {"env":{"SUPABASE_ACCESS_TOKEN":"supabase secret"}}'
    );

    expect(redacted).not.toContain('cf-secret');
    expect(redacted).not.toContain('cf-short');
    expect(redacted).not.toContain('vercel-secret');
    expect(redacted).not.toContain('supabase secret');
    expect(redacted.match(/\[REDACTED\]/g)).toHaveLength(4);
  });

  it('masks quoted sensitive values containing spaces', () => {
    const redacted = redactSecrets(
      'NPM_TOKEN="npm secret" {"env":{"AWS_SESSION_TOKEN":"aws secret"}}'
    );

    expect(redacted).not.toContain('npm secret');
    expect(redacted).not.toContain('aws secret');
    expect(redacted).not.toContain('secret');
    expect(redacted.match(/\[REDACTED\]/g)).toHaveLength(2);
  });
});
