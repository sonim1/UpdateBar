import {spawn} from 'node:child_process';
import type {Readable} from 'node:stream';
import {resolveUpdateBarBinary} from './binaryResolver.js';
import {parseJSONLines} from './jsonl.js';
import type {InitResult, MachineEvent, ScanReport, StatusSnapshot} from './types.js';

export interface CommandResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

export interface RunOptions {
  signal?: AbortSignal;
}

export interface StreamOptions extends RunOptions {
  onEvent: (event: MachineEvent) => void;
}

export interface CommandRunner {
  run(args: string[], options?: RunOptions): Promise<CommandResult>;
  stream(args: string[], options: StreamOptions): Promise<CommandResult>;
}

export class SubprocessRunner implements CommandRunner {
  constructor(private readonly executablePath: string) {}

  async run(args: string[], options: RunOptions = {}): Promise<CommandResult> {
    const child = spawn(this.executablePath, args, {
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe']
    });
    bindAbort(child, options.signal);

    const [stdout, stderr, exitCode] = await Promise.all([
      collect(child.stdout),
      collect(child.stderr),
      waitForExit(child)
    ]);
    return {exitCode, stdout, stderr};
  }

  async stream(args: string[], options: StreamOptions): Promise<CommandResult> {
    const child = spawn(this.executablePath, args, {
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe']
    });
    bindAbort(child, options.signal);

    const stdoutEvents = (async () => {
      for await (const event of parseJSONLines(child.stdout)) {
        options.onEvent(event);
      }
    })();
    const [stderr, exitCode] = await Promise.all([
      collect(child.stderr),
      waitForExit(child),
      stdoutEvents
    ]).then(([stderrResult, exitCodeResult]) => [stderrResult, exitCodeResult] as const);
    return {exitCode, stdout: '', stderr};
  }
}

export interface UpdateBarClient {
  status(): Promise<StatusSnapshot>;
  scan(): Promise<ScanReport>;
  initSelected(ids: string[]): Promise<InitResult>;
  checkNow(): Promise<void>;
  updateAll(options: StreamOptions): Promise<CommandResult>;
}

export class CLIUpdateBarClient implements UpdateBarClient {
  constructor(private readonly runner: CommandRunner) {}

  async status(): Promise<StatusSnapshot> {
    const result = await this.runner.run(['status', '--json', '--exit-zero-on-outdated']);
    ensureExit(result, [0, 10]);
    return JSON.parse(result.stdout) as StatusSnapshot;
  }

  async scan(): Promise<ScanReport> {
    const result = await this.runner.run(['scan', '--json']);
    ensureExit(result, [0]);
    return JSON.parse(result.stdout) as ScanReport;
  }

  async initSelected(ids: string[]): Promise<InitResult> {
    const result = await this.runner.run(['init', '--select', ids.join(','), '--json']);
    ensureExit(result, [0]);
    return JSON.parse(result.stdout) as InitResult;
  }

  async checkNow(): Promise<void> {
    const result = await this.runner.run(['check', '--json', '--force', '--exit-zero-on-outdated']);
    ensureExit(result, [0, 10]);
  }

  async updateAll(options: StreamOptions): Promise<CommandResult> {
    const result = await this.runner.stream(['update', '--all', '--yes', '--json-stream'], options);
    ensureExit(result, [0, 2, 3]);
    return result;
  }
}

export async function createDefaultClient(): Promise<UpdateBarClient> {
  const resolution = await resolveUpdateBarBinary();
  return new CLIUpdateBarClient(new SubprocessRunner(resolution.path));
}

function ensureExit(result: CommandResult, allowed: number[]) {
  if (!allowed.includes(result.exitCode)) {
    const detail = result.stderr.trim() || `exit ${result.exitCode}`;
    throw new Error(detail);
  }
}

function bindAbort(child: ReturnType<typeof spawn>, signal: AbortSignal | undefined) {
  if (!signal) return;
  let exited = false;
  child.once('close', () => {
    exited = true;
  });
  const cancel = () => {
    child.kill('SIGINT');
    const timer = setTimeout(() => {
      if (!exited) child.kill('SIGTERM');
    }, 2000);
    timer.unref();
  };
  if (signal.aborted) {
    cancel();
    return;
  }
  signal.addEventListener('abort', cancel, {once: true});
}

async function collect(stream: Readable | null): Promise<string> {
  if (!stream) return '';
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk)));
  }
  return Buffer.concat(chunks).toString('utf8');
}

function waitForExit(child: ReturnType<typeof spawn>): Promise<number> {
  return new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', code => resolve(code ?? 1));
  });
}
