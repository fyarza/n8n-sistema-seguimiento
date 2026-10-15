# Certificado PDF via Gotenberg (workflow 06)

Objective: Telegram tool + child workflow fills reservation certificate HTML and converts it with Gotenberg to PDF.
Branch: current working branch (no commit until user asks).
Delivery: ask-on-risk. Test: local `node plantilla-certificado/render-certificado.mjs` + curl Gotenberg.

## Specs

S1: "plan con desayuno siempre va a venir" — constant `CON DESAYUNO` in workflow Config / render.
S2: "La fecha de emisión siempre va a ser la fecha en que se crea el certificado" — `now` America/Caracas.
S3: "firmante también es alguna configuración fija" — Config: EVELIN YARZA / EJECUTIVA DE VENTAS / 0424 473 3047.
S4: Variables: nombre, cedula, pax, check_in, check_out, habitacion, monto_total_eur, pagos[], estado_pago.
S5: Payment families A/B/C per commercial + Evelin; Punto de venta = A.
S6: Gotenberg URL `https://test-gotenberg.i3clpy.easypanel.host/forms/chromium/convert/html`; assets via Filebrowser public dl URLs.
S7: Pattern like 05: Execute Workflow Trigger + toolWorkflow on 01; optional Webhook for Postman.

## Tasks

- [x] T1 (S1–S6) inline — HTML template + render engine + local Gotenberg smoke (3-page PDF ~116KB)
- [x] T2 (S7) inline — `n8n/06-telegram-certificado-reserva.json`
- [x] T3 (S7) inline — tool `generar_certificado_reserva` on 01 + README

## Log

L1: User authorized: "si arranca por favor" after closing payment variables (Punto de venta = A).
L2: 2026-10-14 — Implemented template placeholders, render-certificado.mjs, workflow 06 (Execute Workflow + Webhook), tool on 01. Pending: import/publish 06 in n8n and bind workflow id in tool.
