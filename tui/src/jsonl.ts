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

  for await (const chunk of chunks) {
    buffer += chunk.toString();
    let newline = buffer.indexOf('\n');
    while (newline >= 0) {
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      lineNumber += 1;
      if (line.length > 0) yield parseLine(line, lineNumber);
      newline = buffer.indexOf('\n');
    }
  }

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
    if (typeof value.timestamp !== 'string') {
      throw new Error('missing timestamp');
    }
    if (value.result !== undefined && !isUpdateResult(value.result)) {
      throw new Error('invalid result');
    }
    if (value.summary !== undefined && !isUpdateSummary(value.summary)) {
      throw new Error('invalid summary');
    }
    if (value.check_result !== undefined && !isCheckResult(value.check_result)) {
      throw new Error('invalid check_result');
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
