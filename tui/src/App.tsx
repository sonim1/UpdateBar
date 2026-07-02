import React, {useEffect, useRef, useState} from 'react';
import path from 'node:path';
import {Box, Text, useApp, useInput, useStdin} from 'ink';
import {createDefaultClient, type UpdateBarClient} from './client.js';
import type {CheckReport, MachineEvent, ScanCandidate, ScanReport, StatusItem, StatusSnapshot} from './types.js';

type Screen = 'menu' | 'status' | 'logs' | 'scan' | 'updating';
type MenuAction =
  | 'refresh-status'
  | 'scan-add'
  | 'check-now'
  | 'run-updates'
  | 'open-config'
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
  {label: 'Open Config', action: 'open-config'},
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
  const [logs, setLogs] = useState<string[]>([]);
  const [scanReport, setScanReport] = useState<ScanReport | undefined>();
  const [scanIndex, setScanIndex] = useState(0);
  const [selectedScanIds, setSelectedScanIds] = useState<Set<string>>(() => new Set());
  const [error, setError] = useState<string | undefined>();
  const [abortController, setAbortController] = useState<AbortController | undefined>();
  const abortControllerRef = useRef<AbortController | undefined>(undefined);

  useEffect(() => {
    if (providedClient) return;
    createDefaultClient().then(setClient).catch(caught => setError(messageFor(caught)));
  }, [providedClient]);

  useEffect(() => {
    if (!client) return;
    refreshStatus(client, setStatus, setError);
  }, [client]);

  useEffect(() => {
    return () => {
      abortControllerRef.current?.abort();
    };
  }, []);

  useInput(
    (_input, key) => {
      if ((_input === 'c' || _input === 'q') && abortControllerRef.current) {
        abortControllerRef.current.abort();
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
        setError(`${candidate.id} is not importable yet`);
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

  async function runMenuAction() {
    if (!client) return;
    const selected = MENU_ITEMS[menuIndex]?.action;
    switch (selected) {
      case 'refresh-status':
        setScreen('status');
        await refreshStatus(client, setStatus, setError);
        return;
      case 'scan-add':
        await runScan(client);
        return;
      case 'check-now':
        await runCheck(client);
        return;
      case 'run-updates':
        await runUpdates(client);
        return;
      case 'open-config':
        setScreen('logs');
        setLogs([
          `config path: ${getConfigPath()}`,
          'open this file in your editor to inspect configuration'
        ]);
        return;
      case 'view-logs':
        setScreen('logs');
        return;
      case 'quit':
      default:
        exit();
    }
  }

  async function runCheck(activeClient: UpdateBarClient) {
    const controller = beginAbortableAction();
    setScreen('logs');
    setLogs(['check started']);
    setError(undefined);
    try {
      const report = await activeClient.checkNow({signal: controller.signal});
      setLogs(previous => [...previous, ...checkSummaryLines(report)]);
      await refreshStatus(activeClient, setStatus, setError);
    } catch (caught) {
      setError(controller.signal.aborted ? 'check cancelled' : messageFor(caught));
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
    setScreen('logs');
    setLogs(['registering scan selections']);
    try {
      const result = await client.initSelected(ids);
      setLogs([
        `added ${result.added.length}`,
        `replaced ${result.replaced.length}`,
        `skipped ${result.skipped.length}`,
        ...result.errors
      ]);
      setSelectedScanIds(new Set());
      await refreshStatus(client, setStatus, setError);
    } catch (caught) {
      setError(messageFor(caught));
    }
  }

  async function runUpdates(activeClient: UpdateBarClient) {
    const controller = beginAbortableAction();
    setScreen('updating');
    setLogs(['update started']);
    setError(undefined);
    try {
      await activeClient.updateAll({
        signal: controller.signal,
        onEvent: event => setLogs(previous => [...previous, describeEvent(event)])
      });
      await refreshStatus(activeClient, setStatus, setError);
    } catch (caught) {
      setError(controller.signal.aborted ? 'update cancelled' : messageFor(caught));
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
      {error && <Text color="red">{error}</Text>}
      <StatusLine status={status} />
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
      {(screen === 'logs' || screen === 'updating') && (
        <Box flexDirection="column" marginTop={1}>
          {screen === 'updating' && <Text color="yellow">Running updates. Press c to cancel.</Text>}
          {logs.length === 0 ? (
            <Text dimColor>No logs yet</Text>
          ) : (
            logs.slice(-12).map((line, index) => (
              <Text key={`${index}-${line}`}>{line}</Text>
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

function StatusLine({status}: {status: StatusSnapshot | undefined}) {
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
  return <Text>{`${item.id} (${item.category}) ${item.status}${version ? ` · ${version}` : ''}${suffix}`}</Text>;
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
      {visibleRows.map(({row, candidate}) => (
        <Text key={candidate.id} color={row === cursorIndex ? 'cyan' : undefined}>
          {scanMarker(candidate, selectedIds.has(candidate.id))} {candidate.id} · {candidate.name}
          {candidate.installed_version ? ` ${candidate.installed_version}` : ''} · {candidate.category} ·{' '}
          {candidate.detector} · {candidate.capability}
        </Text>
      ))}
      {report.errors.map(error => (
        <Text key={`${error.detector}-${error.message}`} color="yellow">
          {error.detector}: {error.message}
        </Text>
      ))}
    </Box>
  );
}

function getVisibleRows(candidates: ScanCandidate[], cursorIndex: number, maxLines: number) {
  if (candidates.length <= maxLines) {
    return candidates.map((candidate, row) => ({row, candidate}));
  }
  const halfWindow = Math.floor(maxLines / 2);
  const start = Math.max(0, Math.min(cursorIndex - halfWindow, candidates.length - maxLines));
  const end = Math.min(start + maxLines, candidates.length);
  return candidates
    .slice(start, end)
    .map((candidate, index) => ({row: index + start, candidate}));
}

function scanMarker(candidate: ScanCandidate, selected: boolean) {
  if (!canRegister(candidate)) return '-';
  return selected ? '[x]' : '[ ]';
}

function canRegister(candidate: ScanCandidate) {
  return candidate.capability === 'full' && candidate.recipe !== undefined;
}

function helpText(screen: Screen, canCancel: boolean) {
  if (canCancel) return 'c/q cancel';
  if (screen === 'scan') {
    return '↑/↓ navigate · a all · A clear · space select · enter add · m menu · q quit';
  }
  if (screen !== 'menu') return 'm menu · q quit';
  return '↑/↓ navigate · enter select · q quit';
}

async function refreshStatus(
  client: UpdateBarClient,
  setStatus: (status: StatusSnapshot) => void,
  setError: (message: string | undefined) => void
) {
  try {
    setStatus(await client.status());
    setError(undefined);
  } catch (caught) {
    setError(messageFor(caught));
  }
}

function describeEvent(event: MachineEvent) {
  if (event.event === 'item_started') return `starting ${event.item_id ?? 'item'}`;
  if (event.event === 'item_finished') return `${event.item_id ?? 'item'} ${event.result?.outcome ?? 'done'}`;
  if (event.event === 'finished') {
    const updated = event.summary?.updated;
    const total = event.summary?.total;
    if (typeof updated === 'number' && typeof total === 'number') {
      return `finished · updated ${updated}/${total}`;
    }
    return `finished ${event.summary?.updated ?? 0} updated`;
  }
  if (event.event === 'cancelled') return 'cancelled';
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
    .map(item => item.name)
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
