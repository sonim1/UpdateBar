import React, {useEffect, useRef, useState} from 'react';
import path from 'node:path';
import {Box, Text, useApp, useInput, useStdin} from 'ink';
import {createDefaultClient, type UpdateBarClient} from './client.js';
import {redactSecrets} from './secrets.js';
import type {CheckReport, MachineEvent, ScanCandidate, ScanReport, StatusItem, StatusSnapshot} from './types.js';

type Screen = 'menu' | 'status' | 'logs' | 'scan' | 'select-update' | 'confirm-update' | 'updating';
type MenuAction =
  | 'refresh-status'
  | 'scan-add'
  | 'check-now'
  | 'run-updates'
  | 'config-path'
  | 'view-logs'
  | 'quit';
type SummaryCountField<TKey extends string> = readonly [TKey, string];
type CheckSummaryCountKey = Exclude<Extract<keyof CheckReport['summary'], string>, 'total'>;
type StatusSummaryCountKey = Exclude<Extract<keyof StatusSnapshot['summary'], string>, 'total' | 'outdated'>;

const CHECK_SUMMARY_COUNT_FIELDS: Array<SummaryCountField<CheckSummaryCountKey>> = [
  ['outdated', 'outdated'],
  ['errors', 'errors'],
  ['untrusted', 'untrusted'],
  ['differs', 'differs'],
  ['pinned', 'pinned'],
  ['disabled', 'disabled']
];

const STATUS_SUMMARY_COUNT_FIELDS: Array<SummaryCountField<StatusSummaryCountKey>> = [
  ['errors', 'errors'],
  ['untrusted', 'untrusted'],
  ['differs', 'differs'],
  ['checking', 'checking'],
  ['pinned', 'pinned'],
  ['disabled', 'disabled']
];

const MENU_ITEMS: Array<{label: string; action: MenuAction}> = [
  {label: 'Refresh Status', action: 'refresh-status'},
  {label: 'Scan & Add', action: 'scan-add'},
  {label: 'Check Now', action: 'check-now'},
  {label: 'Run Updates', action: 'run-updates'},
  {label: 'Config Path', action: 'config-path'},
  {label: 'View Logs', action: 'view-logs'},
  {label: 'Quit', action: 'quit'}
];

export interface AppProps {
  client?: UpdateBarClient;
}

export function App({client: providedClient}: AppProps) {
  const {exit} = useApp();
  const {isRawModeSupported} = useStdin();
  const canUseKeyboard = isRawModeSupported === true;
  const [client, setClient] = useState<UpdateBarClient | undefined>(providedClient);
  const [screen, setScreen] = useState<Screen>('menu');
  const [menuIndex, setMenuIndex] = useState(0);
  const [status, setStatus] = useState<StatusSnapshot | undefined>();
  const [statusUnavailable, setStatusUnavailable] = useState(false);
  const [logs, setLogs] = useState<string[]>([]);
  const [scanReport, setScanReport] = useState<ScanReport | undefined>();
  const [scanIndex, setScanIndex] = useState(0);
  const [selectedScanIds, setSelectedScanIds] = useState<Set<string>>(() => new Set());
  const [updateIndex, setUpdateIndex] = useState(0);
  const [selectedUpdateIds, setSelectedUpdateIds] = useState<Set<string>>(() => new Set());
  const [error, setError] = useState<string | undefined>();
  const [abortController, setAbortController] = useState<AbortController | undefined>();
  const abortControllerRef = useRef<AbortController | undefined>(undefined);

  useEffect(() => {
    if (providedClient) return;
    createDefaultClient().then(setClient).catch(caught => {
      setStatusUnavailable(true);
      setError(messageFor(caught));
    });
  }, [providedClient]);

  useEffect(() => {
    if (!client) return;
    refreshStatus(client, setStatus, setError, setStatusUnavailable);
  }, [client]);

  useEffect(() => {
    return () => {
      abortControllerRef.current?.abort();
    };
  }, []);

  useInput(
    (_input, key) => {
      if (abortControllerRef.current) {
        if (_input === 'c' || _input === 'q') {
          abortControllerRef.current.abort();
        }
        return;
      }
      if (_input === 'q') {
        exit();
        return;
      }
      if (_input === 'm' && screen !== 'menu' && !abortController) {
        setScreen('menu');
        return;
      }
      if (screen === 'scan') {
        handleScanInput(_input, key);
        return;
      }
      if (screen === 'select-update') {
        handleUpdateSelectionInput(_input, key);
        return;
      }
      if (screen === 'confirm-update') {
        if (key.escape) {
          setScreen('menu');
          return;
        }
        if (key.return && client) {
          void runUpdates(client);
        }
        return;
      }
      if (screen === 'menu') {
        if (key.upArrow) {
          setMenuIndex(index => Math.max(0, index - 1));
          return;
        }
        if (key.downArrow) {
          setMenuIndex(index => Math.min(MENU_ITEMS.length - 1, index + 1));
          return;
        }
        if (key.return) {
          void runMenuAction();
        }
      }
    },
    {isActive: canUseKeyboard}
  );

  function handleScanInput(input: string, key: {upArrow: boolean; downArrow: boolean; return: boolean}) {
    const candidates = scanReport?.candidates ?? [];
    const importableCandidates = candidates.filter(canRegister);
    if (key.upArrow) {
      setScanIndex(index => Math.max(0, index - 1));
      return;
    }
    if (key.downArrow) {
      setScanIndex(index => Math.min(Math.max(0, candidates.length - 1), index + 1));
      return;
    }
    if (input === 'a') {
      if (importableCandidates.length === 0) {
        setError('No importable candidates to select');
        return;
      }
      setSelectedScanIds(new Set(importableCandidates.map(candidate => candidate.id)));
      setError(undefined);
      return;
    }
    if (input === 'A') {
      setSelectedScanIds(new Set());
      setError(undefined);
      return;
    }
    if (input === ' ') {
      const candidate = candidates[scanIndex];
      if (!candidate) return;
      if (!canRegister(candidate)) {
        setError(`${candidate.id} is not importable yet (${candidate.capability})`);
        return;
      }
      setError(undefined);
      setSelectedScanIds(previous => {
        const next = new Set(previous);
        if (next.has(candidate.id)) {
          next.delete(candidate.id);
        } else {
          next.add(candidate.id);
        }
        return next;
      });
      return;
    }
    if (key.return) {
      void registerSelectedScanCandidates();
    }
  }

  function handleUpdateSelectionInput(input: string, key: {upArrow: boolean; downArrow: boolean; return: boolean}) {
    const candidates = updateCandidates(status);
    if (key.upArrow) {
      setUpdateIndex(index => Math.max(0, index - 1));
      return;
    }
    if (key.downArrow) {
      setUpdateIndex(index => Math.min(Math.max(0, candidates.length - 1), index + 1));
      return;
    }
    if (input === 'a') {
      setSelectedUpdateIds(new Set(candidates.map(item => item.id)));
      setError(undefined);
      return;
    }
    if (input === 'A') {
      setSelectedUpdateIds(new Set());
      setError(undefined);
      return;
    }
    if (input === ' ') {
      const item = candidates[updateIndex];
      if (!item) return;
      setError(undefined);
      setSelectedUpdateIds(previous => {
        const next = new Set(previous);
        if (next.has(item.id)) {
          next.delete(item.id);
        } else {
          next.add(item.id);
        }
        return next;
      });
      return;
    }
    if (key.return) {
      if (candidates.length === 0) {
        setError('No outdated items to update');
        return;
      }
      if (selectedUpdateIds.size === 0) {
        setError('Select at least one outdated item');
        return;
      }
      setError(undefined);
      setScreen('confirm-update');
    }
  }

  async function runMenuAction() {
    const selected = MENU_ITEMS[menuIndex]?.action;
    switch (selected) {
      case 'config-path':
        setScreen('logs');
        setError(undefined);
        setLogs([
          `config path: ${getConfigPath()}`,
          'open this file in your editor to inspect configuration'
        ]);
        return;
      case 'view-logs':
        setScreen('logs');
        return;
      case 'quit':
        exit();
        return;
    }
    if (!client) return;
    switch (selected) {
      case 'refresh-status':
        setScreen('status');
        await refreshStatus(client, setStatus, setError, setStatusUnavailable);
        return;
      case 'scan-add':
        await runScan(client);
        return;
      case 'check-now':
        await runCheck(client);
        return;
      case 'run-updates':
        await openUpdateSelection(client);
        return;
      default:
        exit();
    }
  }

  async function openUpdateSelection(activeClient: UpdateBarClient) {
    setUpdateIndex(0);
    setError(undefined);
    let snapshot: StatusSnapshot;
    try {
      snapshot = await activeClient.status();
      setStatus(snapshot);
      setStatusUnavailable(false);
    } catch (caught) {
      setStatus(undefined);
      setStatusUnavailable(true);
      setSelectedUpdateIds(new Set());
      setScreen('select-update');
      setError(messageFor(caught));
      return;
    }
    setSelectedUpdateIds(new Set(updateCandidates(snapshot).map(item => item.id)));
    setScreen('select-update');
  }

  async function runCheck(activeClient: UpdateBarClient) {
    const controller = beginAbortableAction();
    setScreen('logs');
    setLogs(['check started']);
    setError(undefined);
    try {
      const report = await activeClient.checkNow({signal: controller.signal});
      setLogs(previous => [...previous, ...checkSummaryLines(report)]);
      await refreshStatus(activeClient, setStatus, setError, setStatusUnavailable);
    } catch (caught) {
      const cancelled = controller.signal.aborted;
      setLogs(previous => [
        ...previous.filter(line => line !== 'check started'),
        cancelled ? 'check cancelled' : 'check failed'
      ]);
      setError(cancelled ? 'check cancelled' : messageFor(caught));
    } finally {
      endAbortableAction(controller);
    }
  }

  async function runScan(activeClient: UpdateBarClient) {
    const controller = beginAbortableAction();
    setScreen('scan');
    setScanReport(undefined);
    setScanIndex(0);
    setSelectedScanIds(new Set());
    setError(undefined);
    try {
      setScanReport(await activeClient.scan({signal: controller.signal}));
    } catch (caught) {
      setScanReport({candidates: [], errors: []});
      setError(controller.signal.aborted ? 'scan cancelled' : messageFor(caught));
    } finally {
      endAbortableAction(controller);
    }
  }

  async function registerSelectedScanCandidates() {
    if (!client) return;
    const ids = [...selectedScanIds];
    if (ids.length === 0) {
      setError('Select at least one full scan candidate');
      return;
    }
    const controller = beginAbortableAction();
    setScreen('logs');
    setLogs(['registering scan selections']);
    setError(undefined);
    try {
      const result = await client.initSelected(ids, {signal: controller.signal});
      setLogs([
        `added ${result.added.length}`,
        `replaced ${result.replaced.length}`,
        `skipped ${result.skipped.length}`,
        ...result.errors
      ]);
      setSelectedScanIds(new Set());
      await refreshStatus(client, setStatus, setError, setStatusUnavailable);
    } catch (caught) {
      const cancelled = controller.signal.aborted;
      setLogs([cancelled ? 'registration cancelled' : 'registration failed']);
      setError(cancelled ? 'registration cancelled' : messageFor(caught));
    } finally {
      endAbortableAction(controller);
    }
  }

  async function runUpdates(activeClient: UpdateBarClient) {
    const ids = [...selectedUpdateIds];
    if (ids.length === 0) {
      setError('Select at least one outdated item');
      setScreen('select-update');
      return;
    }
    const controller = beginAbortableAction();
    setScreen('updating');
    setLogs(['update started']);
    setError(undefined);
    try {
      await activeClient.updateSelected(ids, {
        signal: controller.signal,
        onEvent: event => setLogs(previous => [...previous, describeEvent(event)])
      });
      setSelectedUpdateIds(new Set());
      await refreshStatus(activeClient, setStatus, setError, setStatusUnavailable);
    } catch (caught) {
      const cancelled = controller.signal.aborted;
      setLogs(previous => [
        ...previous.filter(line => line !== 'update started'),
        cancelled ? 'update cancelled' : 'update failed'
      ]);
      setError(cancelled ? 'update cancelled' : messageFor(caught));
    } finally {
      endAbortableAction(controller);
      setScreen('logs');
    }
  }

  function beginAbortableAction() {
    const controller = new AbortController();
    abortControllerRef.current = controller;
    setAbortController(controller);
    return controller;
  }

  function endAbortableAction(controller: AbortController) {
    if (abortControllerRef.current !== controller) return;
    abortControllerRef.current = undefined;
    setAbortController(undefined);
  }

  return (
    <Box flexDirection="column">
      <Text bold>UpdateBar</Text>
      {error && <Text color="red">{redactSecrets(error)}</Text>}
      <StatusLine status={status} unavailable={statusUnavailable} />
      {screen === 'menu' && (
        <Box flexDirection="column" marginTop={1}>
          {MENU_ITEMS.map((item, index) => (
            <Text key={item.action} color={index === menuIndex ? 'cyan' : undefined}>
              {index === menuIndex ? '› ' : '  '}
              {item.label}
            </Text>
          ))}
        </Box>
      )}
      {screen === 'status' && <StatusList status={status} />}
      {screen === 'scan' && (
        <ScanList report={scanReport} selectedIds={selectedScanIds} cursorIndex={scanIndex} />
      )}
      {screen === 'select-update' && (
        <UpdateTargetList
          items={updateCandidates(status)}
          selectedIds={selectedUpdateIds}
          cursorIndex={updateIndex}
        />
      )}
      {screen === 'confirm-update' && (
        <Box flexDirection="column" marginTop={1}>
          <Text color="yellow">Run selected updates now?</Text>
          <Text dimColor>{`${selectedUpdateIds.size} selected outdated item(s) will run.`}</Text>
        </Box>
      )}
      {(screen === 'logs' || screen === 'updating') && (
        <Box flexDirection="column" marginTop={1}>
          {screen === 'updating' && <Text color="yellow">Running updates. Press c to cancel.</Text>}
          {logs.length === 0 ? (
            <Text dimColor>No logs yet</Text>
          ) : (
            logs.slice(-12).map((line, index) => (
              <Text key={`${index}-${line}`}>{redactSecrets(line)}</Text>
            ))
          )}
        </Box>
      )}
      <Text dimColor>
        {canUseKeyboard ? helpText(screen, abortController !== undefined) : 'non-interactive terminal'}
      </Text>
    </Box>
  );
}

function StatusLine({status, unavailable}: {status: StatusSnapshot | undefined; unavailable: boolean}) {
  if (unavailable) return <Text dimColor>Status unavailable</Text>;
  if (!status) return <Text dimColor>Loading status...</Text>;
  return <Text>{formatStatusSummary(status)}</Text>;
}

function formatStatusSummary(status: StatusSnapshot) {
  const parts = [
    `${status.summary.total} tracked`,
    `${status.summary.outdated} outdated`
  ];
  for (const [key, label] of STATUS_SUMMARY_COUNT_FIELDS) {
    const count = status.summary[key];
    if (count > 0) {
      parts.push(`${count} ${label}`);
    }
  }
  return parts.join(' · ');
}

function StatusList({status}: {status: StatusSnapshot | undefined}) {
  if (!status) return null;
  const lines = status.items;
  const rows = lines.length
    ? lines
    : [{
        id: 'no items',
        name: 'run scan + init first',
        category: 'n/a',
        status: 'ok',
        pinned: false
      } as StatusItem];
  return (
    <Box flexDirection="column" marginTop={1}>
      {rows.map(item => (
        <Text key={item.id} color={statusColor(item.status)}>
          {renderStatusRow(item)}
        </Text>
      ))}
    </Box>
  );
}

function renderStatusRow(item: StatusItem) {
  if (item.id === 'no items') {
    return <Text italic>no items tracked yet</Text>;
  }
  const version = [item.current, item.latest]
    .filter(value => Boolean(value))
    .map(value => value?.trim())
    .join(' → ');
  const suffix = item.error ? ` · ! ${item.error}` : '';
  return <Text>{redactSecrets(`${item.id} (${item.category}) ${item.status}${version ? ` · ${version}` : ''}${suffix}`)}</Text>;
}

function statusColor(status: StatusItem['status']) {
  if (status === 'outdated') return 'yellow';
  if (status === 'error' || status === 'untrusted') return 'red';
  if (status === 'pinned' || status === 'disabled') return 'magenta';
  if (status === 'differs') return 'cyan';
  return undefined;
}

function ScanList({
  report,
  selectedIds,
  cursorIndex
}: {
  report: ScanReport | undefined;
  selectedIds: Set<string>;
  cursorIndex: number;
}) {
  if (!report) return <Text dimColor>Scanning...</Text>;
  if (report.candidates.length === 0) return <Text dimColor>No scan candidates</Text>;
  const importableCount = report.candidates.filter(canRegister).length;
  const reviewCount = report.candidates.length - importableCount;
  const visibleRows = getVisibleRows(report.candidates, cursorIndex, 8);
  const firstVisibleRow = visibleRows[0]?.row;
  const lastVisibleRow = visibleRows.at(-1)?.row;
  return (
    <Box flexDirection="column" marginTop={1}>
      <Text dimColor>{`importable: ${selectedIds.size}/${importableCount}`}</Text>
      <Text dimColor>{`needs review: ${reviewCount}`}</Text>
      <Text dimColor>{`showing ${
        typeof firstVisibleRow === 'number' ? firstVisibleRow + 1 : 0
      }-${
        typeof lastVisibleRow === 'number' ? lastVisibleRow + 1 : 0
      } of ${report.candidates.length}`}</Text>
      {visibleRows.map(({row, item: candidate}) => (
        <Text key={candidate.id} color={row === cursorIndex ? 'cyan' : undefined}>
          {renderScanRow(candidate, selectedIds.has(candidate.id))}
        </Text>
      ))}
      {report.errors.map(error => (
        <Text key={`${error.detector}-${error.message}`} color="yellow">
          {redactSecrets(`${error.detector}: ${error.message}`)}
        </Text>
      ))}
    </Box>
  );
}

function UpdateTargetList({
  items,
  selectedIds,
  cursorIndex
}: {
  items: StatusItem[];
  selectedIds: Set<string>;
  cursorIndex: number;
}) {
  if (items.length === 0) {
    return (
      <Box flexDirection="column" marginTop={1}>
        <Text dimColor>No outdated items in stored status.</Text>
        <Text dimColor>Run Check Now to refresh versions first.</Text>
      </Box>
    );
  }
  const visibleRows = getVisibleRows(items, cursorIndex, 8);
  const firstVisibleRow = visibleRows[0]?.row;
  const lastVisibleRow = visibleRows.at(-1)?.row;
  return (
    <Box flexDirection="column" marginTop={1}>
      <Text color="yellow">Select updates to run</Text>
      <Text dimColor>{`selected: ${selectedIds.size}/${items.length}`}</Text>
      <Text dimColor>{`showing ${
        typeof firstVisibleRow === 'number' ? firstVisibleRow + 1 : 0
      }-${
        typeof lastVisibleRow === 'number' ? lastVisibleRow + 1 : 0
      } of ${items.length}`}</Text>
      {visibleRows.map(({row, item}) => (
        <Text key={item.id} color={row === cursorIndex ? 'cyan' : undefined}>
          {renderUpdateTargetRow(item, selectedIds.has(item.id))}
        </Text>
      ))}
    </Box>
  );
}

function getVisibleRows<T>(items: T[], cursorIndex: number, maxLines: number) {
  if (items.length <= maxLines) {
    return items.map((item, row) => ({row, item}));
  }
  const halfWindow = Math.floor(maxLines / 2);
  const start = Math.max(0, Math.min(cursorIndex - halfWindow, items.length - maxLines));
  const end = Math.min(start + maxLines, items.length);
  return items
    .slice(start, end)
    .map((item, index) => ({row: index + start, item}));
}

function scanMarker(candidate: ScanCandidate, selected: boolean) {
  if (!canRegister(candidate)) return '-';
  return selected ? '[x]' : '[ ]';
}

function renderScanRow(candidate: ScanCandidate, selected: boolean) {
  const version = candidate.installed_version ? ` ${candidate.installed_version}` : '';
  const source = !canRegister(candidate) && candidate.source_ref ? ` · source: ${candidate.source_ref}` : '';
  return redactSecrets(`${scanMarker(candidate, selected)} ${candidate.id} · ${candidate.name}${version} · ${candidate.category} · ${candidate.detector} · ${candidate.capability}${source}`);
}

function renderUpdateTargetRow(item: StatusItem, selected: boolean) {
  const marker = selected ? '[x]' : '[ ]';
  const version = [item.current, item.latest]
    .filter(value => Boolean(value))
    .map(value => value?.trim())
    .join(' → ');
  return redactSecrets(`${marker} ${item.id} · ${item.name}${version ? ` · ${version}` : ''}`);
}

function updateCandidates(status: StatusSnapshot | undefined) {
  return status?.items.filter(item => item.status === 'outdated') ?? [];
}

function canRegister(candidate: ScanCandidate) {
  return candidate.capability === 'full' && candidate.recipe !== undefined;
}

function helpText(screen: Screen, canCancel: boolean) {
  if (canCancel) return 'c/q cancel';
  if (screen === 'scan') {
    return '↑/↓ navigate · a all · A clear · space select · enter add · m menu · q quit';
  }
  if (screen === 'select-update') {
    return '↑/↓ navigate · a all · A clear · space select · enter confirm · m menu · q quit';
  }
  if (screen === 'confirm-update') return 'enter run · esc cancel · m menu · q quit';
  if (screen !== 'menu') return 'm menu · q quit';
  return '↑/↓ navigate · enter select · q quit';
}

async function refreshStatus(
  client: UpdateBarClient,
  setStatus: (status: StatusSnapshot | undefined) => void,
  setError: (message: string | undefined) => void,
  setStatusUnavailable: (unavailable: boolean) => void
) {
  try {
    setStatusUnavailable(false);
    setStatus(await client.status());
    setError(undefined);
  } catch (caught) {
    setStatus(undefined);
    setStatusUnavailable(true);
    setError(messageFor(caught));
  }
}

function describeEvent(event: MachineEvent) {
  if (event.event === 'item_started') return `starting ${event.item_id ?? 'item'}`;
  if (event.event === 'item_finished') {
    const item = event.item_id ?? event.result?.id ?? event.result?.name ?? 'item';
    const summary = `${item} ${event.result?.outcome ?? 'done'}`;
    return event.result?.error ? `${summary} · ${event.result.error}` : summary;
  }
  if (event.event === 'finished') {
    const summary = event.summary;
    if (summary && typeof summary.updated === 'number' && typeof summary.total === 'number') {
      const parts = [`finished · updated ${summary.updated}/${summary.total}`];
      if (summary.failed > 0) parts.push(`failed ${summary.failed}`);
      if (summary.skipped_untrusted > 0) parts.push(`approval ${summary.skipped_untrusted}`);
      if (summary.missing > 0) parts.push(`missing ${summary.missing}`);
      if (summary.cancelled > 0) parts.push(`cancelled ${summary.cancelled}`);
      return parts.join(' · ');
    }
    return `finished ${event.summary?.updated ?? 0} updated`;
  }
  if (event.event === 'cancelled') return 'cancelled';
  if (event.event === 'failed' && event.error) return event.error;
  if (event.message) return event.message;
  return event.event;
}

function checkSummaryLines(report: CheckReport) {
  const lines = [
    `checked ${report.summary.total} items`
  ];

  for (const [key, label] of CHECK_SUMMARY_COUNT_FIELDS) {
    const count = report.summary[key];
    if (count > 0) {
      lines.push(`${label}: ${count}`);
    }
  }

  appendItemSample(lines, report, 'outdated');
  appendItemSample(lines, report, 'error');
  appendItemSample(lines, report, 'differs');

  return lines;
}

function appendItemSample(lines: string[], report: CheckReport, status: StatusItem['status']) {
  const names = report.items
    .filter(item => item.status === status)
    .map(item => status === 'error' && item.error ? `${item.name}: ${item.error}` : item.name)
    .filter(name => Boolean(name));

  if (names.length > 0) {
    const suffix = names.length > 3 ? ', ...' : '';
    lines.push(`${status} sample: ${names.slice(0, 3).join(', ')}${suffix}`);
  }
}

function getConfigPath() {
  const updateBarHome = process.env.UPDATEBAR_HOME?.trim();
  if (updateBarHome) return path.join(updateBarHome, 'config.toml');
  const home = process.env.HOME || process.env.USERPROFILE || '~';
  return path.join(home, '.updatebar', 'config.toml');
}

function messageFor(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
