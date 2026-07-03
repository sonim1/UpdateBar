import type {MachineEvent, MachineEventType} from './types.js';

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
    return {...value, event, type: value.type ?? event} as MachineEvent;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`invalid JSONL event on line ${lineNumber}: ${message}`);
  }
}
