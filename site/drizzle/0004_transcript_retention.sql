-- Separate transcript retention from the fixed seven-day message-acceptance window.
-- Absolute creation-based expiry preserves the existing 14-day cleanup policy.
UPDATE chat_conversations
SET expires_at = strftime('%Y-%m-%dT%H:%M:%fZ', created_at, '+14 days');
