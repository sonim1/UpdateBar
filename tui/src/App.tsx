import React, {useEffect, useMemo, useRef, useState} from 'react';
import {Box, Text, useApp, useInput, useStdin} from 'ink';
import {createDefaultClient, type UpdateBarClient} from './client.js';
import type {MachineEvent, ScanCandidate, ScanReport, StatusSnapshot} from './types.js';

type Screen = 'menu' | 'status' | 'logs' | 'scan' | 'updating';

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
  const menu = useMemo(
    () => ['Refresh Status', 'Scan & Add', 'Check Now', 'Run Updates', 'Open Config', 'View Logs', 'Quit'],
    []
  );

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
          setMenuIndex(index => Math.min(menu.length - 1, index + 1));
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
    const selected = menu[menuIndex];
    if (selected === 'Refresh Status') {
      setScreen('status');
      await refreshStatus(client, setStatus, setError);
    } else if (selected === 'Scan & Add') {
      await runScan(client);
    } else if (selected === 'Check Now') {
      await runCheck(client);
    } else if (selected === 'Run Updates') {
      await runUpdates(client);
    } else if (selected === 'Open Config') {
      setScreen('logs');
      setLogs([`config: ${process.env.UPDATEBAR_HOME ?? '~/.updatebar'}/config.toml`]);
    } else if (selected === 'View Logs') {
      setScreen('logs');
    } else {
      exit();
    }
  }

  async function runCheck(activeClient: UpdateBarClient) {
    const controller = beginAbortableAction();
    setScreen('logs');
    setLogs(['check started']);
    setError(undefined);
    try {
      await activeClient.checkNow({signal: controller.signal});
      setLogs(previous => [...previous, 'check finished']);
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
          {menu.map((item, index) => (
            <Text key={item} color={index === menuIndex ? 'cyan' : undefined}>
              {index === menuIndex ? '› ' : '  '}
              {item}
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
          {logs.slice(-12).map((line, index) => (
            <Text key={`${index}-${line}`}>{line}</Text>
          ))}
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
  return (
    <Text>
      {status.summary.total} tracked · {status.summary.outdated} outdated · {status.summary.errors} errors
    </Text>
  );
}

function StatusList({status}: {status: StatusSnapshot | undefined}) {
  if (!status) return null;
  return (
    <Box flexDirection="column" marginTop={1}>
      {status.items.map(item => (
        <Text key={item.id}>
          {item.id} · {item.status}
        </Text>
      ))}
    </Box>
  );
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
  return (
    <Box flexDirection="column" marginTop={1}>
      <Text dimColor>{`importable: ${selectedIds.size}/${importableCount}`}</Text>
      {report.candidates.map((candidate, index) => (
        <Text key={candidate.id} color={index === cursorIndex ? 'cyan' : undefined}>
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
  if (event.event === 'finished') return `finished ${event.summary?.updated ?? 0} updated`;
  if (event.event === 'cancelled') return 'cancelled';
  if (event.message) return event.message;
  return event.event;
}

function messageFor(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
