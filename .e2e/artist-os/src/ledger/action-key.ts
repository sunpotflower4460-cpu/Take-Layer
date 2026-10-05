import { z } from 'zod'

/**
 * CrossSystemActionKey: one identity for "reply to THIS inbound event on THIS platform",
 * independent of which system sees it or what that system calls it internally.
 *
 *   instagram:comment_reply:<native comment id>
 *   instagram:dm_reply:<native message id>
 *
 * It is derived from the platform's own event id, never from the reply text: a hash of the
 * body would let a reworded duplicate through and would forbid nothing useful, while the event
 * id says exactly "this inbound event has been answered". A later, different inbound message
 * from the same person has a different event id and is therefore never blocked.
 */
export const ACTION_PLATFORMS = ['instagram', 'x', 'youtube', 'line', 'tiktok', 'threads', 'facebook'] as const
export type ActionPlatform = (typeof ACTION_PLATFORMS)[number]

export const ACTION_OPERATIONS = ['comment_reply', 'dm_reply', 'mention_reply'] as const
export type ActionOperation = (typeof ACTION_OPERATIONS)[number]

export const ActionKeyPartsSchema = z.object({
  platform: z.enum(ACTION_PLATFORMS),
  operation: z.enum(ACTION_OPERATIONS),
  /** The platform-native event id. No ':' (it is the key separator); no whitespace. */
  externalEventId: z.string().regex(/^[A-Za-z0-9._\-=]{1,200}$/, 'externalEventId must be a native event id (no ":" or whitespace)'),
})
export type ActionKeyParts = z.infer<typeof ActionKeyPartsSchema>

export type ActionKey = string & { readonly __brand: 'ActionKey' }

export function makeActionKey(parts: ActionKeyParts): ActionKey {
  const p = ActionKeyPartsSchema.parse(parts)
  return `${p.platform}:${p.operation}:${p.externalEventId}` as ActionKey
}

export function parseActionKey(key: string): ActionKeyParts {
  const [platform, operation, ...rest] = key.split(':')
  if (rest.length !== 1) throw new Error(`malformed action key: ${key}`)
  return ActionKeyPartsSchema.parse({ platform, operation, externalEventId: rest[0] })
}

/**
 * Internal ids that specialists derive FROM the native id. Each system must reduce its own
 * id to the native one before keying, or the same event gets two keys and the ledger cannot
 * arbitrate. Unknown shapes are returned unchanged (and must then already be native).
 */
const KNOWN_PREFIXES = ['sa-ig-comment-', 'sa-ig-dm-', 'sa-x-mention-', 'sa-x-reply-', 'sa-x-dm-', 'ig-comment-', 'ig-dm-', 'x-mention-'] as const

export function normalizeExternalEventId(raw: string): string {
  const trimmed = raw.trim()
  for (const p of KNOWN_PREFIXES) if (trimmed.startsWith(p)) return trimmed.slice(p.length)
  return trimmed
}
