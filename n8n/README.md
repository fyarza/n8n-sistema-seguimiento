# n8n — sistema-seguimiento v2

Bot de Telegram que crea seguimientos y consulta el embudo de WhatsApp. Evolution solo alimenta Postgres: **el flujo 03 no responde al cliente**.

Arquitectura: [`docs/arquitectura.md`](../docs/arquitectura.md).

**Recursos:** [Bot Telegram](https://t.me/eve_leads_bot) · [Video demo](https://youtu.be/Q20pbcjGBMI) · [Repositorio](https://github.com/fyarza/n8n-sistema-seguimiento)

## Quick path

1. En Postgres, ejecuta `schema.sql` (si ya corriste v1/v2, vuelve a correrlo: tablas nuevas son `IF NOT EXISTS`; el ALTER actualiza `kind` para llegada y añade `media_analysis` / `media_signal`; crea/seed `team_phones` para traspasos del equipo).
2. Importa los cinco JSON (quedan inactivos).
3. Mapea credenciales: Telegram, Postgres, DeepSeek (`deepseek-flash`) y **OpenAI (DeepSeek vision)** (misma key, Base URL `https://api.deepseek.com/v1`).
4. Speaches y Docling del 03 salen de la tabla `app_config` (nodo **Cargar config**). Las claves se actualizan en Postgres, no en el JSON. Modelo Speaches: `Systran/faster-whisper-small`, `language=es`. DeepSeek sigue en la credencial de n8n.
5. En Evolution, webhook POST a `https://demo-n8n.hiti0l.easypanel.host/webhook/seguimientos-leads` (evento `messages.upsert`).
6. Activa 01, prueba un mensaje. Luego 02, 03, 04, **05** y **06**.
7. En el 01, tool `enviar_grafica`: elige el workflow 05 y refresca los inputs (`telegram_chat_id`, `tipo`, `periodo`, `estilo`). El 05 tiene que estar **publicado**.
8. Tool `generar_certificado_reserva`: elige el workflow 06 y refresca inputs. El 06 tiene que estar **publicado**. Gotenberg: `Config.gotenbergUrl` (default `https://test-gotenberg.i3clpy.easypanel.host/forms/chromium/convert/html`). Assets en Filebrowser (URLs públicas en la plantilla).

## Archivos

| Archivo | Qué es | LLM |
|---------|--------|-----|
| `schema.sql` | Avisos, memoria, **leads WhatsApp** | — |
| `01-telegram-asistente-seguimientos.json` | Chat + tools (seguimientos y embudo); **notas de voz** vía Speaches | Sí |
| `02-cron-recordatorios.json` | Avisos 10:00 / 16:00 / 20:00 Caracas | No |
| `03-whatsapp-clasificar-leads.json` | Observador Evolution → scores + visión + audios + **certificados PDF (Docling)** | Sí (filtro + etapa + `deepseek-flash`) |
| `04-cron-silencio-leads.json` | Silencio >24 h tras cotización | No |
| `05-telegram-grafica-reportes.json` | SQL → QuickChart → foto Telegram | No |
| `06-telegram-certificado-reserva.json` | HTML plantilla → Gotenberg PDF → documento Telegram | No |

n8n tiene que ser alcanzable por HTTPS (`WEBHOOK_URL`). Telegram y Evolution no hablan con localhost.

Zona horaria: `America/Caracas`.

## Flujo 01 — voz Telegram

Acepta texto o nota de voz (`voice` / `audio`). Si es voz: `record_voice` → descarga → Speaches (timeout 300s) → el agente recibe `[Audio] …`. URL y Bearer salen de `app_config` (`speaches_url`, `speaches_api_key`), las mismas claves del 03. Si STT falla, aviso fijo (no se pega HTML del 502). DeepSeek Chat en prod: `maxTokens` 4904, temp `0.2`.

Respuestas: `Dividir Mensaje` convierte Markdown→HTML Telegram (`<b>`, tablas en `<pre>`, teléfonos en `<code>`), parte a ≤3500 y el loop envía con `typing` + Wait 1s. `parse_mode=HTML` (n8n por defecto fuerza Markdown y rompe con `_`/`*` → *can't parse entities*).

## Flujo 03 — qué hace

Guarda los dos lados del chat. **Lista negra**: `team_phones.skip_followup=true` → solo guarda (sin Docling/LLM/score). Agregar/quitar números es solo SQL en BD (no hace falta reimportar el 03). Comerciales con `skip_followup=false` siguen el flujo (certificados/traspasos); los reportes del 01/05 los sacan del `%` pero los listan como traspaso. Clasifica **texto del cliente** relevante (fechas, precios, habitación, reserva), **imágenes del cliente** con DeepSeek vision (`deepseek-flash`) y **audios del cliente** con Speaches (`[Audio] …`). Un comprobante (`media_signal=pago`) fuerza `concreto`. Cotización de la asesora (`OPCIONES DISPONIBLES`, formulario) marca `quoted_at`. No envía WhatsApp.

Para visión: crea una credencial **OpenAI** (no el nodo nativo DeepSeek) con la misma API key y Base URL `https://api.deepseek.com/v1`. El webhook de Evolution debe traer `server_url`, `instance` y `apikey` (el 03 los usa para `getBase64FromMediaMessage`). Si la media expiró, guarda `[Imagen no disponible]` y no rompe el flujo.

Para audio: Evolution baja el `ogg`, **Transcribir audio** llama a Speaches (`/v1/audio/transcriptions`) y **Guardar texto audio** deja el body como `[Audio] texto`. Si falla, queda `[Audio enviado]` y el flujo sigue.

Para certificados de la asesora: documento cuyo body/archivo contiene `certificado` → Evolution baja el PDF → [Docling Serve](https://github.com/docling-project/docling-serve) (`/v1/convert/file`, header `X-Api-Key`, **`page_range=1,1`** solo 1ª hoja) → guarda un **resumen** en `body` (huésped, cédula, check-in/out, habitación, plan, PAX, monto, pago) + `media_analysis` JSON + `media_signal=reserva` y stage `concreto`. Si Docling falla, guarda `[Documento no leido]` y no tumba el flujo.

Params de prod embebidos en el JSON (no se pierden al reimportar): contexto `LIMIT 20`; Filtro `maxTokens=2024` + `timeout=20s` + retry 2×1.5s; Clasificar `maxTokens=3024`; Vision `maxTokens=3048` + `json_object`. URL y API key de Speaches/Docling viven en `app_config`.

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
| `estadisticas_leads_mes` | Conteos del mes: nuevos / recurrentes / **traspaso** (equipo); **lista negra fuera de todos los totales**; `%` solo con clientes |
| `listar_leads_reporte` | Listado: `concretaron` / `no_concretaron` / `traspasos` / `lista_negra` / `atendidos`. `origen` incluye `lista_negra` |
| `listar_lista_negra` | Teléfonos con `skip_followup=true` (sin seguimiento WhatsApp) |
| `gestionar_lista_negra` | `agregar` / `quitar` teléfono en lista negra (BD); al agregar anula scores del lead |
| `listar_usuarios_asistente` | Solo `desarrollo`. Equipo completo y datos faltantes |
| `gestionar_acceso_asistente` | Solo `desarrollo`. Es el workflow 07. `autorizar` reutiliza la fila, toma el nombre de `assistant_access_requests` si no lo repites y avisa a esa persona. El id de Telegram no se guarda como teléfono |
| `gestionar_permisos_herramientas` | Solo `desarrollo`. `listar` / `conceder` / `revocar` en `assistant_tool_acl` |

Las herramientas de administración no van conectadas al agente de un comercial o una asesora. El permiso de cada rol está en `assistant_tool_acl`. `assistant_tool_person` es la excepción de una persona: si `allowed` es false, esa persona no usa la herramienta aunque su rol sí. `assistant_may` aplica primero la persona y después el rol. Volver a correr `schema.sql` no devuelve un permiso de rol que ya se revocó y no borra las excepciones.
| `consultar_ficha_lead` | Ficha de un teléfono/nombre: first_touch, certificados y avisos |
| `enviar_grafica` | Tool Workflow: dispara el 05. `embudo_mes`, `reservas_dia` o `reservas_origen`. Estilo: `barras`, `pie`, `lineas` |
| `generar_certificado_reserva` | Tool Workflow: dispara el 06. Arma HTML (plan fijo CON DESAYUNO, fecha Caracas) → Gotenberg → PDF al chat |

`enviar_grafica` **no** es postgresTool. El id del workflow 05 está en `app_config.workflow_05_id`. QuickChart: `Config.quickchartUrl` en el 05 (`http://quickchart:80/chart` o `https://demo-quickchart.hiti0l.easypanel.host/chart`).

Quien escribe sin permiso queda en `assistant_access_requests` (nombre de Telegram y usuario). Al autorizar, si no pasas el nombre, se usa ese. El workflow 07 (`app_config.workflow_07_id`) hace el alta y el Telegram de aviso. Importa el 07, copia su id a esa clave y reimporta el 01.

`generar_certificado_reserva` tampoco es postgresTool. El id del workflow 06 está en `app_config.workflow_06_id`. Entradas: `nombre`, `cedula`, `pax`, `check_in`, `check_out`, `habitacion`, `monto_total_eur`, `pagos` (JSON array), `estado_pago`. Webhook de prueba: `POST /webhook/seguimientos-certificado`. Motor local: `plantilla-certificado/render-certificado.mjs`.

## Memoria del chat Telegram

- `assistant_chat_messages`: ventana corta del agente.
- Compacta a `conversation_summaries` solo si hay **más de 40** filas; luego borra y deja **20**. Así el contador baja a ~20 y no vuelve a compactar en cada mensaje (hace falta acumular otra vez ~20 msgs).

## Si el agente falla al usar tools

Error típico: `reasoning_content must be passed back`. Apagar thinking, o **OpenAI Chat Model** con base URL `https://api.deepseek.com`, la misma key y modelo `deepseek-v4-flash`.
