import {describe, expect, it} from 'vitest';
import {
  CLIUpdateBarClient,
  SubprocessRunner,
  type CommandRunner,
  type StreamOptions
} from '../client.js';
import type {MachineEvent} from '../types.js';

describe('CLIUpdateBarClient', () => {
  it('reads status JSON through the Swift CLI contract', async () => {
    const runner = new FakeRunner({
      exitCode: 10,
      stdout:
        '{"generated_at":"2026-06-30T00:00:00Z","summary":{"total":1,"outdated":1,"errors":0},"items":[]}',
      stderr: ''
    });
    const client = new CLIUpdateBarClient(runner);

    const status = await client.status();

    expect(status.summary.outdated).toBe(1);
    expect(runner.calls[0]).toEqual(['status', '--json', '--exit-zero-on-outdated']);
  });

  it('streams update events through the Swift CLI contract', async () => {
    const runner = new FakeRunner({exitCode: 0, stdout: '', stderr: ''});
    runner.events = [
      {event: 'started', operation: 'update', timestamp: '2026-06-30T00:00:00Z'},
      {event: 'finished', operation: 'update', timestamp: '2026-06-30T00:00:01Z'}
    ];
    const client = new CLIUpdateBarClient(runner);
    const events: string[] = [];

    await client.updateAll({onEvent: event => events.push(event.event)});

    expect(events).toEqual(['started', 'finished']);
    expect(runner.calls[0]).toEqual(['update', '--all', '--yes', '--json-stream']);
  });

  it('cancels subprocesses with AbortSignal', async () => {
    const runner = new SubprocessRunner('/bin/sh');
    const controller = new AbortController();
    setTimeout(() => controller.abort(), 50);

    const result = await runner.run(['-c', 'sleep 5'], {signal: controller.signal});

    expect(result.exitCode).not.toBe(0);
  });
});

class FakeRunner implements CommandRunner {
  calls: string[][] = [];
  events: MachineEvent[] = [];

  constructor(private readonly result: {exitCode: number; stdout: string; stderr: string}) {}

  async run(args: string[]) {
    this.calls.push(args);
    return this.result;
  }

  async stream(args: string[], options: StreamOptions) {
    this.calls.push(args);
    for (const event of this.events as Array<Parameters<StreamOptions['onEvent']>[0]>) {
      options.onEvent(event);
    }
    return this.result;
  }
}
