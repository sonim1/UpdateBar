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

  it('rejects unknown event names with line numbers', () => {
    expect(() =>
      parseJSONLText('{"event":"surprise","operation":"update","timestamp":"2026-06-30T00:00:00Z"}')
    ).toThrow('line 1');
  });

  it('rejects mismatched event aliases with line numbers', () => {
    expect(() =>
      parseJSONLText(
        '{"event":"started","type":"finished","operation":"update","timestamp":"2026-06-30T00:00:00Z"}'
      )
    ).toThrow('line 1');
  });

  it('rejects unknown operation names with line numbers', () => {
    expect(() =>
      parseJSONLText('{"event":"started","operation":"install","timestamp":"2026-06-30T00:00:00Z"}')
    ).toThrow('line 1');
  });

  it('rejects missing timestamps with line numbers', () => {
    expect(() => parseJSONLText('{"event":"started","operation":"update"}')).toThrow('line 1');
  });

  it('rejects unknown update result outcomes with line numbers', () => {
    expect(() =>
      parseJSONLText(
        '{"event":"item_finished","operation":"update","timestamp":"2026-06-30T00:00:00Z","result":{"id":"brew.gh","name":"gh","outcome":"mystery"}}'
      )
    ).toThrow('line 1');
  });

  it('rejects invalid update summaries with line numbers', () => {
    expect(() =>
      parseJSONLText(
        '{"event":"finished","operation":"update","timestamp":"2026-06-30T00:00:00Z","summary":{"total":"1","updated":1,"failed":0,"skipped":0,"skipped_untrusted":0,"missing":0,"cancelled":0,"hard_failures":0}}'
      )
    ).toThrow('line 1');
  });

  it('rejects invalid update result arrays with line numbers', () => {
    expect(() =>
      parseJSONLText(
        '{"event":"finished","operation":"update","timestamp":"2026-06-30T00:00:00Z","results":[{"id":"brew.gh","name":"gh","outcome":"mystery"}]}'
      )
    ).toThrow('line 1');
  });

  it('rejects unknown check result statuses with line numbers', () => {
    expect(() =>
      parseJSONLText(
        '{"event":"item_finished","operation":"check","timestamp":"2026-06-30T00:00:00Z","check_result":{"id":"brew.gh","name":"gh","status":"mystery"}}'
      )
    ).toThrow('line 1');
  });

  it('rejects invalid check summaries with line numbers', () => {
    expect(() =>
      parseJSONLText(
        '{"event":"finished","operation":"check","timestamp":"2026-06-30T00:00:00Z","check_summary":{"total":1,"outdated":"1","errors":0,"untrusted":0,"disabled":0,"pinned":0,"differs":0}}'
      )
    ).toThrow('line 1');
  });

  it('rejects invalid check result arrays with line numbers', () => {
    expect(() =>
      parseJSONLText(
        '{"event":"finished","operation":"check","timestamp":"2026-06-30T00:00:00Z","check_results":[{"id":"brew.gh","name":"gh","status":"mystery"}]}'
      )
    ).toThrow('line 1');
  });

  it('counts blank lines when reporting text parse failures', () => {
    expect(() => parseJSONLText('\n\n{')).toThrow('line 3');
  });
});
