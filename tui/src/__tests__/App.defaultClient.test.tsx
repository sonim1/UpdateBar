import React from 'react';
import {render} from 'ink-testing-library';
import {afterEach, describe, expect, it, vi} from 'vitest';
import {createDefaultClient} from '../client.js';
import {App} from '../App.js';

vi.mock('../client.js', async importOriginal => {
  const actual = await importOriginal<typeof import('../client.js')>();
  return {
    ...actual,
    createDefaultClient: vi.fn()
  };
});

const mockedCreateDefaultClient = vi.mocked(createDefaultClient);

describe('App default client setup', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('does not describe default client setup failures as still loading status', async () => {
    mockedCreateDefaultClient.mockRejectedValue(new Error('updatebar binary not found'));

    const view = render(<App />);

    await waitForFrame(view, 'updatebar binary not found');

    expect(view.lastFrame()).toContain('Status unavailable');
    expect(view.lastFrame()).not.toContain('Loading status...');
  });
});

async function waitForFrame(view: {lastFrame(): string | undefined}, text: string) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (view.lastFrame()?.includes(text)) return;
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  throw new Error(`Timed out waiting for frame containing: ${text}\n${view.lastFrame()}`);
}
