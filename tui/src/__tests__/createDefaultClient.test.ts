import {afterEach, describe, expect, it, vi} from 'vitest';
import {createDefaultClient} from '../client.js';
import {resolveUpdateBarBinary} from '../binaryResolver.js';

vi.mock('../binaryResolver.js', () => ({
  resolveUpdateBarBinary: vi.fn()
}));

const mockedResolve = vi.mocked(resolveUpdateBarBinary);

describe('createDefaultClient', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('warns when resolving via deprecated UPDATEBAR_CLI', async () => {
    mockedResolve.mockResolvedValue({path: '/tmp/updatebar', source: 'UPDATEBAR_CLI'});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    await createDefaultClient();

    expect(warnSpy).toHaveBeenCalledWith('UPDATEBAR_CLI is deprecated; prefer UPDATEBAR_BIN');
  });

  it('does not warn when resolving via UPDATEBAR_BIN', async () => {
    mockedResolve.mockResolvedValue({path: '/tmp/updatebar', source: 'UPDATEBAR_BIN'});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    await createDefaultClient();

    expect(warnSpy).not.toHaveBeenCalled();
  });
});
