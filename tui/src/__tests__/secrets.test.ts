import {describe, expect, it} from 'vitest';
import {redactSecrets} from '../secrets.js';

describe('redactSecrets', () => {
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
});
