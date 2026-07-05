import {afterEach, describe, expect, it, vi} from 'vitest';
import {createDefaultClient} from '../client.js';
import {resolveUpdateBarBinary} from '../binaryResolver.js';

vi.mock('../binaryResolver.js', () => ({
  resolveUpdateBarBinary: vi.fn()
}));

const mockedResolve = vi.mocked(resolveUpdateBarBinary);

describe('createDefaultClient', () => {
  afterEach(() => {
    vi.clearAllMocks();
    vi.restoreAllMocks();
  });

  it('does not warn when resolving via UPDATEBAR_BIN', async () => {
    mockedResolve.mockResolvedValue({path: '/tmp/updatebar', source: 'UPDATEBAR_BIN'});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    await createDefaultClient();

    expect(warnSpy).not.toHaveBeenCalled();
  });

  it('passes configured binary paths to the resolver', async () => {
    mockedResolve.mockResolvedValue({path: '/tmp/updatebar', source: 'configured'});

    await createDefaultClient({configuredPath: '/tmp/updatebar'});

    expect(mockedResolve).toHaveBeenCalledWith({configuredPath: '/tmp/updatebar'});
  });
});
