export type ItemStatus =
  | 'ok'
  | 'outdated'
  | 'differs'
  | 'error'
  | 'pinned'
  | 'disabled'
  | 'checking'
  | 'untrusted';

export interface StatusSnapshot {
  generated_at: string;
  summary: {
    total: number;
    outdated: number;
    errors: number;
    untrusted: number;
    pinned: number;
    disabled: number;
    checking: number;
    differs: number;
  };
  items: StatusItem[];
}

export interface StatusItem {
  id: string;
  name: string;
  category: string;
  current?: string;
  latest?: string;
  status: ItemStatus;
  pinned: boolean;
  last_checked?: string;
  error?: string;
}

export interface ScanReport {
  candidates: ScanCandidate[];
  errors: ScanError[];
}

export interface ScanCandidate {
  id: string;
  name: string;
  detector: 'brew' | 'npm_global' | 'known' | 'codex_skill' | 'mcp_config';
  category: string;
  capability: 'full' | 'check-only' | 'metadata-only' | 'unsupported';
  confidence: 'high' | 'medium' | 'low';
  installed_version?: string;
  source_ref?: string;
  recipe?: unknown;
}

export interface ScanError {
  detector: 'brew' | 'npm_global' | 'known' | 'codex_skill' | 'mcp_config';
  message: string;
}

export interface InitResult {
  ok: boolean;
  added: string[];
  replaced: string[];
  skipped: string[];
  errors: string[];
}

export type UpdateOutcome =
  | 'updated'
  | 'failed'
  | 'skipped_pinned'
  | 'skipped_disabled'
  | 'skipped_untrusted'
  | 'skipped_not_outdated'
  | 'missing'
  | 'cancelled';

export interface UpdateResult {
  id: string;
  name: string;
  outcome: UpdateOutcome;
  current?: string;
  latest?: string;
  error?: string;
  command_fingerprint?: string;
}

export interface UpdateSummary {
  total: number;
  updated: number;
  failed: number;
  skipped: number;
  skipped_untrusted: number;
  missing: number;
  cancelled: number;
  hard_failures: number;
}

export type MachineEventType =
  | 'started'
  | 'item_started'
  | 'log'
  | 'item_finished'
  | 'cancelled'
  | 'failed'
  | 'finished';

export interface MachineEvent {
  event: MachineEventType;
  type?: MachineEventType;
  operation: 'update' | 'check';
  run_id?: string;
  timestamp: string;
  item_id?: string;
  message?: string;
  level?: 'debug' | 'info' | 'warning' | 'error';
  result?: UpdateResult;
  results?: UpdateResult[];
  summary?: UpdateSummary;
  check_result?: CheckResult;
  check_results?: CheckResult[];
  check_summary?: CheckSummary;
  error?: string;
}

export interface CheckResult {
  id: string;
  name: string;
  current?: string;
  latest?: string;
  status: ItemStatus;
  last_checked?: string;
  error?: string;
}

export interface CheckReport {
  items: CheckResult[];
  summary: CheckSummary;
}

export interface CheckSummary {
  total: number;
  outdated: number;
  errors: number;
  untrusted: number;
  disabled: number;
  pinned: number;
  differs: number;
}
