# n8n — sistema-seguimiento v1

Bot de Telegram (solo texto) que crea seguimientos en Postgres y avisa en el mismo chat. Sin Google Calendar.

## Archivos

| Archivo | Qué es |
|---|---|
| `schema.sql` | Tablas: avisos, resumen durable, memoria corta |
| `01-telegram-asistente-seguimientos.json` | Chat + agente DeepSeek + tools |
| `02-cron-recordatorios.json` | Avisos cada 15 min, sin LLM |

## Cómo importar

1. En Postgres, ejecuta `schema.sql`.
2. En n8n: **Import from File** cada JSON (quedan inactivos).
3. En cada nodo, mapea credenciales reales:
   - Telegram (el mismo bot en ambos flujos)
   - Postgres
   - DeepSeek (`DeepSeek account` → modelo `deepseek-v4-flash`)
4. En **Config** del flujo 01, opcional: `allowedChatIds` con los chat id permitidos, separados por coma.
5. Activa primero el 01 y prueba un mensaje. Luego el 02.

n8n tiene que ser alcanzable por HTTPS (`WEBHOOK_URL`). Telegram no habla con localhost.

Zona horaria de ambos workflows: `America/Caracas`. Los avisos se guardan a las 10:00 local (T-3 y el día). El cron corre cada 15 min y solo envía `pending` con `fire_at <= now()`.

## Memoria del chat

- `assistant_chat_messages`: el nodo **Postgres Chat Memory** inyecta las últimas **10 interacciones**.
- Si hay más de 20 filas, **Compactar historial** resume lo viejo (máx. 800 caracteres) en `conversation_summaries` y borra el resto.
- El resumen entra al system prompt para no perder clientes/fechas antiguas.

## Tools del agente

`crear_seguimiento`, `listar_seguimientos` y `cancelar_seguimiento` son **Postgres Tool** (`n8n-nodes-base.postgresTool` v2.6). El nodo Postgres normal (`n8n-nodes-base.postgres`) queda para el flujo principal (cargar resumen, compactar, cron). Si se importan como Postgres normal, n8n los deja sueltos y el agente no los ve.

En el canvas: Agent → Tools → Postgres. Borrar el tool vacío "Execute a SQL query" (exige Query).

## Si el agente falla al usar tools

Error típico: `reasoning_content must be passed back`. En V4 el thinking viene prendido. Opciones: community node que apague thinking, o **OpenAI Chat Model** con base URL `https://api.deepseek.com`, la misma API key y modelo `deepseek-v4-flash`.
