ALTER TABLE chat_messages ADD COLUMN reply_to TEXT;
--> statement-breakpoint
CREATE UNIQUE INDEX chat_messages_reply ON chat_messages(reply_to) WHERE reply_to IS NOT NULL;
--> statement-breakpoint
CREATE TABLE chat_bridge_status (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  last_seen TEXT NOT NULL
);
