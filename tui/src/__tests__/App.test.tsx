import React from 'react';
import {PassThrough, Writable} from 'node:stream';
import {render as renderInk} from 'ink';
import {render} from 'ink-testing-library';
import {describe, expect, it} from 'vitest';
import {App} from '../App.js';
import type {CommandResult, StreamOptions, UpdateBarClient} from '../client.js';

describe('App', () => {
  it('renders status summary from the client', async () => {
    const client = createClient({
      async status() {
        return {
          generated_at: '2026-06-30T00:00:00Z',
          summary: {total: 2, outdated: 1, errors: 0, untrusted: 3, pinned: 2},
          items: []
        };
      }
    });

    const view = render(<App client={client} />);
    await waitForFrame(view, '2 tracked · 1 outdated · 0 errors · 3 untrusted · 2 pinned');

    expect(view.lastFrame()).toContain('2 tracked · 1 outdated · 0 errors · 3 untrusted · 2 pinned');
  });

  it('opens scan candidates from the menu', async () => {
    const client = createClient();
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'brew.gh');

    expect(view.lastFrame()).toContain('brew.gh');
    expect(view.lastFrame()).toContain('known.node');
    expect(view.lastFrame()).toContain('check-only');
  });

  it('returns from status to the menu', async () => {
    const client = createClient();
    const view = render(<App client={client} />);

    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('m');
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(view.lastFrame()).toContain('Scan & Add');
    expect(view.lastFrame()).toContain('Run Updates');
  });

  it('selects all importable scan candidates at once', async () => {
    const selected: string[][] = [];
    const client = createClient({
      async scan() {
        return {
          candidates: [
            {
              id: 'brew.gh',
              name: 'gh',
              detector: 'brew',
              category: 'cloud-devops',
              capability: 'full',
              confidence: 'high',
              installed_version: '2.74.0',
              source_ref: 'gh',
              recipe: {}
            },
            {
              id: 'brew.curl',
              name: 'curl',
              detector: 'brew',
              category: 'shell-utility',
              capability: 'full',
              confidence: 'high',
              installed_version: '8.0.0',
              source_ref: 'curl',
              recipe: {}
            },
            {
              id: 'known.node',
              name: 'node',
              detector: 'known',
              category: 'runtime-sdk',
              capability: 'check-only',
              confidence: 'medium',
              installed_version: '24.0.0',
              source_ref: 'node'
            }
          ],
          errors: []
        };
      },
      async initSelected(ids) {
        selected.push(ids);
        return {ok: true, added: ids, replaced: [], skipped: [], errors: []};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'importable: 0/2');
    view.stdin.write('a');
    await wait();
    expect(view.lastFrame()).toContain('importable: 2/2');
    view.stdin.write('\r');
    await waitForFrame(view, 'added 2');

    expect(selected).toEqual([['brew.gh', 'brew.curl']]);
  });

  it('shows a helpful message when trying to select an unimportable candidate', async () => {
    const selected: string[][] = [];
    const client = createClient({
      async scan() {
        return {
          candidates: [
            {
              id: 'brew.gh',
              name: 'gh',
              detector: 'brew',
              category: 'cloud-devops',
              capability: 'full',
              confidence: 'high',
              installed_version: '2.74.0',
              source_ref: 'gh',
              recipe: {}
            },
            {
              id: 'known.node',
              name: 'node',
              detector: 'known',
              category: 'runtime-sdk',
              capability: 'check-only',
              confidence: 'medium',
              installed_version: '24.0.0',
              source_ref: 'node'
            }
          ],
          errors: []
        };
      },
      async initSelected(ids) {
        selected.push(ids);
        return {ok: true, added: ids, replaced: [], skipped: [], errors: []};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'importable: 0/1');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write(' ');
    await wait();

    expect(view.lastFrame()).toContain('known.node is not importable yet');
    expect(selected).toEqual([]);
  });

  it('reports when trying to bulk-select with no importable candidates', async () => {
    const client = createClient({
      async scan() {
        return {
          candidates: [
            {
              id: 'known.node',
              name: 'node',
              detector: 'known',
              category: 'runtime-sdk',
              capability: 'check-only',
              confidence: 'medium',
              installed_version: '24.0.0',
              source_ref: 'node'
            }
          ],
          errors: []
        };
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'needs review: 1');
    view.stdin.write('a');
    await wait();

    expect(view.lastFrame()).toContain('No importable candidates to select');
  });

  it('registers selected scan candidates', async () => {
    const selected: string[][] = [];
    const client = createClient({
      async initSelected(ids) {
        selected.push(ids);
        return {ok: true, added: ids, replaced: [], skipped: [], errors: []};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'brew.gh');
    view.stdin.write(' ');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'added 1');

    expect(selected).toEqual([['brew.gh']]);
    expect(view.lastFrame()).toContain('added 1');
  });

  it('clears scan selections after a successful registration', async () => {
    const selected: string[][] = [];
    const client = createClient({
      async scan() {
        return {
          candidates: [
            {
              id: 'brew.gh',
              name: 'gh',
              detector: 'brew',
              category: 'cloud-devops',
              capability: 'full',
              confidence: 'high',
              installed_version: '2.74.0',
              source_ref: 'gh',
              recipe: {}
            },
            {
              id: 'brew.jq',
              name: 'jq',
              detector: 'brew',
              category: 'shell-utility',
              capability: 'full',
              confidence: 'high',
              installed_version: '1.7.0',
              source_ref: 'jq',
              recipe: {}
            }
          ],
          errors: []
        };
      },
      async initSelected(ids) {
        selected.push(ids);
        return {ok: true, added: ids, replaced: [], skipped: [], errors: []};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'importable: 0/2');
    view.stdin.write(' ');
    await waitForFrame(view, 'importable: 1/2');
    view.stdin.write('\r');
    await waitForFrame(view, 'added 1');

    view.stdin.write('m');
    await waitForFrame(view, 'm menu · q quit');
    view.stdin.write('\u001B[A');
    view.stdin.write('\u001B[A');
    view.stdin.write('\u001B[A');
    view.stdin.write('\u001B[A');
    view.stdin.write('\u001B[A');
    view.stdin.write('\u001B[A');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'importable: 0/2');
    view.stdin.write('a');
    await waitForFrame(view, 'importable: 2/2');

    expect(selected).toEqual([['brew.gh']]);
  });

  it('navigates scan candidates before registering', async () => {
    const selected: string[][] = [];
    const client = createClient({
      async scan() {
        return {
          candidates: [
            {
              id: 'brew.gh',
              name: 'gh',
              detector: 'brew',
              category: 'cloud-devops',
              capability: 'full',
              confidence: 'high',
              installed_version: '2.74.0',
              source_ref: 'gh',
              recipe: {}
            },
            {
              id: 'npm.typescript',
              name: 'typescript',
              detector: 'npm_global',
              category: 'runtime-sdk',
              capability: 'full',
              confidence: 'high',
              installed_version: '5.9.0',
              source_ref: 'typescript',
              recipe: {}
            }
          ],
          errors: []
        };
      },
      async initSelected(ids) {
        selected.push(ids);
        return {ok: true, added: ids, replaced: [], skipped: [], errors: []};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'npm.typescript');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write(' ');
    await wait();
    view.stdin.write('\r');
    await wait();

    expect(selected).toEqual([['npm.typescript']]);
  });

  it('cancels an active scan', async () => {
    let aborted = false;
    const client = createClient({
      async scan(options) {
        options?.signal?.addEventListener('abort', () => {
          aborted = true;
        });
        return new Promise(() => {});
      }
    });
    const view = render(<App client={client} />);

    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('c');
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(aborted).toBe(true);
  });

  it('shows a friendly message when scan cancellation rejects', async () => {
    const client = createClient({
      async scan(options) {
        return new Promise((_resolve, reject) => {
          options?.signal?.addEventListener('abort', () => {
            reject(new Error('exit 1'));
          });
        });
      }
    });
    const view = render(<App client={client} />);

    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('c');
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(view.lastFrame()).toContain('scan cancelled');
    expect(view.lastFrame()).not.toContain('exit 1');
  });

  it('shows check summary logs', async () => {
    const client = createClient({
      async checkNow() {
        return {
          items: [
            {
              id: 'brew.gh',
              name: 'gh',
              status: 'outdated',
              current: '2.74.0',
              latest: '2.75.0',
              last_checked: '2026-06-30T00:00:00Z'
            }
          ],
          summary: {total: 1, outdated: 1, errors: 0, untrusted: 0, disabled: 0, pinned: 0}
        };
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Refresh Status');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'checked 1 items');

    expect(view.lastFrame()).toContain('outdated: 1');
    expect(view.lastFrame()).toContain('errors: 0');
  });

  it('cancels an active check', async () => {
    let aborted = false;
    const client = createClient({
      async checkNow(options?: {signal?: AbortSignal}) {
        options?.signal?.addEventListener('abort', () => {
          aborted = true;
        });
        return new Promise(() => {});
      }
    });
    const view = render(<App client={client} />);

    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('c');
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(aborted).toBe(true);
  });

  it('cancels an active check before quitting', async () => {
    let aborted = false;
    const client = createClient({
      async checkNow(options?: {signal?: AbortSignal}) {
        options?.signal?.addEventListener('abort', () => {
          aborted = true;
        });
        return new Promise(() => {});
      }
    });
    const view = render(<App client={client} />);

    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('q');
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(aborted).toBe(true);
  });

  it('cancels an active check when unmounted', async () => {
    let aborted = false;
    const client = createClient({
      async checkNow(options?: {signal?: AbortSignal}) {
        options?.signal?.addEventListener('abort', () => {
          aborted = true;
        });
        return new Promise(() => {});
      }
    });
    const view = render(<App client={client} />);

    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.unmount();
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(aborted).toBe(true);
  });

  it('shows a friendly message when update cancellation rejects', async () => {
    const client = createClient({
      async updateAll(options: StreamOptions): Promise<CommandResult> {
        return new Promise((_resolve, reject) => {
          options.signal?.addEventListener('abort', () => {
            reject(new Error('exit 1'));
          });
        });
      }
    });
    const view = render(<App client={client} />);

    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('c');
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(view.lastFrame()).toContain('update cancelled');
    expect(view.lastFrame()).not.toContain('exit 1');
  });

  it('clears stale errors when starting updates', async () => {
    let statusCalls = 0;
    const client = createClient({
      async status() {
        statusCalls += 1;
        if (statusCalls === 1) {
          throw new Error('status unavailable');
        }
        return {
          generated_at: '2026-06-30T00:00:00Z',
          summary: {total: 0, outdated: 0, errors: 0, untrusted: 0, pinned: 0},
          items: []
        };
      },
      async updateAll() {
        return new Promise(() => {});
      }
    });
    const view = render(<App client={client} />);

    await new Promise(resolve => setTimeout(resolve, 20));
    expect(view.lastFrame()).toContain('status unavailable');

    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(view.lastFrame()).toContain('update started');
    expect(view.lastFrame()).not.toContain('status unavailable');

    view.unmount();
  });

  it('renders without raw mode when stdin has no TTY support', async () => {
    const client = createClient();
    const stdin = new PassThrough() as NodeJS.ReadStream;
    const stdout = createOutputStream();
    const stderr = createOutputStream();

    Object.defineProperty(stdin, 'isTTY', {value: undefined});

    const view = renderInk(<App client={client} />, {
      stdin,
      stdout,
      stderr,
      debug: true,
      exitOnCtrlC: false,
      interactive: false,
      patchConsole: false
    });

    await new Promise(resolve => setTimeout(resolve, 20));

    view.unmount();
    await expect(view.waitUntilExit()).resolves.toBeUndefined();
  });
});

function createClient(overrides: Partial<UpdateBarClient> = {}): UpdateBarClient {
  return {
    async status() {
      return {
        generated_at: '2026-06-30T00:00:00Z',
        summary: {total: 0, outdated: 0, errors: 0, untrusted: 0, pinned: 0},
        items: []
      };
    },
    async scan() {
      return {
        candidates: [
          {
            id: 'brew.gh',
            name: 'gh',
            detector: 'brew',
            category: 'cloud-devops',
            capability: 'full',
            confidence: 'high',
            installed_version: '2.74.0',
            source_ref: 'gh',
            recipe: {}
          },
          {
            id: 'known.node',
            name: 'node',
            detector: 'known',
            category: 'runtime-sdk',
            capability: 'check-only',
            confidence: 'medium',
            installed_version: '24.0.0',
            source_ref: 'node'
          }
        ],
        errors: []
      };
    },
    async initSelected() {
      return {ok: true, added: ['brew.gh'], replaced: [], skipped: [], errors: []};
    },
    async checkNow() {
      return {
        items: [],
        summary: {total: 0, outdated: 0, errors: 0, untrusted: 0, disabled: 0, pinned: 0}
      };
    },
    async updateAll() {
      return {exitCode: 0, stdout: '', stderr: ''};
    },
    ...overrides
  };
}

function createOutputStream(): NodeJS.WriteStream {
  const stream = new Writable({
    write(_chunk, _encoding, callback) {
      callback();
    }
  }) as NodeJS.WriteStream;

  Object.defineProperty(stream, 'columns', {value: 100});
  Object.defineProperty(stream, 'isTTY', {value: false});
  return stream;
}

async function wait(ms = 20) {
  await new Promise(resolve => setTimeout(resolve, ms));
}

async function waitForFrame(
  view: ReturnType<typeof render>,
  text: string,
  timeoutMs = 1_000
) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (view.lastFrame()?.includes(text)) return;
    await wait(10);
  }
  expect(view.lastFrame()).toContain(text);
}
