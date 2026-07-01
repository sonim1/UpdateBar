import type {MachineEvent} from './types.js';

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
  return text
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)
    .map((line, index) => parseLine(line, index + 1));
}

function parseLine(line: string, lineNumber: number): MachineEvent {
  try {
    const value = JSON.parse(line) as Partial<MachineEvent>;
    const event = typeof value.event === 'string' ? value.event : value.type;
    if (typeof event !== 'string') {
      throw new Error('missing event');
    }
    return {...value, event, type: value.type ?? event} as MachineEvent;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`invalid JSONL event on line ${lineNumber}: ${message}`);
  }
}
