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
          summary: {
            total: 2,
            outdated: 1,
            errors: 0,
            untrusted: 3,
            pinned: 2,
            disabled: 1,
            checking: 4,
            differs: 5
          },
          items: []
        };
      }
    });

    const view = render(<App client={client} />);
    await waitForFrame(
      view,
      '2 tracked · 1 outdated · 3 untrusted · 5 differs · 4 checking · 2 pinned · 1 disabled'
    );

    expect(view.lastFrame()).toContain(
      '2 tracked · 1 outdated · 3 untrusted · 5 differs · 4 checking · 2 pinned · 1 disabled'
    );
    expect(view.lastFrame()).not.toContain('0 errors');
  });

  it('hides zero status attention counts', async () => {
    const client = createClient({
      async status() {
        return {
          generated_at: '2026-06-30T00:00:00Z',
          summary: {
            total: 2,
            outdated: 0,
            errors: 0,
            untrusted: 0,
            pinned: 0,
            disabled: 0,
            checking: 0,
            differs: 0
          },
          items: []
        };
      }
    });

    const view = render(<App client={client} />);
    await waitForFrame(view, '2 tracked · 0 outdated');

    expect(view.lastFrame()).toContain('2 tracked · 0 outdated');
    expect(view.lastFrame()).not.toContain('0 errors');
    expect(view.lastFrame()).not.toContain('0 untrusted');
    expect(view.lastFrame()).not.toContain('0 pinned');
    expect(view.lastFrame()).not.toContain('0 disabled');
    expect(view.lastFrame()).not.toContain('0 checking');
    expect(view.lastFrame()).not.toContain('0 differs');
  });

  it('does not describe failed status loads as still loading', async () => {
    const client = createClient({
      async status() {
        throw new Error('status unavailable');
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'status unavailable');

    expect(view.lastFrame()).toContain('Status unavailable');
    expect(view.lastFrame()).not.toContain('Loading status...');
  });

  it('redacts status row secrets before rendering', async () => {
    const secret = 'sk-or-v1-status-secret-value';
    const client = createClient({
      async status() {
        return {
          generated_at: '2026-06-30T00:00:00Z',
          summary: {total: 1, outdated: 0, errors: 1, untrusted: 0, pinned: 0},
          items: [
            {
              id: `tool-${secret}`,
              name: 'secret-tool',
              category: 'cloud-devops',
              status: 'error',
              pinned: false,
              current: secret,
              latest: secret,
              error: `failed ${secret}`
            }
          ]
        };
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Refresh Status');
    view.stdin.write('\r');
    await waitForFrame(view, '[REDACTED]');

    expect(view.lastFrame()).toContain('[REDACTED]');
    expect(view.lastFrame()).not.toContain(secret);
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

  it('opens prompts from the menu', async () => {
    const client = createClient();
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    for (let index = 0; index < 7; index += 1) {
      view.stdin.write('\u001B[B');
      await wait();
    }
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Prompt Templates');

    expect(view.lastFrame()).toContain('Prompt Templates');
    expect(view.lastFrame()).toContain('LLM prompt: npm / JS package');
    expect(view.lastFrame()).toContain('Tool name:');
  });

  it('generates prompt template text from tool name input', async () => {
    const client = createClient();
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    for (let index = 0; index < 7; index += 1) {
      view.stdin.write('\u001B[B');
      await wait();
    }
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Tool name:');

    view.stdin.write('claude-code');
    await waitForFrame(view, 'Prompt for tool: "claude-code"');

    expect(view.lastFrame()).toContain('Prompt for tool: "claude-code"');
    expect(view.lastFrame()).toContain('updatebar validate --from /tmp/claude-code.json --json --explain');
  });

  it('warns when pressing enter on prompts without a tool name', async () => {
    const client = createClient();
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    for (let index = 0; index < 7; index += 1) {
      view.stdin.write('\u001B[B');
      await wait();
    }
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Tool name:');
    view.stdin.write('\r');
    await waitForFrame(view, 'Enter a tool name first');

    expect(view.lastFrame()).toContain('Enter a tool name first');
  });

  it('redacts scan rows and scan errors before rendering', async () => {
    const secret = 'sk-or-v1-scan-secret-value';
    const client = createClient({
      async scan() {
        return {
          candidates: [
            {
              id: `known.${secret}`,
              name: `tool-${secret}`,
              detector: 'known',
              category: 'cloud-devops',
              capability: 'unsupported',
              confidence: 'medium',
              source_ref: `/tmp/${secret}`
            }
          ],
          errors: [
            {
              detector: 'known',
              message: `failed ${secret}`
            }
          ]
        };
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, '[REDACTED]');

    expect(view.lastFrame()).toContain('[REDACTED]');
    expect(view.lastFrame()).not.toContain(secret);
  });

  it('shows scan errors when no candidates are found', async () => {
    const client = createClient({
      async scan() {
        return {
          candidates: [],
          errors: [
            {
              detector: 'brew',
              message: 'brew list failed'
            }
          ]
        };
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'No scan candidates');

    expect(view.lastFrame()).toContain('No scan candidates');
    expect(view.lastFrame()).toContain('brew: brew list failed');
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

  it('labels the config action as a path view', async () => {
    const client = createClient();
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Config Path');

    expect(view.lastFrame()).toContain('Config Path');
    expect(view.lastFrame()).not.toContain('Open Config');
  });

  it('shows the UPDATEBAR_HOME config path from Config Path', async () => {
    const previousHome = process.env.UPDATEBAR_HOME;
    process.env.UPDATEBAR_HOME = '/tmp/updatebar-custom-home';
    const client = createClient();
    const view = render(<App client={client} />);

    try {
      await waitForFrame(view, 'Config Path');
      view.stdin.write('\u001B[B');
      view.stdin.write('\u001B[B');
      view.stdin.write('\u001B[B');
      view.stdin.write('\u001B[B');
      await wait();
      view.stdin.write('\r');
      await waitForFrame(view, 'config path: /tmp/updatebar-custom-home/config.toml');

      expect(view.lastFrame()).toContain('config path: /tmp/updatebar-custom-home/config.toml');
    } finally {
      view.unmount();
      if (previousHome === undefined) {
        delete process.env.UPDATEBAR_HOME;
      } else {
        process.env.UPDATEBAR_HOME = previousHome;
      }
    }
  });

  it('clears stale status errors when showing the config path', async () => {
    const client = createClient({
      async status() {
        throw new Error('status unavailable');
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'status unavailable');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'config path:');

    expect(view.lastFrame()).toContain('config path:');
    expect(view.lastFrame()).not.toContain('status unavailable');
  });

  it('does not keep config path content as action logs', async () => {
    const previousHome = process.env.UPDATEBAR_HOME;
    process.env.UPDATEBAR_HOME = '/tmp/updatebar-config-log-home';
    const client = createClient();
    const view = render(<App client={client} />);

    try {
      await waitForFrame(view, 'Config Path');
      view.stdin.write('\u001B[B');
      view.stdin.write('\u001B[B');
      view.stdin.write('\u001B[B');
      view.stdin.write('\u001B[B');
      await wait();
      view.stdin.write('\r');
      await waitForFrame(view, 'config path: /tmp/updatebar-config-log-home/config.toml');
      view.stdin.write('m');
      await waitForFrame(view, 'View Logs');
      view.stdin.write('\u001B[B');
      await wait();
      view.stdin.write('\r');
      await waitForFrame(view, 'No logs yet');

      expect(view.lastFrame()).toContain('No logs yet');
      expect(view.lastFrame()).not.toContain('config path: /tmp/updatebar-config-log-home/config.toml');
    } finally {
      view.unmount();
      if (previousHome === undefined) {
        delete process.env.UPDATEBAR_HOME;
      } else {
        process.env.UPDATEBAR_HOME = previousHome;
      }
    }
  });

  it('shows an empty state when viewing logs before an action runs', async () => {
    const client = createClient();
    const view = render(<App client={client} />);

    await waitForFrame(view, 'View Logs');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'No logs yet');

    expect(view.lastFrame()).toContain('No logs yet');
  });

  it('clears stale status errors when viewing empty logs', async () => {
    const client = createClient({
      async status() {
        throw new Error('status unavailable');
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'status unavailable');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'No logs yet');

    expect(view.lastFrame()).toContain('No logs yet');
    expect(view.lastFrame()).not.toContain('status unavailable');
    expect(view.lastFrame()).toContain('Status unavailable');
  });

  it('ignores scan selection input while scan is running', async () => {
    let registrations = 0;
    const client = createClient({
      async scan() {
        return new Promise(() => {});
      },
      async initSelected() {
        registrations += 1;
        return {ok: true, added: [], replaced: [], skipped: [], errors: []};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Scanning...');
    view.stdin.write('\r');
    await wait();
    view.stdin.write('a');
    await wait();

    expect(registrations).toBe(0);
    expect(view.lastFrame()).toContain('Scanning...');
    expect(view.lastFrame()).not.toContain('Select at least one full scan candidate');
    expect(view.lastFrame()).not.toContain('No importable candidates to select');

    view.unmount();
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

    expect(view.lastFrame()).toContain('known.node is not importable yet (check-only)');
    expect(selected).toEqual([]);
  });

  it('shows metadata-only scan candidates with their source ref', async () => {
    const client = createClient({
      async scan() {
        return {
          candidates: [
            {
              id: 'mcp_config.filesystem',
              name: 'filesystem',
              detector: 'mcp_config',
              category: 'mcp-server',
              capability: 'metadata-only',
              confidence: 'medium',
              source_ref: 'npx'
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
    await waitForFrame(view, 'mcp_config.filesystem');

    expect(view.lastFrame()).toContain('mcp_config');
    expect(view.lastFrame()).toContain('metadata-only');
    expect(view.lastFrame()).toContain('source: npx');
  });

  it('does not repeat source refs for importable scan candidates', async () => {
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
    await waitForFrame(view, 'brew.gh');

    expect(view.lastFrame()).not.toContain('source: gh');
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

  it('cancels active scan candidate registration', async () => {
    let aborted = false;
    const client = createClient({
      async initSelected(_ids, options?: {signal?: AbortSignal}) {
        options?.signal?.addEventListener('abort', () => {
          aborted = true;
        });
        return new Promise(() => {});
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'brew.gh');
    view.stdin.write(' ');
    await waitForFrame(view, 'importable: 1/1');
    view.stdin.write('\r');
    await waitForFrame(view, 'registering scan selections');
    view.stdin.write('c');
    await wait();

    expect(aborted).toBe(true);

    view.unmount();
  });

  it('does not keep showing registration progress after registration failure', async () => {
    const client = createClient({
      async initSelected() {
        throw new Error('manifest is locked');
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'brew.gh');
    view.stdin.write(' ');
    await waitForFrame(view, 'importable: 1/1');
    view.stdin.write('\r');
    await waitForFrame(view, 'manifest is locked');

    expect(view.lastFrame()).toContain('registration failed');
    expect(view.lastFrame()).not.toContain('registering scan selections');
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

  it('does not keep showing scan progress after scan failure', async () => {
    const client = createClient({
      async scan() {
        throw new Error('scan source unavailable');
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Scan & Add');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'scan source unavailable');

    expect(view.lastFrame()).not.toContain('Scanning...');
    expect(view.lastFrame()).toContain('No scan candidates');
  });

  it('does not keep showing check progress after check failure', async () => {
    const client = createClient({
      async checkNow() {
        throw new Error('registry unavailable');
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Check Now');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'registry unavailable');

    expect(view.lastFrame()).toContain('check failed');
    expect(view.lastFrame()).not.toContain('check started');
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
            },
            {
              id: 'local.tool',
              name: 'local-tool',
              status: 'differs',
              current: 'local',
              latest: 'remote',
              last_checked: '2026-06-30T00:00:00Z'
            },
            {
              id: 'pinned.tool',
              name: 'pinned-tool',
              status: 'pinned',
              current: '1.0.0',
              latest: '1.0.0',
              last_checked: '2026-06-30T00:00:00Z'
            },
            {
              id: 'broken.tool',
              name: 'broken-tool',
              status: 'error',
              current: '1.0.0',
              latest: '2.0.0',
              last_checked: '2026-06-30T00:00:00Z',
              error: 'failed'
            }
          ],
          summary: {
            total: 4,
            outdated: 1,
            differs: 1,
            errors: 1,
            untrusted: 0,
            disabled: 0,
            pinned: 1
          }
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
    await waitForFrame(view, 'checked 4 items');

    expect(view.lastFrame()).toContain('outdated: 1');
    expect(view.lastFrame()).toContain('differs: 1');
    expect(view.lastFrame()).toContain('errors: 1');
    expect(view.lastFrame()).toContain('pinned: 1');
    expect(view.lastFrame()).toContain('differs sample: local-tool');
    expect(view.lastFrame()).toContain('error sample: broken-tool');
    expect(view.lastFrame()).toContain('error sample: broken-tool: failed');
  });

  it('hides zero check summary counts', async () => {
    const client = createClient({
      async checkNow() {
        return {
          items: [
            {
              id: 'brew.gh',
              name: 'gh',
              status: 'ok',
              current: '2.75.0',
              latest: '2.75.0',
              last_checked: '2026-06-30T00:00:00Z'
            }
          ],
          summary: {
            total: 1,
            outdated: 0,
            differs: 0,
            errors: 0,
            untrusted: 0,
            disabled: 0,
            pinned: 0
          }
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

    expect(view.lastFrame()).not.toContain('outdated: 0');
    expect(view.lastFrame()).not.toContain('errors: 0');
    expect(view.lastFrame()).not.toContain('differs: 0');
    expect(view.lastFrame()).not.toContain('pinned: 0');
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
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('c');
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(view.lastFrame()).toContain('update cancelled');
    expect(view.lastFrame()).not.toContain('exit 1');
  });

  it('shows failed update event errors in logs', async () => {
    const client = createClient({
      async updateAll(options: StreamOptions): Promise<CommandResult> {
        options.onEvent({
          event: 'failed',
          operation: 'update',
          timestamp: '2026-06-30T00:00:00Z',
          error: 'manifest lock timed out'
        });
        return {exitCode: 2, stdout: '', stderr: ''};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Run Updates');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Select updates to run');
    view.stdin.write('\r');
    await waitForFrame(view, 'Run selected updates now?');
    view.stdin.write('\r');
    await waitForFrame(view, 'manifest lock timed out');

    expect(view.lastFrame()).toContain('manifest lock timed out');
  });

  it('redacts update event errors before rendering logs', async () => {
    const secret = 'sk-or-v1-update-secret-value';
    const client = createClient({
      async updateAll(options: StreamOptions): Promise<CommandResult> {
        options.onEvent({
          event: 'failed',
          operation: 'update',
          timestamp: '2026-06-30T00:00:00Z',
          error: `failed ${secret}`
        });
        return {exitCode: 2, stdout: '', stderr: ''};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Run Updates');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Select updates to run');
    view.stdin.write('\r');
    await waitForFrame(view, 'Run selected updates now?');
    view.stdin.write('\r');
    await waitForFrame(view, '[REDACTED]');

    expect(view.lastFrame()).toContain('[REDACTED]');
    expect(view.lastFrame()).not.toContain(secret);
  });

  it('shows failed item result errors in update logs', async () => {
    const client = createClient({
      async updateAll(options: StreamOptions): Promise<CommandResult> {
        options.onEvent({
          event: 'item_finished',
          operation: 'update',
          timestamp: '2026-06-30T00:00:00Z',
          item_id: 'brew.gh',
          result: {
            id: 'brew.gh',
            name: 'gh',
            outcome: 'failed',
            error: 'brew upgrade gh failed'
          }
        });
        return {exitCode: 2, stdout: '', stderr: ''};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Run Updates');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Select updates to run');
    view.stdin.write('\r');
    await waitForFrame(view, 'Run selected updates now?');
    view.stdin.write('\r');
    await waitForFrame(view, 'brew.gh failed · brew upgrade gh failed');

    expect(view.lastFrame()).toContain('brew.gh failed · brew upgrade gh failed');
  });

  it('uses update result ids when item ids are absent from update logs', async () => {
    const client = createClient({
      async updateAll(options: StreamOptions): Promise<CommandResult> {
        options.onEvent({
          event: 'item_finished',
          operation: 'update',
          timestamp: '2026-06-30T00:00:00Z',
          result: {
            id: 'brew.gh',
            name: 'gh',
            outcome: 'updated'
          }
        });
        return {exitCode: 0, stdout: '', stderr: ''};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Run Updates');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Select updates to run');
    view.stdin.write('\r');
    await waitForFrame(view, 'Run selected updates now?');
    view.stdin.write('\r');
    await waitForFrame(view, 'brew.gh updated');

    expect(view.lastFrame()).toContain('brew.gh updated');
  });

  it('shows failed and approval-blocked counts in finished update logs', async () => {
    const client = createClient({
      async updateAll(options: StreamOptions): Promise<CommandResult> {
        options.onEvent({
          event: 'finished',
          operation: 'update',
          timestamp: '2026-06-30T00:00:00Z',
          summary: {
            total: 3,
            updated: 1,
            failed: 1,
            skipped: 1,
            skipped_untrusted: 1,
            missing: 0,
            cancelled: 0,
            hard_failures: 1
          }
        });
        return {exitCode: 3, stdout: '', stderr: ''};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Run Updates');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Select updates to run');
    view.stdin.write('\r');
    await waitForFrame(view, 'Run selected updates now?');
    view.stdin.write('\r');
    await waitForFrame(view, 'finished · updated 1/3 · failed 1 · approval 1');

    expect(view.lastFrame()).toContain('finished · updated 1/3 · failed 1 · approval 1');
  });

  it('clears stale status when update result refresh fails', async () => {
    let statusCalls = 0;
    const client = createClient({
      async status() {
        statusCalls += 1;
        if (statusCalls <= 2) {
          return {
            generated_at: '2026-06-30T00:00:00Z',
            summary: {total: 1, outdated: 1, errors: 0, untrusted: 0, pinned: 0},
            items: [
              {
                id: 'brew.gh',
                name: 'gh',
                category: 'cloud-devops',
                status: 'outdated',
                pinned: false,
                current: '2.74.0',
                latest: '2.75.0'
              }
            ]
          };
        }
        throw new Error('status unavailable after update');
      },
      async updateSelected(ids, options) {
        options.onEvent({
          event: 'finished',
          operation: 'update',
          timestamp: '2026-06-30T00:00:00Z',
          summary: {
            total: ids.length,
            updated: ids.length,
            failed: 0,
            skipped: 0,
            skipped_untrusted: 0,
            missing: 0,
            cancelled: 0,
            hard_failures: 0
          }
        });
        return {exitCode: 0, stdout: '', stderr: ''};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Run Updates');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Select updates to run');
    view.stdin.write('\r');
    await waitForFrame(view, 'Run selected updates now?');
    view.stdin.write('\r');
    await waitForFrame(view, 'status unavailable after update');

    expect(view.lastFrame()).toContain('finished · updated 1/1');
    expect(view.lastFrame()).toContain('Status unavailable');
    expect(view.lastFrame()).not.toContain('Loading status...');
    expect(view.lastFrame()).not.toContain('1 tracked · 1 outdated');
  });

  it('runs only selected outdated items from the update target screen', async () => {
    const updated: string[][] = [];
    const client = createClient({
      async status() {
        return {
          generated_at: '2026-06-30T00:00:00Z',
          summary: {total: 3, outdated: 2, errors: 0, untrusted: 0, pinned: 0},
          items: [
            {
              id: 'brew.gh',
              name: 'gh',
              category: 'cloud-devops',
              status: 'outdated',
              pinned: false,
              current: '2.74.0',
              latest: '2.75.0'
            },
            {
              id: 'npm.typescript',
              name: 'typescript',
              category: 'runtime-sdk',
              status: 'outdated',
              pinned: false,
              current: '5.8.0',
              latest: '5.9.0'
            },
            {
              id: 'known.node',
              name: 'node',
              category: 'runtime-sdk',
              status: 'ok',
              pinned: false,
              current: '24.0.0',
              latest: '24.0.0'
            }
          ]
        };
      },
      async updateSelected(ids, options) {
        updated.push(ids);
        options.onEvent({
          event: 'finished',
          operation: 'update',
          timestamp: '2026-06-30T00:00:00Z',
          summary: {
            total: ids.length,
            updated: ids.length,
            failed: 0,
            skipped: 0,
            skipped_untrusted: 0,
            missing: 0,
            cancelled: 0,
            hard_failures: 0
          }
        });
        return {exitCode: 0, stdout: '', stderr: ''};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Run Updates');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Select updates to run');
    expect(view.lastFrame()).toContain('selected: 2/2');

    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write(' ');
    await waitForFrame(view, 'selected: 1/2');
    view.stdin.write('\r');
    await waitForFrame(view, 'Run selected updates now?');
    view.stdin.write('\r');
    await waitForFrame(view, 'finished · updated 1/1');

    expect(updated).toEqual([['brew.gh']]);
  });

  it('refreshes status before showing update targets', async () => {
    let statusCalls = 0;
    const client = createClient({
      async status() {
        statusCalls += 1;
        if (statusCalls === 1) {
          return {
            generated_at: '2026-06-30T00:00:00Z',
            summary: {total: 1, outdated: 0, errors: 0, untrusted: 0, pinned: 0},
            items: [
              {
                id: 'brew.gh',
                name: 'gh',
                category: 'cloud-devops',
                status: 'ok',
                pinned: false,
                current: '2.74.0',
                latest: '2.74.0'
              }
            ]
          };
        }
        return {
          generated_at: '2026-06-30T00:01:00Z',
          summary: {total: 1, outdated: 1, errors: 0, untrusted: 0, pinned: 0},
          items: [
            {
              id: 'brew.gh',
              name: 'gh',
              category: 'cloud-devops',
              status: 'outdated',
              pinned: false,
              current: '2.74.0',
              latest: '2.75.0'
            }
          ]
        };
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, '1 tracked · 0 outdated');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Select updates to run');

    expect(view.lastFrame()).toContain('selected: 1/1');
    expect(view.lastFrame()).toContain('brew.gh · gh · 2.74.0 → 2.75.0');
  });

  it('does not show stale update targets when status refresh fails', async () => {
    let statusCalls = 0;
    const client = createClient({
      async status() {
        statusCalls += 1;
        if (statusCalls === 1) {
          return {
            generated_at: '2026-06-30T00:00:00Z',
            summary: {total: 1, outdated: 1, errors: 0, untrusted: 0, pinned: 0},
            items: [
              {
                id: 'brew.gh',
                name: 'gh',
                category: 'cloud-devops',
                status: 'outdated',
                pinned: false,
                current: '2.74.0',
                latest: '2.75.0'
              }
            ]
          };
        }
        throw new Error('status unavailable');
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, '1 tracked · 1 outdated');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'status unavailable');

    expect(view.lastFrame()).not.toContain('brew.gh · gh · 2.74.0 → 2.75.0');
  });

  it('does not run updates when no outdated items are selectable', async () => {
    let updateCalls = 0;
    const client = createClient({
      async status() {
        return {
          generated_at: '2026-06-30T00:00:00Z',
          summary: {total: 0, outdated: 0, errors: 0, untrusted: 0, pinned: 0},
          items: []
        };
      },
      async updateSelected() {
        updateCalls += 1;
        return {exitCode: 0, stdout: '', stderr: ''};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Run Updates');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'No outdated items in stored status');
    view.stdin.write('\r');
    await wait();

    expect(updateCalls).toBe(0);
  });

  it('asks for confirmation before running updates', async () => {
    let updateCalls = 0;
    const client = createClient({
      async updateSelected() {
        updateCalls += 1;
        return {exitCode: 0, stdout: '', stderr: ''};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Run Updates');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Select updates to run');
    view.stdin.write('\r');
    await waitForFrame(view, 'Run selected updates now?');

    expect(view.lastFrame()).toContain('esc cancel');
    expect(updateCalls).toBe(0);

    view.stdin.write('\r');
    await waitForFrame(view, 'update started');

    expect(updateCalls).toBe(1);
  });

  it('cancels update confirmation with escape', async () => {
    let updateCalls = 0;
    const client = createClient({
      async updateSelected() {
        updateCalls += 1;
        return {exitCode: 0, stdout: '', stderr: ''};
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Run Updates');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Select updates to run');
    view.stdin.write('\r');
    await waitForFrame(view, 'Run selected updates now?');
    view.stdin.write('\u001B');
    await waitForFrame(view, 'Refresh Status');

    expect(view.lastFrame()).toContain('Run Updates');
    expect(view.lastFrame()).not.toContain('Run approved updates now?');
    expect(updateCalls).toBe(0);
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
          summary: {total: 1, outdated: 1, errors: 0, untrusted: 0, pinned: 0},
          items: [
            {
              id: 'brew.gh',
              name: 'gh',
              category: 'cloud-devops',
              status: 'outdated',
              pinned: false
            }
          ]
        };
      },
      async updateSelected() {
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
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));
    view.stdin.write('\r');
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(view.lastFrame()).toContain('update started');
    expect(view.lastFrame()).not.toContain('status unavailable');

    view.unmount();
  });

  it('does not keep showing update progress after update failure', async () => {
    const client = createClient({
      async updateSelected() {
        throw new Error('brew update failed');
      }
    });
    const view = render(<App client={client} />);

    await waitForFrame(view, 'Run Updates');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    view.stdin.write('\u001B[B');
    await wait();
    view.stdin.write('\r');
    await waitForFrame(view, 'Select updates to run');
    view.stdin.write('\r');
    await waitForFrame(view, 'Run selected updates now?');
    view.stdin.write('\r');
    await waitForFrame(view, 'brew update failed');

    expect(view.lastFrame()).toContain('update failed');
    expect(view.lastFrame()).not.toContain('update started');
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
        summary: {total: 1, outdated: 1, errors: 0, untrusted: 0, pinned: 0},
        items: [
          {
            id: 'brew.gh',
            name: 'gh',
            category: 'cloud-devops',
            status: 'outdated',
            pinned: false,
            current: '2.74.0',
            latest: '2.75.0'
          }
        ]
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
    async updateSelected(_ids, options) {
      if (overrides.updateSelected) {
        return overrides.updateSelected(_ids, options);
      }
      if (overrides.updateAll) {
        return overrides.updateAll(options);
      }
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
