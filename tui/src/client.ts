import {spawn} from 'node:child_process';
import type {Readable} from 'node:stream';
import {resolveUpdateBarBinary} from './binaryResolver.js';
import type {BinaryResolverOptions} from './binaryResolver.js';
import {parseJSONLines} from './jsonl.js';
import type {
  CheckReport,
  CheckSummary,
  CheckResult,
  InitResult,
  ItemStatus,
  MachineEvent,
  ScanCandidate,
  ScanError,
  ScanReport,
  StatusItem,
  StatusSnapshot
} from './types.js';

const ITEM_STATUSES = new Set<ItemStatus>([
  'ok',
  'outdated',
  'differs',
  'error',
  'pinned',
  'disabled',
  'checking',
  'untrusted'
]);

const SCAN_DETECTORS = new Set<ScanCandidate['detector']>([
  'brew',
  'npm_global',
  'known',
  'codex_skill',
  'mcp_config'
]);

const SCAN_CAPABILITIES = new Set<ScanCandidate['capability']>([
  'full',
  'check-only',
  'metadata-only',
  'unsupported'
]);

const SCAN_CONFIDENCES = new Set<ScanCandidate['confidence']>(['high', 'medium', 'low']);

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
    let exited = false;
    child.once('close', () => {
      exited = true;
    });
    bindAbort(child, options.signal);

    const stdoutEvents = (async () => {
      try {
        for await (const event of parseJSONLines(child.stdout)) {
          options.onEvent(event);
        }
      } catch (error) {
        stopChild(child, () => exited, 250);
        throw error;
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
  scan(options?: RunOptions): Promise<ScanReport>;
  initSelected(ids: string[], options?: RunOptions): Promise<InitResult>;
  checkNow(options?: RunOptions): Promise<CheckReport>;
  updateAll(options: StreamOptions): Promise<CommandResult>;
}

export class CLIUpdateBarClient implements UpdateBarClient {
  constructor(private readonly runner: CommandRunner) {}

  async status(): Promise<StatusSnapshot> {
    const result = await this.runner.run(['status', '--json', '--exit-zero-on-outdated']);
    ensureExit(result, [0, 10]);
    return normalizeStatusSnapshot(parseStatusSnapshot(result.stdout));
  }

  async scan(options: RunOptions = {}): Promise<ScanReport> {
    const result = await this.runner.run(['scan', '--json'], options);
    ensureExit(result, [0]);
    return parseScanReport(result.stdout);
  }

  async initSelected(ids: string[], options: RunOptions = {}): Promise<InitResult> {
    if (ids.length === 0) {
      throw new Error('select at least one scan candidate');
    }
    const result = await this.runner.run(['init', '--select', ids.join(','), '--json'], options);
    ensureExit(result, [0]);
    return parseInitResult(result.stdout);
  }

  async checkNow(options: RunOptions = {}): Promise<CheckReport> {
    const result = await this.runner.run(
      ['check', '--json', '--force', '--exit-zero-on-outdated'],
      options
    );
    ensureExit(result, [0, 10]);
    const parsed = parseJSON<unknown>(result.stdout, 'check');
    if (!Array.isArray(parsed)) {
      throw new Error('unexpected check result format from updatebar');
    }
    const results = parseCheckResults(parsed);
    return {
      items: results,
      summary: summarizeCheck(results)
    };
  }

  async updateAll(options: StreamOptions): Promise<CommandResult> {
    let streamError: string | undefined;
    const result = await this.runner.stream(['update', '--yes', '--json-stream'], {
      ...options,
      onEvent: event => {
        if (event.error?.trim()) {
          streamError = event.error.trim();
        }
        options.onEvent(event);
      }
    });
    ensureExit(result, [0, 2, 3], streamError);
    return result;
  }
}

export async function createDefaultClient(
  options: BinaryResolverOptions = {}
): Promise<UpdateBarClient> {
  const resolution = await resolveUpdateBarBinary(options);
  return new CLIUpdateBarClient(new SubprocessRunner(resolution.path));
}

function ensureExit(result: CommandResult, allowed: number[], fallbackDetail?: string) {
  if (!allowed.includes(result.exitCode)) {
    const detail =
      stdoutError(result.stdout) ||
      fallbackDetail?.trim() ||
      result.stderr.trim() ||
      `exit ${result.exitCode}`;
    throw new Error(detail);
  }
}

function stdoutError(stdout: string): string | undefined {
  try {
    const payload = JSON.parse(stdout) as {errors?: unknown; error?: unknown};
    if (Array.isArray(payload.errors) && payload.errors.length > 0) {
      return payload.errors.map(String).join('\n');
    }
    if (typeof payload.error === 'string' && payload.error.length > 0) {
      return payload.error;
    }
  } catch {
    return undefined;
  }
  return undefined;
}

function bindAbort(child: ReturnType<typeof spawn>, signal: AbortSignal | undefined) {
  if (!signal) return;
  let exited = false;
  child.once('close', () => {
    exited = true;
  });
  const cancel = () => {
    stopChild(child, () => exited);
  };
  if (signal.aborted) {
    cancel();
    return;
  }
  signal.addEventListener('abort', cancel, {once: true});
}

function stopChild(
  child: ReturnType<typeof spawn>,
  isExited: () => boolean,
  terminateAfterMs = 2000
) {
  if (isExited()) return;
  child.kill('SIGINT');
  const timer = setTimeout(() => {
    if (!isExited()) child.kill('SIGTERM');
  }, terminateAfterMs);
  timer.unref();
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

function parseJSON<T>(payload: string, command: string): T {
  try {
    return JSON.parse(payload) as T;
  } catch {
    throw new Error(`updatebar ${command} returned invalid JSON`);
  }
}

function parseStatusSnapshot(payload: string): StatusSnapshot {
  const snapshot = parseJSON<unknown>(payload, 'status');
  if (
    !isObject(snapshot) ||
    typeof snapshot.generated_at !== 'string' ||
    !isStatusSummary(snapshot.summary) ||
    !Array.isArray(snapshot.items) ||
    !snapshot.items.every(isStatusItem)
  ) {
    throw new Error('unexpected status result format from updatebar');
  }
  return snapshot as unknown as StatusSnapshot;
}

function parseScanReport(payload: string): ScanReport {
  const report = parseJSON<unknown>(payload, 'scan');
  if (
    !isObject(report) ||
    !Array.isArray(report.candidates) ||
    !Array.isArray(report.errors) ||
    !report.candidates.every(isScanCandidate) ||
    !report.errors.every(isScanError)
  ) {
    throw new Error('unexpected scan result format from updatebar');
  }
  return report as unknown as ScanReport;
}

function parseInitResult(payload: string): InitResult {
  const result = parseJSON<unknown>(payload, 'init');
  if (
    !isObject(result) ||
    typeof result.ok !== 'boolean' ||
    !isStringArray(result.added) ||
    !isStringArray(result.replaced) ||
    !isStringArray(result.skipped) ||
    !isStringArray(result.errors)
  ) {
    throw new Error('unexpected init result format from updatebar');
  }
  return result as unknown as InitResult;
}

function isStatusSummary(value: unknown): value is StatusSnapshot['summary'] {
  if (!isObject(value)) return false;
  return (
    typeof value.total === 'number' &&
    typeof value.outdated === 'number' &&
    typeof value.errors === 'number' &&
    isOptionalNumber(value.untrusted) &&
    isOptionalNumber(value.pinned) &&
    isOptionalNumber(value.disabled) &&
    isOptionalNumber(value.checking) &&
    isOptionalNumber(value.differs)
  );
}

function parseCheckResults(results: unknown[]): CheckResult[] {
  if (!results.every(isCheckResult)) {
    throw new Error('unexpected check result format from updatebar');
  }
  return results;
}

function isStatusItem(value: unknown): value is StatusItem {
  if (!isObject(value)) return false;
  return (
    typeof value.id === 'string' &&
    typeof value.name === 'string' &&
    typeof value.category === 'string' &&
    typeof value.status === 'string' &&
    typeof value.pinned === 'boolean' &&
    ITEM_STATUSES.has(value.status as ItemStatus) &&
    isOptionalString(value.current) &&
    isOptionalString(value.latest) &&
    isOptionalString(value.last_checked) &&
    isOptionalString(value.error)
  );
}

function isScanCandidate(value: unknown): value is ScanCandidate {
  if (!isObject(value)) return false;
  return (
    typeof value.id === 'string' &&
    typeof value.name === 'string' &&
    typeof value.detector === 'string' &&
    typeof value.category === 'string' &&
    typeof value.capability === 'string' &&
    typeof value.confidence === 'string' &&
    SCAN_DETECTORS.has(value.detector as ScanCandidate['detector']) &&
    SCAN_CAPABILITIES.has(value.capability as ScanCandidate['capability']) &&
    SCAN_CONFIDENCES.has(value.confidence as ScanCandidate['confidence']) &&
    isOptionalString(value.installed_version) &&
    isOptionalString(value.source_ref)
  );
}

function isScanError(value: unknown): value is ScanError {
  if (!isObject(value)) return false;
  return (
    typeof value.detector === 'string' &&
    typeof value.message === 'string' &&
    SCAN_DETECTORS.has(value.detector as ScanError['detector'])
  );
}

function isCheckResult(value: unknown): value is CheckResult {
  if (!isObject(value)) return false;
  return (
    typeof value.id === 'string' &&
    typeof value.name === 'string' &&
    typeof value.status === 'string' &&
    ITEM_STATUSES.has(value.status as ItemStatus) &&
    isOptionalString(value.current) &&
    isOptionalString(value.latest) &&
    isOptionalString(value.last_checked) &&
    isOptionalString(value.error)
  );
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(item => typeof item === 'string');
}

function isOptionalString(value: unknown) {
  return value === undefined || typeof value === 'string';
}

function isOptionalNumber(value: unknown) {
  return value === undefined || typeof value === 'number';
}

function normalizeStatusSnapshot(snapshot: StatusSnapshot): StatusSnapshot {
  return {
    ...snapshot,
    summary: {
      ...snapshot.summary,
      untrusted: snapshot.summary.untrusted ?? 0,
      pinned: snapshot.summary.pinned ?? 0,
      disabled: snapshot.summary.disabled ?? 0,
      checking: snapshot.summary.checking ?? 0,
      differs: snapshot.summary.differs ?? 0
    }
  };
}

function summarizeCheck(results: CheckResult[]): CheckSummary {
  const summary: CheckSummary = {
    total: results.length,
    outdated: 0,
    errors: 0,
    untrusted: 0,
    disabled: 0,
    pinned: 0,
    differs: 0
  };

  for (const result of results) {
    if (result.status === 'error') summary.errors += 1;
    if (result.status === 'outdated') summary.outdated += 1;
    if (result.status === 'pinned') summary.pinned += 1;
    if (result.status === 'disabled') summary.disabled += 1;
    if (result.status === 'untrusted') summary.untrusted += 1;
    if (result.status === 'differs') summary.differs += 1;
  }

  return summary;
}
