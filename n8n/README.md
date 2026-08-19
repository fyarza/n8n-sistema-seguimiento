# n8n — sistema-seguimiento v2

Bot de Telegram que crea seguimientos y consulta el embudo de WhatsApp. Evolution solo alimenta Postgres: **el flujo 03 no responde al cliente**.

Arquitectura: [`docs/arquitectura.md`](../docs/arquitectura.md).

## Quick path

1. En Postgres, ejecuta `schema.sql` (si ya corriste v1, vuelve a correrlo: las tablas nuevas son `IF NOT EXISTS`).
2. Importa los cuatro JSON (quedan inactivos).
3. Mapea credenciales: Telegram, Postgres, DeepSeek (`deepseek-v4-flash`).
4. En Evolution, webhook POST a `https://<n8n>/webhook/seguimientos-leads` (evento `messages.upsert`).
5. Activa 01, prueba un mensaje. Luego 02, 03 y 04.

## Archivos

| Archivo | Qué es | LLM |
|---------|--------|-----|
| `schema.sql` | Avisos, memoria, **leads WhatsApp** | — |
| `01-telegram-asistente-seguimientos.json` | Chat + tools (seguimientos y embudo) | Sí |
| `02-cron-recordatorios.json` | Avisos 10:00 Caracas | No |
| `03-whatsapp-clasificar-leads.json` | Observador Evolution → scores | Sí (filtro + etapa) |
| `04-cron-silencio-leads.json` | Silencio >24 h tras cotización | No |

n8n tiene que ser alcanzable por HTTPS (`WEBHOOK_URL`). Telegram y Evolution no hablan con localhost.

Zona horaria: `America/Caracas`.

## Flujo 03 — qué hace

Guarda los dos lados del chat. Solo clasifica **texto del cliente** que el Text Classifier marca `relevante` (fechas, precios, habitación, reserva). Cotización de la asesora (`OPCIONES DISPONIBLES`, formulario) marca `quoted_at`. No envía WhatsApp.

## Flujo 04 — silencio

Si `en_proceso`, hay cotización, el cliente lleva >24 h callado y `score_cierre < 50`:

- engagement alto → `pregunto_no_concreto`
- engagement bajo → `no_respondio`

No pisa `concreto`.

## Tools del agente (01)

Siguen siendo **Postgres Tool** v2.6. Si se importan como Postgres normal, el agente no las ve.

| Tool | Para qué |
|------|----------|
| `crear_seguimiento` / `listar_seguimientos` / `cancelar_seguimiento` | Avisos Telegram |
| `listar_leads_potenciales` | Difusión: no reservaron, con potencial |
| `listar_preguntan_sin_reservar` | Preguntan mucho y no cierran |
| `estadisticas_leads_mes` | Conteos y `%` del mes (`YYYY-MM`) |
| `listar_leads_reporte` | Listado por nombre: `concretaron`, `no_concretaron` o `atendidos` (mes YYYY-MM) |

## Memoria del chat Telegram

- `assistant_chat_messages`: últimas **10 interacciones**.
- Si hay más de 20 filas, compacta a `conversation_summaries` (máx. 800 caracteres).

## Si el agente falla al usar tools

Error típico: `reasoning_content must be passed back`. Apagar thinking, o **OpenAI Chat Model** con base URL `https://api.deepseek.com`, la misma key y modelo `deepseek-v4-flash`.
