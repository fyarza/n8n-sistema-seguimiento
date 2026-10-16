-- sistema-seguimiento v2
-- Zona horaria de negocio: America/Caracas.
-- Comercial: avisos 10:00 (t3 y day). Llegada: 16:00 y 20:00 (arrival_16, arrival_20).
-- Correr este script en Postgres ANTES de activar los workflows de n8n.
-- v2 añade leads de WhatsApp (Evolution). Es idempotente (IF NOT EXISTS).
-- Re-ejecutar actualiza el CHECK de kind (llegada) y añade media_analysis / media_signal.

CREATE TABLE IF NOT EXISTS followup_reminders (
  id BIGSERIAL PRIMARY KEY,
  telegram_chat_id BIGINT NOT NULL,
  client_name TEXT NOT NULL,
  client_phone TEXT NOT NULL,
  estimated_date DATE NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('t3', 'day', 'arrival_16', 'arrival_20')),
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

-- Postgres ya desplegado: CREATE TABLE IF NOT EXISTS no cambia el CHECK viejo.
ALTER TABLE followup_reminders DROP CONSTRAINT IF EXISTS followup_reminders_kind_check;
ALTER TABLE followup_reminders ADD CONSTRAINT followup_reminders_kind_check
  CHECK (kind IN ('t3', 'day', 'arrival_16', 'arrival_20'));

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
  media_analysis TEXT,
  media_signal TEXT,
  occurred_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (lead_id, evolution_message_id)
);

-- Postgres ya desplegado: CREATE IF NOT EXISTS no añade columnas nuevas.
ALTER TABLE whatsapp_messages ADD COLUMN IF NOT EXISTS media_analysis TEXT;
ALTER TABLE whatsapp_messages ADD COLUMN IF NOT EXISTS media_signal TEXT;
ALTER TABLE whatsapp_messages DROP CONSTRAINT IF EXISTS whatsapp_messages_media_signal_check;
ALTER TABLE whatsapp_messages ADD CONSTRAINT whatsapp_messages_media_signal_check
  CHECK (media_signal IS NULL OR media_signal IN ('pago', 'reserva', 'consulta', 'ninguna'));

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

-- URLs y secretos que el flujo 03 lee al inicio (Cargar config).
-- ON CONFLICT DO NOTHING: re-ejecutar schema no pisa claves ya cargadas en prod.
CREATE TABLE IF NOT EXISTS app_config (
  config_key TEXT PRIMARY KEY,
  config_value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO app_config (config_key, config_value) VALUES
  ('speaches_url', 'https://test-speaches.i3clpy.easypanel.host/v1/audio/transcriptions'),
  ('speaches_api_key', 'PEGAR_SPEACHES_API_KEY'),
  ('docling_url', 'https://test-docling.i3clpy.easypanel.host/v1/convert/file'),
  ('docling_api_key', 'PEGAR_DOCLING_API_KEY')
ON CONFLICT (config_key) DO NOTHING;

-- Números del equipo de ventas / traspaso interno (no son captación del chat).
-- Mantener con INSERT/UPDATE; los reportes excluyen active=true del % de conversión.
-- skip_followup=true = lista negra del flujo 03 (guarda mensaje, sin Docling/LLM/score).
-- Agregar números a la lista negra: solo BD, sin reimportar n8n.
CREATE TABLE IF NOT EXISTS team_phones (
  id BIGSERIAL PRIMARY KEY,
  phone TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  team_tag TEXT NOT NULL DEFAULT 'equipo_ventas',
  active BOOLEAN NOT NULL DEFAULT true,
  skip_followup BOOLEAN NOT NULL DEFAULT false,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT team_phones_phone_digits CHECK (phone ~ '^[0-9]+$'),
  UNIQUE (phone)
);

ALTER TABLE team_phones
  ADD COLUMN IF NOT EXISTS skip_followup BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_team_phones_active
  ON team_phones (phone)
  WHERE active;

CREATE INDEX IF NOT EXISTS idx_team_phones_skip_followup
  ON team_phones (phone)
  WHERE active AND skip_followup;

-- Seed confirmado (nombre + número). ON CONFLICT actualiza nombre/tag/lista negra si re-ejecutas.
INSERT INTO team_phones (phone, name, team_tag, skip_followup, notes) VALUES
  ('584127425397', 'Yoly Cuicas', 'equipo_ventas', false, 'Baywatch Reservas / traspasos'),
  ('584244208619', 'Yenny Morales', 'equipo_ventas', false, 'Hotel Baywatch Morrocoy'),
  ('584144355578', 'Clismary Orasma', 'equipo_ventas', false, NULL),
  ('584244739618', 'Relvis Olivares', 'equipo_ventas', false, NULL),
  ('584126470732', 'Jesus Gallardo', 'equipo_ventas', false, NULL),
  ('584144026889', 'Darwin Brett', 'equipo_ventas', false, 'A menudo alias Evelin Yarza en WhatsApp'),
  ('584244676361', 'Jeannie Barrolleta', 'equipo_ventas', false, NULL),
  ('584144202819', 'Danielys Polanco', 'equipo_ventas', false, NULL),
  ('584124067967', 'Federico Yarza', 'desarrollo', true, 'Lista negra WhatsApp: pruebas / no es cliente')
ON CONFLICT (phone) DO UPDATE SET
  name = EXCLUDED.name,
  team_tag = EXCLUDED.team_tag,
  skip_followup = EXCLUDED.skip_followup,
  notes = COALESCE(EXCLUDED.notes, team_phones.notes),
  active = true,
  updated_at = now();

-- Undo false client scoring when internal numbers were treated as leads.
UPDATE leads SET
  stage = 'en_proceso',
  score_potencial = 0,
  score_engagement = 0,
  score_cierre = 0,
  score_silencio = 0,
  last_reason = 'Numero interno (team_phones): score anulado',
  updated_at = now()
WHERE phone = '584124067967'
  AND (
    stage = 'concreto'
    OR score_cierre > 0
    OR COALESCE(last_reason, '') ILIKE '%certificado%'
  );
