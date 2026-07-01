import React from 'react';
import {PassThrough, Writable} from 'node:stream';
import {render as renderInk} from 'ink';
import {render} from 'ink-testing-library';
import {describe, expect, it} from 'vitest';
import {App} from '../App.js';
import type {UpdateBarClient} from '../client.js';

describe('App', () => {
  it('renders status summary from the client', async () => {
    const client: UpdateBarClient = {
      async status() {
        return {
          generated_at: '2026-06-30T00:00:00Z',
          summary: {total: 2, outdated: 1, errors: 0},
          items: []
        };
      },
      async checkNow() {},
      async updateAll() {
        return {exitCode: 0, stdout: '', stderr: ''};
      }
    };

    const view = render(<App client={client} />);
    await new Promise(resolve => setTimeout(resolve, 20));

    expect(view.lastFrame()).toContain('2 tracked · 1 outdated · 0 errors');
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

function createClient(): UpdateBarClient {
  return {
    async status() {
      return {
        generated_at: '2026-06-30T00:00:00Z',
        summary: {total: 0, outdated: 0, errors: 0},
        items: []
      };
    },
    async checkNow() {},
    async updateAll() {
      return {exitCode: 0, stdout: '', stderr: ''};
    }
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
