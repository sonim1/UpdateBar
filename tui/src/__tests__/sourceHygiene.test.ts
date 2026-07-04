import {readFile} from 'node:fs/promises';
import {describe, expect, it} from 'vitest';

describe('TUI source hygiene', () => {
  it('does not disable explicit-any linting', async () => {
    const eslintConfig = await readFile('eslint.config.js', 'utf8');

    expect(eslintConfig).not.toContain("'@typescript-eslint/no-explicit-any': 'off'");
    expect(eslintConfig).not.toContain('"@typescript-eslint/no-explicit-any": "off"');
  });
});
