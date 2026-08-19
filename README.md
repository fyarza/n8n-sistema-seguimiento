# n8n — sistema-seguimiento v2

Asistente conversacional en Telegram para programar avisos comerciales y consultar un embudo de leads alimentado por WhatsApp (Evolution API), con clasificación automática por IA y detección de silencio post-cotización.

**Autor:** Federico Yarza

## Recursos del proyecto

| Recurso | URL |
|---------|-----|
| Repositorio | https://github.com/fyarza/n8n-sistema-seguimiento |
| Bot Telegram | https://t.me/eve_leads_bot |
| Webhook Evolution (prod.) | https://demo-n8n.hiti0l.easypanel.host/webhook/seguimientos-leads |
| Instancia n8n | https://demo-n8n.hiti0l.easypanel.host/ *(acceso privado; evaluación vía bot, webhook y evidencia en repo)* |
| Video demo | https://youtu.be/Q20pbcjGBMI |

## Documentación

- [Arquitectura v2](docs/arquitectura.md)
- [Guía de despliegue n8n](n8n/README.md)
- [Informe final del proyecto (TFC)](docs/informe-final.md)
- [Evidencia de funcionamiento (capturas)](docs/evidencia/)

## Stack

n8n · PostgreSQL · Telegram Bot API · Evolution API · DeepSeek (`deepseek-v4-flash`)

## Workflows

| # | Archivo | Función |
|---|---------|---------|
| 01 | `n8n/01-telegram-asistente-seguimientos.json` | Asistente Telegram + tools |
| 02 | `n8n/02-cron-recordatorios.json` | Avisos programados 10:00 Caracas |
| 03 | `n8n/03-whatsapp-clasificar-leads.json` | Observador WhatsApp → embudo |
| 04 | `n8n/04-cron-silencio-leads.json` | Detección silencio >24 h |
