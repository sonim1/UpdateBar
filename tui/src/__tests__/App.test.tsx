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
          summary: {total: 2, outdated: 1, errors: 0},
          items: []
        };
      }
    });

    const view = render(<App client={client} />);
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(view.lastFrame()).toContain('2 tracked · 1 outdated · 0 errors');
  });

  it('opens scan candidates from the menu', async () => {
    const client = createClient();
    const view = render(<App client={client} />);

    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));

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

  it('registers selected scan candidates', async () => {
    const selected: string[][] = [];
    const client = createClient({
      async initSelected(ids) {
        selected.push(ids);
        return {ok: true, added: ids, replaced: [], skipped: [], errors: []};
      }
    });
    const view = render(<App client={client} />);

    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write(' ');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(selected).toEqual([['brew.gh']]);
    expect(view.lastFrame()).toContain('added 1');
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

    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\u001B[B');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write(' ');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));

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
        summary: {total: 0, outdated: 0, errors: 0},
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
    async checkNow() {},
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
