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

  it('opens config path even when default client setup fails', async () => {
    const previousHome = process.env.UPDATEBAR_HOME;
    process.env.UPDATEBAR_HOME = '/tmp/updatebar-tui-home';
    mockedCreateDefaultClient.mockRejectedValue(new Error('updatebar binary not found'));
    const view = render(<App />);

    try {
      await waitForFrame(view, 'updatebar binary not found');
      view.stdin.write('\u001B[B');
      view.stdin.write('\u001B[B');
      view.stdin.write('\u001B[B');
      view.stdin.write('\u001B[B');
      await wait();
      view.stdin.write('\r');
      await waitForFrame(view, 'config path: /tmp/updatebar-tui-home/config.toml');

      expect(view.lastFrame()).toContain('config path: /tmp/updatebar-tui-home/config.toml');
      expect(view.lastFrame()).not.toContain('updatebar binary not found');
    } finally {
      view.unmount();
      if (previousHome === undefined) {
        delete process.env.UPDATEBAR_HOME;
      } else {
        process.env.UPDATEBAR_HOME = previousHome;
      }
    }
  });
});

async function waitForFrame(view: {lastFrame(): string | undefined}, text: string) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (view.lastFrame()?.includes(text)) return;
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  throw new Error(`Timed out waiting for frame containing: ${text}\n${view.lastFrame()}`);
}

async function wait() {
  await new Promise(resolve => setTimeout(resolve, 20));
}
