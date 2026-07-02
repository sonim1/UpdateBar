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
    expect(status.summary.untrusted).toBe(0);
    expect(status.summary.pinned).toBe(0);
    expect(status.summary.disabled).toBe(0);
    expect(status.summary.checking).toBe(0);
    expect(status.summary.differs).toBe(0);
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
    expect(runner.calls[0]).toEqual(['update', '--yes', '--json-stream']);
  });

  it('reads scan candidates through the Swift CLI contract', async () => {
    const runner = new FakeRunner({
      exitCode: 0,
      stdout:
        '{"candidates":[{"id":"brew.gh","name":"gh","detector":"brew","category":"cloud-devops","capability":"full","confidence":"high","installed_version":"2.74.0","source_ref":"gh","recipe":{}}],"errors":[]}',
      stderr: ''
    });
    const client = new CLIUpdateBarClient(runner);

    const report = await client.scan();

    expect(report.candidates[0]?.id).toBe('brew.gh');
    expect(runner.calls[0]).toEqual(['scan', '--json']);
  });

  it('reports unexpected scan JSON shape with command context', async () => {
    const runner = new FakeRunner({exitCode: 0, stdout: '{"ok":true}', stderr: ''});
    const client = new CLIUpdateBarClient(runner);

    await expect(client.scan()).rejects.toThrow('unexpected scan result format from updatebar');
  });

  it('passes cancellation to scan commands', async () => {
    const runner = new FakeRunner({
      exitCode: 0,
      stdout: '{"candidates":[],"errors":[]}',
      stderr: ''
    });
    const client = new CLIUpdateBarClient(runner);
    const controller = new AbortController();

    await client.scan({signal: controller.signal});

    expect(runner.runOptions[0]?.signal).toBe(controller.signal);
  });

  it('registers selected scan candidates through the Swift CLI contract', async () => {
    const runner = new FakeRunner({
      exitCode: 0,
      stdout: '{"ok":true,"added":["brew.gh"],"replaced":[],"skipped":[],"errors":[]}',
      stderr: ''
    });
    const client = new CLIUpdateBarClient(runner);

    const result = await client.initSelected(['brew.gh']);

    expect(result.added).toEqual(['brew.gh']);
    expect(runner.calls[0]).toEqual(['init', '--select', 'brew.gh', '--json']);
  });

  it('reports unexpected init JSON shape with command context', async () => {
    const runner = new FakeRunner({exitCode: 0, stdout: '{"ok":true}', stderr: ''});
    const client = new CLIUpdateBarClient(runner);

    await expect(client.initSelected(['brew.gh'])).rejects.toThrow(
      'unexpected init result format from updatebar'
    );
  });

  it('passes cancellation to check commands', async () => {
    const runner = new FakeRunner({exitCode: 0, stdout: '[]', stderr: ''});
    const client = new CLIUpdateBarClient(runner);
    const controller = new AbortController();

    await client.checkNow({signal: controller.signal});

    expect(runner.runOptions[0]?.signal).toBe(controller.signal);
  });

  it('reports invalid status JSON with command context', async () => {
    const runner = new FakeRunner({exitCode: 0, stdout: 'not json', stderr: ''});
    const client = new CLIUpdateBarClient(runner);

    await expect(client.status()).rejects.toThrow('updatebar status returned invalid JSON');
  });

  it('reports unexpected status JSON shape with command context', async () => {
    const runner = new FakeRunner({exitCode: 0, stdout: '{"ok":true}', stderr: ''});
    const client = new CLIUpdateBarClient(runner);

    await expect(client.status()).rejects.toThrow('unexpected status result format from updatebar');
  });

  it('summarizes differs check results from the Swift CLI contract', async () => {
    const runner = new FakeRunner({
      exitCode: 10,
      stdout:
        '[{"id":"brew.gh","name":"gh","current":"2.74.0","latest":"2.75.0","status":"differs","last_checked":"2026-06-30T00:00:00Z"}]',
      stderr: ''
    });
    const client = new CLIUpdateBarClient(runner);

    const report = await client.checkNow();

    expect(report.summary.total).toBe(1);
    expect(report.summary.outdated).toBe(0);
    expect(report.summary.differs).toBe(1);
  });

  it('surfaces JSON error payloads from failed commands', async () => {
    const runner = new FakeRunner({
      exitCode: 1,
      stdout: '{"ok":false,"added":[],"replaced":[],"skipped":[],"errors":["brew.gh: duplicate item"]}',
      stderr: ''
    });
    const client = new CLIUpdateBarClient(runner);

    await expect(client.initSelected(['brew.gh'])).rejects.toThrow('brew.gh: duplicate item');
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
  runOptions: Array<{signal?: AbortSignal} | undefined> = [];
  events: MachineEvent[] = [];

  constructor(private readonly result: {exitCode: number; stdout: string; stderr: string}) {}

  async run(args: string[], options?: {signal?: AbortSignal}) {
    this.calls.push(args);
    this.runOptions.push(options);
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
