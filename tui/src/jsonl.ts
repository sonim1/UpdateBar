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
const ISO_TIMESTAMP_PATTERN = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$/;

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
    if (!isValidMachineTimestamp(value.timestamp)) {
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
    isNonNegativeInteger(value.total) &&
    isNonNegativeInteger(value.updated) &&
    isNonNegativeInteger(value.failed) &&
    isNonNegativeInteger(value.skipped) &&
    isNonNegativeInteger(value.skipped_untrusted) &&
    isNonNegativeInteger(value.missing) &&
    isNonNegativeInteger(value.cancelled) &&
    isNonNegativeInteger(value.hard_failures)
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
    isNonNegativeInteger(value.total) &&
    isNonNegativeInteger(value.outdated) &&
    isNonNegativeInteger(value.errors) &&
    isNonNegativeInteger(value.untrusted) &&
    isNonNegativeInteger(value.disabled) &&
    isNonNegativeInteger(value.pinned) &&
    isNonNegativeInteger(value.differs)
  );
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function isOptionalString(value: unknown) {
  return value === undefined || typeof value === 'string';
}

function isNonNegativeInteger(value: unknown) {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0;
}

export function isValidMachineTimestamp(value: string) {
  const match = ISO_TIMESTAMP_PATTERN.exec(value);
  if (!match) return false;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const offsetHour = match[7] === undefined ? 0 : Number(match[7]);
  const offsetMinute = match[8] === undefined ? 0 : Number(match[8]);

  return (
    month >= 1 &&
    month <= 12 &&
    day >= 1 &&
    day <= daysInMonth(year, month) &&
    hour >= 0 &&
    hour <= 23 &&
    minute >= 0 &&
    minute <= 59 &&
    second >= 0 &&
    second <= 59 &&
    offsetHour >= 0 &&
    offsetHour <= 23 &&
    offsetMinute >= 0 &&
    offsetMinute <= 59 &&
    !Number.isNaN(Date.parse(value))
  );
}

function daysInMonth(year: number, month: number) {
  const days = [31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return days[month - 1] ?? 0;
}

function isLeapYear(year: number) {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
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
