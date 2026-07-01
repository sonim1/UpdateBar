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
  operation: 'update' | 'check';
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

export interface CheckSummary {
  total: number;
  outdated: number;
  errors: number;
  untrusted: number;
  disabled: number;
  pinned: number;
}
