#!/usr/bin/env node
/**
 * Renders certificado-reserva.template.html from reservation data.
 * Usable locally (CLI) and as reference for the n8n Code node in workflow 06.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

const DEFAULTS = {
  plan: 'CON DESAYUNO',
  destino: 'Tucacas, Edo. Falcón, Parque Nacional Morrocoy',
  firmante_nombre: 'EVELIN YARZA',
  firmante_cargo: 'EJECUTIVA DE VENTAS',
  firmante_tel: '0424 473 3047',
  timezone: 'America/Caracas',
};

const MESES = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

export function escapeHtml(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function normalizeForma(forma) {
  return String(forma || '')
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

/** A = tasa+EUR; B = Binance/Zelle; C = Transferencia/Pago móvil */
export function paymentFamily(forma) {
  const f = normalizeForma(forma);
  if (/(binance|zelle)/.test(f)) return 'B';
  if (/(transferencia|pago\s*movil)/.test(f)) return 'C';
  return 'A';
}

export function formatFechaEmision(date = new Date(), timeZone = DEFAULTS.timezone) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    day: '2-digit',
    month: 'numeric',
    year: 'numeric',
  }).formatToParts(date);
  const day = parts.find((p) => p.type === 'day')?.value || '01';
  const monthNum = Number(parts.find((p) => p.type === 'month')?.value || '1');
  const year = parts.find((p) => p.type === 'year')?.value || '2026';
  return `Tucacas, ${day} de ${MESES[monthNum - 1]} de ${year}`;
}

/** Commercial-style stamp: 03-10-2026_14-30 (America/Caracas). */
export function formatFilenameStamp(date = new Date(), timeZone = DEFAULTS.timezone) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(date);
  const get = (type, fallback = '00') => parts.find((p) => p.type === type)?.value || fallback;
  const day = get('day', '01');
  const month = get('month', '01');
  const year = get('year', '2026');
  let hour = get('hour', '00');
  if (hour === '24') hour = '00';
  const minute = get('minute', '00');
  return `${day}-${month}-${year}_${hour}-${minute}`;
}

function sanitizeFilenamePart(s) {
  return String(s ?? '')
    .normalize('NFC')
    .replace(/[\/\\:*?"<>|]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toUpperCase();
}

/** Matches commercial files: CERTIFICADO DE RESERVA DE {NOMBRE} {DD-MM-YYYY_HH-mm}--{FIRMANTE}.pdf */
export function buildCertificadoFilename(
  nombre,
  firmanteNombre = DEFAULTS.firmante_nombre,
  date = new Date(),
  timeZone = DEFAULTS.timezone,
) {
  const guest = sanitizeFilenamePart(nombre);
  const signer = sanitizeFilenamePart(firmanteNombre);
  const stamp = formatFilenameStamp(date, timeZone);
  return `CERTIFICADO DE RESERVA DE ${guest} ${stamp}--${signer}.pdf`;
}

export function parseIsoDate(iso) {
  const m = String(iso || '').trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) throw new Error(`Fecha inválida (YYYY-MM-DD): ${iso}`);
  return { y: Number(m[1]), mo: Number(m[2]), d: Number(m[3]) };
}

export function formatDisplayDate(iso) {
  const { y, mo, d } = parseIsoDate(iso);
  return `${String(d).padStart(2, '0')}/${String(mo).padStart(2, '0')}/${y}`;
}

export function durationLabel(checkIn, checkOut) {
  const a = parseIsoDate(checkIn);
  const b = parseIsoDate(checkOut);
  const t0 = Date.UTC(a.y, a.mo - 1, a.d);
  const t1 = Date.UTC(b.y, b.mo - 1, b.d);
  const noches = Math.round((t1 - t0) / 86400000);
  if (noches < 1) throw new Error('check_out debe ser posterior a check_in');
  const dias = noches + 1;
  return `${noches} NOCHES Y ${dias} DIAS`;
}

export function formatEur(n, { spaced = true } = {}) {
  const num = Number(n);
  if (!Number.isFinite(num)) throw new Error(`Monto EUR inválido: ${n}`);
  const body = num.toLocaleString('es-VE', {
    minimumFractionDigits: Number.isInteger(num) ? 0 : 2,
    maximumFractionDigits: 2,
  });
  return spaced ? `€ ${body}` : `€${body}`;
}

export function formatBs(n) {
  const raw = String(n ?? '').trim();
  if (!raw) return '';
  if (/bs\.?\s*s/i.test(raw)) return raw.replace(/\s+/g, '');
  // Already Venezuelan-formatted (e.g. 1.234.567,89 / 912.937,59 / 973,93)
  if (/^\d{1,3}(\.\d{3})+(,\d+)?$/.test(raw) || /^\d{1,3},\d+$/.test(raw)) {
    return `Bs.S${raw}`;
  }
  let num = NaN;
  if (/^\d+(\.\d+)?$/.test(raw)) num = Number(raw); // US / plain
  else if (/^\d+,\d+$/.test(raw)) num = Number(raw.replace(',', '.')); // decimal comma, no thousands
  if (Number.isFinite(num)) {
    return `Bs.S${num.toLocaleString('es-VE', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })}`;
  }
  return `Bs.S${raw}`;
}

function cuentaCell(cuenta, nombreCliente) {
  const c = String(cuenta || '').trim();
  const extra = nombreCliente ? ` <small>${escapeHtml(nombreCliente)}</small>` : '';
  if (!c) return escapeHtml(nombreCliente || '');
  if (/@/.test(c) || /^https?:/i.test(c)) {
    const href = c.includes('@') && !c.startsWith('http') ? `mailto:${c}` : c;
    return `<a href="${escapeHtml(href)}">${escapeHtml(c)}</a>${extra}`;
  }
  return `<a href="#">${escapeHtml(c)}</a>${extra}`;
}

function groupByFamily(pagos) {
  const groups = [];
  for (const row of pagos) {
    const fam = paymentFamily(row.forma);
    const last = groups[groups.length - 1];
    if (last && last.family === fam) last.rows.push(row);
    else groups.push({ family: fam, rows: [row] });
  }
  return groups;
}

function renderTableA(rows, nombreCliente) {
  const body = rows.map((r) => `
        <tr>
          <td>${escapeHtml(r.forma)}</td>
          <td class="right">${escapeHtml(r.fecha)}</td>
          <td>${cuentaCell(r.cuenta, nombreCliente)}</td>
          <td class="num">${escapeHtml(formatBs(r.tasa_euro))}</td>
          <td class="num">${escapeHtml(formatEur(r.monto_eur))}</td>
        </tr>`).join('');
  return `
    <table class="pay">
      <colgroup>
        <col style="width:104.1pt"><col style="width:55.9pt"><col style="width:142.7pt"><col style="width:107pt"><col style="width:88.9pt">
      </colgroup>
      <thead>
        <tr>
          <td>Forma de pago</td>
          <td>Fecha de pago</td>
          <td>Cuenta</td>
          <td class="arial">Tasa del Euro</td>
          <td class="arial">Monto <span>€</span></td>
        </tr>
      </thead>
      <tbody>${body}
      </tbody>
    </table>`;
}

function renderTableB(rows) {
  const body = rows.map((r) => `
        <tr>
          <td>${escapeHtml(r.forma)}</td>
          <td class="right">${escapeHtml(r.fecha)}</td>
          <td>${cuentaCell(r.cuenta)}</td>
          <td>${escapeHtml(r.codigo_o_titular || '')}</td>
          <td class="num">${escapeHtml(formatEur(r.monto_eur))}</td>
        </tr>`).join('');
  return `
    <table class="pay">
      <colgroup>
        <col style="width:90pt"><col style="width:55pt"><col style="width:160pt"><col style="width:110pt"><col style="width:83pt">
      </colgroup>
      <thead>
        <tr>
          <td>Forma de pago</td>
          <td>Fecha de pago</td>
          <td>Cuenta</td>
          <td class="arial">Código / Titular</td>
          <td class="arial">Monto <span>€</span></td>
        </tr>
      </thead>
      <tbody>${body}
      </tbody>
    </table>`;
}

function renderTableC(rows) {
  const body = rows.map((r) => `
        <tr>
          <td>${escapeHtml(r.forma)}</td>
          <td class="right">${escapeHtml(r.fecha)}</td>
          <td>${cuentaCell(r.cuenta)}</td>
          <td>${escapeHtml(r.ref_o_titular || r.codigo_o_titular || '')}</td>
          <td class="num">${escapeHtml(formatBs(r.tasa_euro))}</td>
          <td class="num">${escapeHtml(formatBs(r.monto_bs))}</td>
          <td class="num">${escapeHtml(formatEur(r.monto_eur))}</td>
        </tr>`).join('');
  // Wider "Monto Bs." (~128pt) so amounts ≥ Bs.S1.000.000 do not collide with Tasa / Monto €
  return `
    <table class="pay pay-c">
      <colgroup>
        <col style="width:76pt"><col style="width:36pt"><col style="width:68pt"><col style="width:64pt"><col style="width:62pt"><col style="width:118pt"><col style="width:74.6pt">
      </colgroup>
      <thead>
        <tr>
          <td>Forma de pago</td>
          <td>Fecha</td>
          <td>Cuenta</td>
          <td class="arial">Ref. / Titular</td>
          <td class="arial">Tasa €</td>
          <td class="arial">Monto Bs.</td>
          <td class="arial">Monto <span>€</span></td>
        </tr>
      </thead>
      <tbody>${body}
      </tbody>
    </table>`;
}

export function renderPagosHtml(pagos, nombreCliente) {
  if (!Array.isArray(pagos) || pagos.length === 0) {
    throw new Error('pagos[] es obligatorio (al menos 1 fila)');
  }
  return groupByFamily(pagos)
    .map((g, i) => {
      const table =
        g.family === 'B' ? renderTableB(g.rows)
          : g.family === 'C' ? renderTableC(g.rows)
            : renderTableA(g.rows, i === 0 ? nombreCliente : '');
      return i === 0 ? table : `<div class="gap12"></div>${table}`;
    })
    .join('\n');
}

export function renderCertificado(input, templateHtml) {
  const cfg = { ...DEFAULTS, ...(input.config || {}) };
  const nombre = String(input.nombre || '').trim();
  const cedula = String(input.cedula || '').trim();
  const habitacion = String(input.habitacion || '').trim();
  const checkIn = String(input.check_in || '').trim();
  const checkOut = String(input.check_out || '').trim();
  const pax = Number(input.pax);
  const montoTotal = Number(input.monto_total_eur);
  const estadoPago = String(input.estado_pago || 'PAGO COMPLETO').trim();
  let pagos = input.pagos;
  if (typeof pagos === 'string') {
    pagos = JSON.parse(pagos);
  }
  if (!nombre || !cedula || !habitacion || !checkIn || !checkOut) {
    throw new Error('Faltan nombre, cedula, habitacion, check_in o check_out');
  }
  if (!Number.isFinite(pax) || pax < 1) throw new Error('pax inválido');
  if (!Number.isFinite(montoTotal)) throw new Error('monto_total_eur inválido');

  const duracion = durationLabel(checkIn, checkOut);
  const emittedAt = input.now ? new Date(input.now) : new Date();
  const fechaEmision = formatFechaEmision(emittedAt, cfg.timezone);
  const filename = buildCertificadoFilename(
    nombre,
    cfg.firmante_nombre,
    emittedAt,
    cfg.timezone,
  );
  const montoTotalLabel = formatEur(montoTotal, { spaced: false });
  const pagadoSum = Array.isArray(pagos)
    ? pagos.reduce((s, r) => s + Number(r.monto_eur || 0), 0)
    : montoTotal;
  const montoPagadoLine = `Monto Pagado: ${formatEur(pagadoSum, { spaced: false })} (${estadoPago})`;

  const map = {
    '{{FECHA_EMISION}}': escapeHtml(fechaEmision),
    '{{NOMBRE}}': escapeHtml(nombre.toUpperCase()),
    '{{CEDULA}}': escapeHtml(cedula),
    '{{PLAN}}': escapeHtml(cfg.plan),
    '{{PAX}}': escapeHtml(String(pax)),
    '{{DURACION}}': escapeHtml(duracion),
    '{{CHECK_IN}}': escapeHtml(formatDisplayDate(checkIn)),
    '{{CHECK_OUT}}': escapeHtml(formatDisplayDate(checkOut)),
    '{{HABITACION}}': escapeHtml(habitacion.toUpperCase()),
    '{{DESTINO}}': escapeHtml(cfg.destino),
    '{{MONTO_TOTAL}}': escapeHtml(montoTotalLabel),
    '{{PAGOS_HTML}}': renderPagosHtml(pagos, nombre.toUpperCase()),
    '{{MONTO_PAGADO_LINE}}': escapeHtml(montoPagadoLine),
    '{{FIRMANTE_NOMBRE}}': escapeHtml(cfg.firmante_nombre),
    '{{FIRMANTE_CARGO}}': escapeHtml(cfg.firmante_cargo),
    '{{FIRMANTE_TEL}}': escapeHtml(cfg.firmante_tel),
  };

  let html = templateHtml;
  for (const [k, v] of Object.entries(map)) {
    html = html.split(k).join(v);
  }
  if (/\{\{[A-Z0-9_]+\}\}/.test(html)) {
    throw new Error(`Quedaron placeholders sin reemplazar: ${html.match(/\{\{[A-Z0-9_]+\}\}/g)}`);
  }
  return {
    html,
    meta: {
      nombre,
      cedula,
      check_in: checkIn,
      check_out: checkOut,
      duracion,
      fecha_emision: fechaEmision,
      filename,
    },
  };
}

const ELVIS_SAMPLE = {
  nombre: 'ELVIS RANGEL',
  cedula: 'V-14.017.336',
  pax: 2,
  check_in: '2026-10-03',
  check_out: '2026-10-04',
  habitacion: '1 MATRIMONIAL ESTÁNDAR',
  monto_total_eur: 130,
  estado_pago: 'PAGO COMPLETO',
  pagos: [
    {
      forma: 'EFECTIVO',
      fecha: '3-oct',
      cuenta: 'EFECTIVO',
      tasa_euro: '973,93',
      monto_eur: 130,
    },
  ],
  now: '2026-10-03T15:00:00-04:00',
};

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('render-certificado.mjs')) {
  const templatePath = join(__dirname, 'certificado-reserva.template.html');
  const outPath = join(__dirname, 'certificado-reserva.rendered.html');
  const template = readFileSync(templatePath, 'utf8');
  const { html, meta } = renderCertificado(ELVIS_SAMPLE, template);
  writeFileSync(outPath, html, 'utf8');
  console.log(JSON.stringify({ ok: true, outPath, meta }, null, 2));
}
