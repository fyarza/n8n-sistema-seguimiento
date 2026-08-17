-- sistema-seguimiento v1
-- Zona horaria de negocio: America/Caracas. Avisos a las 10:00 local.
-- Correr este script en Postgres ANTES de activar los workflows de n8n.

CREATE TABLE IF NOT EXISTS followup_reminders (
  id BIGSERIAL PRIMARY KEY,
  telegram_chat_id BIGINT NOT NULL,
  client_name TEXT NOT NULL,
  client_phone TEXT NOT NULL,
  estimated_date DATE NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('t3', 'day')),
  fire_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sent', 'cancelled', 'skipped')),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ,
  UNIQUE (telegram_chat_id, client_phone, estimated_date, kind)
);

CREATE INDEX IF NOT EXISTS idx_followup_due
  ON followup_reminders (fire_at)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_followup_chat
  ON followup_reminders (telegram_chat_id, status);

-- Resumen durable fuera de la ventana de 10 interacciones.
CREATE TABLE IF NOT EXISTS conversation_summaries (
  telegram_chat_id BIGINT PRIMARY KEY,
  summary TEXT NOT NULL DEFAULT '',
  last_compacted_at TIMESTAMPTZ,
  messages_compacted INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Memoria corta del agente (LangChain / nodo Postgres Chat Memory de n8n).
-- Si el nodo la crea solo, deja esta definición; el esquema debe coincidir.
CREATE TABLE IF NOT EXISTS assistant_chat_messages (
  id SERIAL PRIMARY KEY,
  session_id VARCHAR(255) NOT NULL,
  message JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_assistant_chat_session
  ON assistant_chat_messages (session_id, id);
