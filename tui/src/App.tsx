import React, {useEffect, useMemo, useState} from 'react';
import {Box, Text, useApp, useInput, useStdin} from 'ink';
import {createDefaultClient, type UpdateBarClient} from './client.js';
import type {MachineEvent, StatusSnapshot} from './types.js';

type Screen = 'menu' | 'status' | 'logs' | 'updating';

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
  const [error, setError] = useState<string | undefined>();
  const [abortController, setAbortController] = useState<AbortController | undefined>();
  const menu = useMemo(
    () => ['Refresh Status', 'Check Now', 'Run Updates', 'Open Config', 'View Logs', 'Quit'],
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

  useInput(
    (_input, key) => {
      if (key.upArrow) {
        setMenuIndex(index => Math.max(0, index - 1));
        return;
      }
      if (key.downArrow) {
        setMenuIndex(index => Math.min(menu.length - 1, index + 1));
        return;
      }
      if (_input === 'q') {
        exit();
        return;
      }
      if (_input === 'c' && abortController) {
        abortController.abort();
        return;
      }
      if (key.return) {
        void runMenuAction();
      }
    },
    {isActive: canUseKeyboard}
  );

  async function runMenuAction() {
    if (!client) return;
    const selected = menu[menuIndex];
    if (selected === 'Refresh Status') {
      setScreen('status');
      await refreshStatus(client, setStatus, setError);
    } else if (selected === 'Check Now') {
      setScreen('logs');
      setLogs(['check started']);
      try {
        await client.checkNow();
        setLogs(previous => [...previous, 'check finished']);
        await refreshStatus(client, setStatus, setError);
      } catch (caught) {
        setError(messageFor(caught));
      }
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

  async function runUpdates(activeClient: UpdateBarClient) {
    const controller = new AbortController();
    setAbortController(controller);
    setScreen('updating');
    setLogs(['update started']);
    try {
      await activeClient.updateAll({
        signal: controller.signal,
        onEvent: event => setLogs(previous => [...previous, describeEvent(event)])
      });
      await refreshStatus(activeClient, setStatus, setError);
    } catch (caught) {
      setError(messageFor(caught));
    } finally {
      setAbortController(undefined);
      setScreen('logs');
    }
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
      {(screen === 'logs' || screen === 'updating') && (
        <Box flexDirection="column" marginTop={1}>
          {screen === 'updating' && <Text color="yellow">Running updates. Press c to cancel.</Text>}
          {logs.slice(-12).map((line, index) => (
            <Text key={`${index}-${line}`}>{line}</Text>
          ))}
        </Box>
      )}
      <Text dimColor>
        {canUseKeyboard ? '↑/↓ navigate · enter select · q quit' : 'non-interactive terminal'}
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
