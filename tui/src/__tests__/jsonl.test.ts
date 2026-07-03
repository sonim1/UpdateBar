import {describe, expect, it} from 'vitest';
import {parseJSONLText, parseJSONLines} from '../jsonl.js';

describe('jsonl parser', () => {
  it('parses complete JSONL text', () => {
    const events = parseJSONLText(
      '{"event":"started","operation":"update","timestamp":"2026-06-30T00:00:00Z"}\n' +
        '{"event":"finished","operation":"update","timestamp":"2026-06-30T00:00:01Z"}\n'
    );

    expect(events.map(event => event.event)).toEqual(['started', 'finished']);
  });

  it('normalizes contract type to event', () => {
    const events = parseJSONLText(
      '{"type":"started","operation":"check","run_id":"run-1","timestamp":"2026-06-30T00:00:00Z"}\n'
    );

    expect(events[0]).toMatchObject({event: 'started', type: 'started', run_id: 'run-1'});
  });

  it('parses chunked lines', async () => {
    async function* chunks() {
      yield '{"event":"log","operation":"update"';
      yield ',"timestamp":"2026-06-30T00:00:00Z","message":"ok"}\n';
    }

    const events = [];
    for await (const event of parseJSONLines(chunks())) {
      events.push(event);
    }

    expect(events).toHaveLength(1);
    expect(events[0]?.message).toBe('ok');
  });

  it('reports invalid lines with line numbers', () => {
    expect(() => parseJSONLText('{')).toThrow('line 1');
  });

  it('counts blank lines when reporting text parse failures', () => {
    expect(() => parseJSONLText('\n\n{')).toThrow('line 3');
  });
});
