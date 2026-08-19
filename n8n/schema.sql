-- sistema-seguimiento v2
-- Zona horaria de negocio: America/Caracas. Avisos a las 10:00 local.
-- Correr este script en Postgres ANTES de activar los workflows de n8n.
-- v2 añade leads de WhatsApp (Evolution). Es idempotente (IF NOT EXISTS).

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

-- v2: embudo WhatsApp (Evolution). Observador: no responde al cliente.
CREATE TABLE IF NOT EXISTS leads (
  id BIGSERIAL PRIMARY KEY,
  whatsapp_jid TEXT NOT NULL UNIQUE,
  phone TEXT NOT NULL,
  display_name TEXT NOT NULL DEFAULT '',
  stage TEXT NOT NULL DEFAULT 'en_proceso'
    CHECK (stage IN ('en_proceso', 'concreto', 'pregunto_no_concreto', 'no_respondio')),
  score_potencial INTEGER NOT NULL DEFAULT 0 CHECK (score_potencial BETWEEN 0 AND 100),
  score_engagement INTEGER NOT NULL DEFAULT 0 CHECK (score_engagement BETWEEN 0 AND 100),
  score_cierre INTEGER NOT NULL DEFAULT 0 CHECK (score_cierre BETWEEN 0 AND 100),
  score_silencio INTEGER NOT NULL DEFAULT 0 CHECK (score_silencio BETWEEN 0 AND 100),
  sentiment_last TEXT NOT NULL DEFAULT 'neutro'
    CHECK (sentiment_last IN ('positivo', 'neutro', 'negativo', 'enfadado')),
  quoted_at TIMESTAMPTZ,
  last_client_at TIMESTAMPTZ,
  last_advisor_at TIMESTAMPTZ,
  client_msg_count INTEGER NOT NULL DEFAULT 0,
  advisor_msg_count INTEGER NOT NULL DEFAULT 0,
  last_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_leads_stage_potencial
  ON leads (stage, score_potencial DESC)
  WHERE stage <> 'concreto';

CREATE INDEX IF NOT EXISTS idx_leads_phone
  ON leads (phone);

CREATE TABLE IF NOT EXISTS whatsapp_messages (
  id BIGSERIAL PRIMARY KEY,
  lead_id BIGINT NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  evolution_message_id TEXT NOT NULL,
  from_me BOOLEAN NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  content_type TEXT NOT NULL DEFAULT 'text',
  relevant BOOLEAN,
  filter_label TEXT,
  occurred_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (lead_id, evolution_message_id)
);

CREATE INDEX IF NOT EXISTS idx_wa_messages_lead_time
  ON whatsapp_messages (lead_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS lead_score_events (
  id BIGSERIAL PRIMARY KEY,
  lead_id BIGINT NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  stage TEXT NOT NULL,
  score_potencial INTEGER NOT NULL,
  score_engagement INTEGER NOT NULL,
  score_cierre INTEGER NOT NULL,
  score_silencio INTEGER NOT NULL,
  sentiment TEXT NOT NULL,
  reason TEXT,
  source TEXT NOT NULL DEFAULT 'classifier'
    CHECK (source IN ('classifier', 'silence_cron', 'rule')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_lead_score_lead_time
  ON lead_score_events (lead_id, created_at DESC);
