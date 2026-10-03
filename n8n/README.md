# n8n — sistema-seguimiento v2

Bot de Telegram que crea seguimientos y consulta el embudo de WhatsApp. Evolution solo alimenta Postgres: **el flujo 03 no responde al cliente**.

Arquitectura: [`docs/arquitectura.md`](../docs/arquitectura.md).

**Recursos:** [Bot Telegram](https://t.me/eve_leads_bot) · [Video demo](https://youtu.be/Q20pbcjGBMI) · [Repositorio](https://github.com/fyarza/n8n-sistema-seguimiento)

## Quick path

1. En Postgres, ejecuta `schema.sql` (si ya corriste v1/v2, vuelve a correrlo: tablas nuevas son `IF NOT EXISTS`; el ALTER actualiza `kind` para llegada y añade `media_analysis` / `media_signal`).
2. Importa los cinco JSON (quedan inactivos).
3. Mapea credenciales: Telegram, Postgres, DeepSeek (`deepseek-flash`) y **OpenAI (DeepSeek vision)** (misma key, Base URL `https://api.deepseek.com/v1`).
4. Speaches (transcripción de audios WhatsApp): servicio self-hosted con API OpenAI-compatible. En el nodo **Transcribir audio** del 03, pega la URL y `Bearer PEGAR_SPEACHES_API_KEY`. Modelo: `Systran/faster-whisper-small`, `language=es`.
5. En Evolution, webhook POST a `https://demo-n8n.hiti0l.easypanel.host/webhook/seguimientos-leads` (evento `messages.upsert`).
6. Activa 01, prueba un mensaje. Luego 02, 03, 04 y **05**.
7. En el 01, tool `enviar_grafica`: elige el workflow 05 y refresca los inputs (`telegram_chat_id`, `tipo`, `periodo`, `estilo`). El 05 tiene que estar **publicado**.

## Archivos

| Archivo | Qué es | LLM |
|---------|--------|-----|
| `schema.sql` | Avisos, memoria, **leads WhatsApp** | — |
| `01-telegram-asistente-seguimientos.json` | Chat + tools (seguimientos y embudo); **notas de voz** vía Speaches | Sí |
| `02-cron-recordatorios.json` | Avisos 10:00 / 16:00 / 20:00 Caracas | No |
| `03-whatsapp-clasificar-leads.json` | Observador Evolution → scores + visión + **audios (Speaches)** | Sí (filtro + etapa + `deepseek-flash`) |
| `04-cron-silencio-leads.json` | Silencio >24 h tras cotización | No |
| `05-telegram-grafica-reportes.json` | SQL → QuickChart → foto Telegram | No |

n8n tiene que ser alcanzable por HTTPS (`WEBHOOK_URL`). Telegram y Evolution no hablan con localhost.

Zona horaria: `America/Caracas`.

## Flujo 01 — voz Telegram

Acepta texto o nota de voz (`voice` / `audio`). Si es voz: Telegram descarga el archivo → Speaches transcribe → el agente recibe `[Audio] …`. Misma URL/Bearer que el 03 (`PEGAR_SPEACHES_API_KEY`). DeepSeek Chat en prod: `maxTokens` 4904, temp `0.2`.

## Flujo 03 — qué hace

Guarda los dos lados del chat. Clasifica **texto del cliente** relevante (fechas, precios, habitación, reserva), **imágenes del cliente** con DeepSeek vision (`deepseek-flash`) y **audios del cliente** con Speaches (`[Audio] …`). Un comprobante (`media_signal=pago`) fuerza `concreto`. Cotización de la asesora (`OPCIONES DISPONIBLES`, formulario) marca `quoted_at`. No envía WhatsApp.

Para visión: crea una credencial **OpenAI** (no el nodo nativo DeepSeek) con la misma API key y Base URL `https://api.deepseek.com/v1`. El webhook de Evolution debe traer `server_url`, `instance` y `apikey` (el 03 los usa para `getBase64FromMediaMessage`). Si la media expiró, guarda `[Imagen no disponible]` y no rompe el flujo.

Para audio: Evolution baja el `ogg`, **Transcribir audio** llama a Speaches (`/v1/audio/transcriptions`) y **Guardar texto audio** deja el body como `[Audio] texto`. Si falla, queda `[Audio enviado]` y el flujo sigue.

## Flujo 04 — silencio

Si `en_proceso`, hay cotización, el cliente lleva >24 h callado y `score_cierre < 50`:

- engagement alto → `pregunto_no_concreto`
- engagement bajo → `no_respondio`

No pisa `concreto`.

## Tools del agente (01)

Siguen siendo **Postgres Tool** v2.6. Si se importan como Postgres normal, el agente no las ve.

| Tool | Para qué |
|------|----------|
| `crear_seguimiento` | Comercial: t3 + day a las 10:00 |
| `crear_seguimiento_llegada` | Llegada: 16:00 y 20:00 el día indicado |
| `listar_seguimientos` | Pendientes, con tipo legible |
| `cancelar_seguimiento` | Cancela; pasa `tipo`: `llegada`, `comercial` o `todos` |
| `listar_leads_potenciales` | Difusión: no reservaron, con potencial |
| `listar_preguntan_sin_reservar` | Preguntan mucho y no cierran |
| `estadisticas_leads_mes` | Conteos del mes: `reservaron` = cierres (certificado o primer concreto), incluye recurrentes |
| `listar_leads_reporte` | Listado: `concretaron` (cierre **en ese mes**), `no_concretaron`, `atendidos`. Campo `origen` |
| `consultar_ficha_lead` | Ficha de un teléfono/nombre: first_touch, certificados y avisos |
| `enviar_grafica` | Tool Workflow: dispara el 05. `embudo_mes`, `reservas_dia` o `reservas_origen`. Estilo: `barras`, `pie`, `lineas` |

`enviar_grafica` **no** es postgresTool. Tras importar, selecciona el workflow 05 (el JSON trae `PEGAR_ID_WORKFLOW_05`). QuickChart: `Config.quickchartUrl` en el 05 (`http://quickchart:80/chart` o `https://demo-quickchart.hiti0l.easypanel.host/chart`).

## Memoria del chat Telegram

- `assistant_chat_messages`: últimas **10 interacciones**.
- Si hay más de 20 filas, compacta a `conversation_summaries` (máx. 800 caracteres).

## Si el agente falla al usar tools

Error típico: `reasoning_content must be passed back`. Apagar thinking, o **OpenAI Chat Model** con base URL `https://api.deepseek.com`, la misma key y modelo `deepseek-v4-flash`.
