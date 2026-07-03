import {StringDecoder} from 'node:string_decoder';
import type {
  CheckResult,
  CheckSummary,
  ItemStatus,
  MachineEvent,
  MachineEventType,
  UpdateOutcome,
  UpdateResult,
  UpdateSummary
} from './types.js';

const MACHINE_EVENT_TYPES = new Set<MachineEventType>([
  'started',
  'item_started',
  'log',
  'item_finished',
  'cancelled',
  'failed',
  'finished'
]);

const MACHINE_OPERATIONS = new Set<MachineEvent['operation']>(['update', 'check']);
const ISO_TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

const MACHINE_LOG_LEVELS = new Set<NonNullable<MachineEvent['level']>>([
  'debug',
  'info',
  'warning',
  'error'
]);

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

const UPDATE_OUTCOMES = new Set<UpdateOutcome>([
  'updated',
  'failed',
  'skipped_pinned',
  'skipped_disabled',
  'skipped_untrusted',
  'skipped_not_outdated',
  'missing',
  'cancelled'
]);

export async function* parseJSONLines(
  chunks: AsyncIterable<Buffer | string>
): AsyncGenerator<MachineEvent> {
  let buffer = '';
  let lineNumber = 0;
  let decoder = new StringDecoder('utf8');

  for await (const chunk of chunks) {
    if (typeof chunk === 'string') {
      buffer += decoder.end() + chunk;
      decoder = new StringDecoder('utf8');
    } else {
      buffer += decoder.write(chunk);
    }
    let newline = buffer.indexOf('\n');
    while (newline >= 0) {
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      lineNumber += 1;
      if (line.length > 0) yield parseLine(line, lineNumber);
      newline = buffer.indexOf('\n');
    }
  }

  buffer += decoder.end();
  const tail = buffer.trim();
  if (tail.length > 0) {
    lineNumber += 1;
    yield parseLine(tail, lineNumber);
  }
}

export function parseJSONLText(text: string): MachineEvent[] {
  const events: MachineEvent[] = [];
  for (const [index, rawLine] of text.split('\n').entries()) {
    const line = rawLine.trim();
    if (line.length > 0) events.push(parseLine(line, index + 1));
  }
  return events;
}

function parseLine(line: string, lineNumber: number): MachineEvent {
  try {
    const value = JSON.parse(line) as Partial<MachineEvent>;
    const event = typeof value.event === 'string' ? value.event : value.type;
    if (typeof event !== 'string') {
      throw new Error('missing event');
    }
    if (
      typeof value.event === 'string' &&
      typeof value.type === 'string' &&
      value.event !== value.type
    ) {
      throw new Error(`event/type mismatch ${value.event}/${value.type}`);
    }
    if (!MACHINE_EVENT_TYPES.has(event as MachineEventType)) {
      throw new Error(`unknown event ${event}`);
    }
    if (typeof value.operation !== 'string') {
      throw new Error('missing operation');
    }
    if (!MACHINE_OPERATIONS.has(value.operation as MachineEvent['operation'])) {
      throw new Error(`unknown operation ${value.operation}`);
    }
    const operation = value.operation as MachineEvent['operation'];
    if (typeof value.timestamp !== 'string') {
      throw new Error('missing timestamp');
    }
    if (!isValidTimestamp(value.timestamp)) {
      throw new Error('invalid timestamp');
    }
    if (!isOptionalString(value.run_id)) {
      throw new Error('invalid run_id');
    }
    if (!isOptionalString(value.item_id)) {
      throw new Error('invalid item_id');
    }
    if (!isOptionalString(value.message)) {
      throw new Error('invalid message');
    }
    if (!isOptionalString(value.error)) {
      throw new Error('invalid error');
    }
    if (
      value.level !== undefined &&
      (typeof value.level !== 'string' ||
        !MACHINE_LOG_LEVELS.has(value.level as NonNullable<MachineEvent['level']>))
    ) {
      throw new Error('invalid level');
    }
    if (operation === 'check' && hasUpdatePayload(value)) {
      throw new Error('unexpected update payload for check operation');
    }
    if (operation === 'update' && hasCheckPayload(value)) {
      throw new Error('unexpected check payload for update operation');
    }
    if (value.result !== undefined && !isUpdateResult(value.result)) {
      throw new Error('invalid result');
    }
    if (value.results !== undefined && !isUpdateResults(value.results)) {
      throw new Error('invalid results');
    }
    if (value.summary !== undefined && !isUpdateSummary(value.summary)) {
      throw new Error('invalid summary');
    }
    if (value.check_result !== undefined && !isCheckResult(value.check_result)) {
      throw new Error('invalid check_result');
    }
    if (value.check_results !== undefined && !isCheckResults(value.check_results)) {
      throw new Error('invalid check_results');
    }
    if (value.check_summary !== undefined && !isCheckSummary(value.check_summary)) {
      throw new Error('invalid check_summary');
    }
    return {...value, event, type: value.type ?? event} as MachineEvent;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`invalid JSONL event on line ${lineNumber}: ${message}`);
  }
}

function isUpdateResult(value: unknown): value is UpdateResult {
  if (!isObject(value)) return false;
  return (
    typeof value.id === 'string' &&
    typeof value.name === 'string' &&
    typeof value.outcome === 'string' &&
    UPDATE_OUTCOMES.has(value.outcome as UpdateOutcome)
  );
}

function isUpdateResults(value: unknown): value is UpdateResult[] {
  return Array.isArray(value) && value.every(isUpdateResult);
}

function isUpdateSummary(value: unknown): value is UpdateSummary {
  if (!isObject(value)) return false;
  return (
    typeof value.total === 'number' &&
    typeof value.updated === 'number' &&
    typeof value.failed === 'number' &&
    typeof value.skipped === 'number' &&
    typeof value.skipped_untrusted === 'number' &&
    typeof value.missing === 'number' &&
    typeof value.cancelled === 'number' &&
    typeof value.hard_failures === 'number'
  );
}

function isCheckResult(value: unknown): value is CheckResult {
  if (!isObject(value)) return false;
  return (
    typeof value.id === 'string' &&
    typeof value.name === 'string' &&
    typeof value.status === 'string' &&
    ITEM_STATUSES.has(value.status as ItemStatus)
  );
}

function isCheckResults(value: unknown): value is CheckResult[] {
  return Array.isArray(value) && value.every(isCheckResult);
}

function isCheckSummary(value: unknown): value is CheckSummary {
  if (!isObject(value)) return false;
  return (
    typeof value.total === 'number' &&
    typeof value.outdated === 'number' &&
    typeof value.errors === 'number' &&
    typeof value.untrusted === 'number' &&
    typeof value.disabled === 'number' &&
    typeof value.pinned === 'number' &&
    typeof value.differs === 'number'
  );
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function isOptionalString(value: unknown) {
  return value === undefined || typeof value === 'string';
}

function isValidTimestamp(value: string) {
  return ISO_TIMESTAMP_PATTERN.test(value) && !Number.isNaN(Date.parse(value));
}

function hasUpdatePayload(value: Partial<MachineEvent>) {
  return value.result !== undefined || value.results !== undefined || value.summary !== undefined;
}

function hasCheckPayload(value: Partial<MachineEvent>) {
  return (
    value.check_result !== undefined ||
    value.check_results !== undefined ||
    value.check_summary !== undefined
  );
}
