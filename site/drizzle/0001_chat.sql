CREATE TABLE chat_conversations (
  id TEXT PRIMARY KEY NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  busy_until TEXT,
  active_message TEXT
);
--> statement-breakpoint
CREATE TABLE chat_messages (
  id TEXT PRIMARY KEY NOT NULL,
  conversation_id TEXT NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('pending', 'complete', 'failed')),
  created_at TEXT NOT NULL,
  handled_at TEXT
);
--> statement-breakpoint
CREATE INDEX chat_messages_conversation ON chat_messages(conversation_id, created_at);
--> statement-breakpoint
CREATE INDEX chat_messages_relay ON chat_messages(handled_at, created_at);
