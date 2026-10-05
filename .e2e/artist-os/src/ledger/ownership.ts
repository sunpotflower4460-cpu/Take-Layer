import type { SystemId } from '../core/common.js'
import type { ActionOperation, ActionPlatform } from './action-key.js'

/**
 * Runtime mode of a specialist (and the expectation Artist OS has of it).
 *   standalone         the product works alone, exactly as before
 *   artist_os_managed  Artist OS ownership rules apply
 * Detection is explicit (env + health), never inferred.
 */
export const RUNTIME_MODES = ['standalone', 'artist_os_managed'] as const
export type RuntimeMode = (typeof RUNTIME_MODES)[number]

export type ExecutionOwner = Extract<SystemId, 'my-sns' | 'sns-providers'>
export type ManagedOwner = ExecutionOwner | 'handoff'

export interface OwnershipRule {
  platform: ActionPlatform
  operation: ActionOperation
  /** The only system allowed to execute this reply in managed mode, or `handoff` (a human does it). */
  managedOwner: ManagedOwner
  /** Systems that may add context/drafts/priority but NEVER execute. */
  intelligence: readonly SystemId[]
  approvalOwner: SystemId
  note: string
}

/**
 * Data, not logic: the ownership table the ledger enforces. Unknown (platform, operation)
 * is refused by the ledger (fail closed). See docs/architecture/ACTION_OWNERSHIP_MATRIX.md.
 */
export const OWNERSHIP_RULES: readonly OwnershipRule[] = [
  { platform: 'instagram', operation: 'comment_reply', managedOwner: 'my-sns', intelligence: ['sns-providers', 'sns-ai'], approvalOwner: 'my-sns', note: 'Meta webhook canonical receiver is My-SNS. My-SNS cannot send IG yet: the executor fails closed and the human replies.' },
  { platform: 'instagram', operation: 'dm_reply', managedOwner: 'my-sns', intelligence: ['sns-providers', 'sns-ai'], approvalOwner: 'my-sns', note: 'My-SNS cannot send Instagram DMs yet (HTTP 409); no other system may fill that gap in managed mode.' },
  { platform: 'youtube', operation: 'comment_reply', managedOwner: 'my-sns', intelligence: ['sns-ai'], approvalOwner: 'my-sns', note: 'My-SNS pulls YouTube comments.' },
  { platform: 'line', operation: 'dm_reply', managedOwner: 'my-sns', intelligence: ['sns-ai'], approvalOwner: 'my-sns', note: 'The only surface My-SNS actually sends on today.' },
  { platform: 'x', operation: 'mention_reply', managedOwner: 'sns-providers', intelligence: ['sns-ai'], approvalOwner: 'sns-providers', note: 'My-SNS does not ingest X. SNS-providers is the only X inbound/execute path (human-approved one at a time). Move to my-sns when it ingests X.' },
  { platform: 'x', operation: 'dm_reply', managedOwner: 'sns-providers', intelligence: ['sns-ai'], approvalOwner: 'sns-providers', note: 'As above.' },
  { platform: 'tiktok', operation: 'comment_reply', managedOwner: 'handoff', intelligence: [], approvalOwner: 'my-sns', note: 'No supported reply API wired anywhere.' },
  { platform: 'threads', operation: 'comment_reply', managedOwner: 'handoff', intelligence: [], approvalOwner: 'my-sns', note: 'Not supported.' },
  { platform: 'facebook', operation: 'comment_reply', managedOwner: 'handoff', intelligence: [], approvalOwner: 'my-sns', note: 'Not supported.' },
]

export function ownershipFor(platform: ActionPlatform, operation: ActionOperation): OwnershipRule | undefined {
  return OWNERSHIP_RULES.find((r) => r.platform === platform && r.operation === operation)
}

/** Systems that must never reserve/execute an inbound reply in managed mode, whatever the rule says. */
export const NEVER_EXECUTES_INBOUND_REPLIES: readonly SystemId[] = ['sns-ai', 'growth-bridge', 'sns-hub', 'artist-os', 'take-layer', 'my-spotify', 'playlist-garden', 'mac-runner']
