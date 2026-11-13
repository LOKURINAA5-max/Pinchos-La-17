#!/usr/bin/env node
// Agente de impresión de comandas · Pinchos la 17
// Se deja corriendo en UN computador del local (el de caja sirve). Pregunta al servidor por las comandas de cada zona
// y las manda a la impresora térmica de esa zona, conectada de cualquiera de estas dos formas:
//   • "red"  → impresora con WiFi o cable de red (ESC/POS por el puerto 9100). Se indica su IP.
//   • "usb"  → impresora con cable USB conectada a ESTE computador. Se indica su nombre compartido (Windows),
//              su dispositivo (/dev/usb/lp0 en Linux) o su nombre en CUPS (Mac/Linux).
// Solo necesita Node.js 18 o superior. Uso:
//   node impresion/agente.mjs              → imprime las comandas (dejarlo abierto)
//   node impresion/agente.mjs --prueba     → imprime una comanda de prueba en cada impresora del config.json
//   node impresion/agente.mjs --buscar     → busca impresoras de red (WiFi/cable de red) en la red del local
//   node impresion/agente.mjs --impresoras → (Windows) muestra las impresoras USB instaladas y su nombre compartido
import net from 'node:net';
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const ARGS = process.argv.slice(2), BANDERA = (b) => ARGS.includes(b);
const hora = () => new Date().toLocaleTimeString('es-CO');
const log = (...m) => console.log(hora(), ...m), err = (...m) => console.error(hora(), ...m);

/* ---------- Herramientas de instalación (no necesitan config.json) ---------- */
if (BANDERA('--buscar')) await buscarRed();
if (BANDERA('--impresoras')) await listarWindows();

const RUTA = ARGS.find((a) => !a.startsWith('--')) || path.join(DIR, 'config.json');
if (!fs.existsSync(RUTA)) { console.error(`Falta ${RUTA}. Copia config.ejemplo.json como config.json y complétalo (ver LEEME.md).`); process.exit(1); }
const CFG = JSON.parse(fs.readFileSync(RUTA, 'utf8'));
const BASE = String(CFG.servidor || '').replace(/\/+$/, '');
const CADA = Math.max(2, Number(CFG.cada_segundos) || 3) * 1000;

/* ---------- Texto para la impresora ---------- */
// Tildes: con "tildes": true se usa la página de códigos PC850 (Epson, Xprinter, 3nStar, Bixolon...).
// Si en la prueba salen símbolos raros en vez de Á É Ñ, pon "tildes": false y se imprimen sin tilde (siempre funciona).
const CP850 = { 'á': 0xa0, 'é': 0x82, 'í': 0xa1, 'ó': 0xa2, 'ú': 0xa3, 'ñ': 0xa4, 'Ñ': 0xa5, 'Á': 0xb5, 'É': 0x90, 'Í': 0xd6, 'Ó': 0xe0, 'Ú': 0xe9, 'ü': 0x81, 'Ü': 0x9a, '¿': 0xa8, '¡': 0xad, '°': 0xf8, 'º': 0xa7 };
const sinTilde = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[¿¡]/g, '');
function codificar(texto, tildes) {
  const out = [];
  for (const ch of String(texto)) {
    const n = ch.charCodeAt(0);
    if (n < 0x80) out.push(n);
    else if (tildes && CP850[ch] !== undefined) out.push(CP850[ch]);
    else { const s = sinTilde(ch); for (const c of s) if (c.charCodeAt(0) < 0x80) out.push(c.charCodeAt(0)); }
  }
  return Buffer.from(out);
}
// Comandos ESC/POS
const ESC = '\x1b', GS = '\x1d';
const INI = ESC + '@', CENTRO = ESC + 'a\x01', IZQ = ESC + 'a\x00', NEG = ESC + 'E\x01', NONEG = ESC + 'E\x00',
  INV = GS + 'B\x01', NOINV = GS + 'B\x00', TAM = (ancho, alto) => GS + '!' + String.fromCharCode(((ancho - 1) << 4) | (alto - 1)),
  ESPACIADO = ESC + '3\x26', CORTE = '\n\n\n\n' + GS + 'V\x42\x00', PITO = ESC + 'B\x03\x02';
// Parte un texto en renglones de «ancho» caracteres; los siguientes renglones llevan sangría para que se vea que siguen
function partir(texto, ancho, sangria = 0) {
  const lead = (String(texto).match(/^ */) || [''])[0];
  const pal = String(texto).split(/\s+/).filter(Boolean), out = []; let r = '';
  if (pal.length) pal[0] = lead + pal[0];
  for (let p of pal) {
    const max = ancho - (out.length ? sangria : 0);
    while (p.length > max) { if (r) { out.push(r); r = ''; } out.push(p.slice(0, max)); p = p.slice(max); }
    if (!r) r = p; else if ((r + ' ' + p).length <= ancho - (out.length ? sangria : 0)) r += ' ' + p; else { out.push(r); r = p; }
  }
  if (r) out.push(r);
  return out.map((x, i) => (i ? ' '.repeat(sangria) : '') + x);
}
const destino = (c) => c.tipo_pedido === 'mesa' ? 'MESA ' + c.mesa : c.tipo_pedido === 'domicilio' ? 'DOMICILIO' : 'MOSTRADOR';
const horaDe = (iso) => new Date(iso).toLocaleTimeString('es-CO', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: 'America/Bogota' });

// La comanda. imp = configuración de la impresora (papel/columnas/tildes)
export function comanda(j, imp = {}) {
  const c = j.contenido, col = Number(imp.columnas) || (Number(imp.papel) === 58 ? 32 : 48), mitad = Math.floor(col / 2);
  const tildes = imp.tildes ?? CFG?.tildes ?? false, T = (s) => (tildes ? String(s ?? '') : sinTilde(s));
  const may = (s) => T(s).toUpperCase();
  const centrar = (s, w) => { s = s.slice(0, w); const a = Math.floor((w - s.length) / 2); return ' '.repeat(a) + s + ' '.repeat(w - s.length - a); };
  let t = INI + (tildes ? ESC + 't\x02' : '') + ESPACIADO;
  // Encabezado: la zona en blanco sobre negro (se ve desde lejos), número de pedido enorme y destino
  t += CENTRO + NEG + TAM(2, 2) + INV + centrar(may(c.zona), mitad) + NOINV + '\n';
  if (j.tipo === 'anulado') t += '\n' + TAM(2, 2) + INV + centrar('ANULADO', mitad) + NOINV + '\n' + TAM(1, 1) + 'NO PREPARAR ESTE PEDIDO\n';
  t += TAM(3, 3) + '#' + c.numero + '\n';
  t += TAM(2, 2) + partir(may(destino(c)), mitad).join('\n') + '\n';
  t += TAM(1, 1) + NONEG + horaDe(c.hora) + (j.tipo === 'copia' ? '   (COPIA)' : '') + '\n';
  if (c.tipo_pedido === 'domicilio' && c.cliente) t += partir(T(c.cliente), col).join('\n') + '\n';
  if (c.complemento_num) t += NEG + TAM(1, 2) + INV + ` AGREGADO AL PEDIDO #${c.complemento_num} ` + NOINV + TAM(1, 1) + NONEG + '\n';
  t += IZQ + '='.repeat(col) + '\n';
  let unidades = 0;
  for (const l of c.lineas) {
    unidades += Number(l.cantidad) || 0;
    // Cantidad y plato en letra doble (ancho y alto)
    const cab = `${l.cantidad} x `;
    t += NEG + TAM(2, 2) + partir(cab + may(l.nombre), mitad, cab.length).join('\n') + '\n' + TAM(1, 1);
    // Opciones (adicionales, sabores, guarnición): una por renglón, en letra alta
    for (const o of l.opciones || []) {
      const txt = '  + ' + T(o.nombre) + (o.otra_zona ? ` (lo hace ${T(o.otra_zona)})` : '');
      t += (o.otra_zona ? NONEG + TAM(1, 1) : NEG + TAM(1, 2)) + partir(txt, col, 4).join('\n') + '\n';
    }
    t += TAM(1, 1);
    if (l.para) t += NONEG + partir(`  Para: ${T(l.para)}`, col, 8).join('\n') + '\n';
    if (l.origen) t += NONEG + partir(`  De la promo: ${T(l.origen)}`, col, 8).join('\n') + '\n';
    if (l.parte) t += NONEG + partir(`  Parte: ${T(l.parte)}`, col, 8).join('\n') + '\n';
    if (l.sin && l.sin.length) t += NEG + TAM(1, 2) + INV + partir(' SIN ' + may(l.sin.join(', ')) + ' ', col).join('\n') + NOINV + TAM(1, 1) + '\n';
    if (l.nota) t += NEG + TAM(1, 2) + partir('  NOTA: ' + T(l.nota), col, 8).join('\n') + TAM(1, 1) + '\n';
    t += NONEG + '-'.repeat(col) + '\n';
  }
  if (j.tipo === 'anulado' && c.motivo) t += NEG + partir('Motivo: ' + T(c.motivo), col).join('\n') + NONEG + '\n';
  t += NEG + `${unidades} ${unidades === 1 ? 'producto' : 'productos'} en esta comanda\n` + NONEG;
  t += (c.otras && c.otras.length ? partir(T('También preparan: ') + may(c.otras.join(', ')), col).join('\n') : 'Solo esta zona') + '\n';
  t += CENTRO + '\n' + T('Pinchos la 17') + '\n';
  const pie = (imp.pitar ?? CFG?.pitar) === false ? '' : PITO;
  return Buffer.concat([codificar(t, tildes), Buffer.from(pie + CORTE, 'latin1')]);
}

/* ---------- Envío: por red (WiFi / cable de red) o por cable USB ---------- */
const enviarRed = (imp, datos) => new Promise((ok, mal) => {
  const s = net.createConnection({ host: imp.host, port: imp.port || 9100, timeout: 6000 });
  s.on('connect', () => s.end(datos, () => { ok(); setTimeout(() => s.destroy(), 1500); }));
  s.on('timeout', () => { s.destroy(); mal(new Error('la impresora no responde (¿apagada, sin WiFi o IP distinta?)')); });
  s.on('error', (e) => mal(new Error(e.code === 'ECONNREFUSED' ? 'la impresora rechazó la conexión (¿puerto distinto de 9100?)' : e.code === 'EHOSTUNREACH' || e.code === 'ENETUNREACH' ? 'no se encuentra la IP en la red' : e.message)));
});
const correr = (cmd, args) => new Promise((ok, mal) => execFile(cmd, args, { windowsHide: true, timeout: 20000 }, (e, so, se) => e ? mal(new Error((se || so || e.message).toString().trim())) : ok(so)));
async function enviarUsb(imp, datos) {
  const nombre = String(imp.nombre || imp.impresora || '').trim();
  if (!nombre) throw new Error('falta "nombre" de la impresora USB en config.json');
  if (nombre.startsWith('/dev/')) { await fs.promises.writeFile(nombre, datos); return; }            // Linux: directo al dispositivo
  const tmp = path.join(os.tmpdir(), `comanda-${process.pid}-${Date.now()}.bin`);
  await fs.promises.writeFile(tmp, datos);
  try {
    if (process.platform === 'win32') await correr('cmd', ['/c', 'copy', '/b', tmp, `\\\\localhost\\${nombre}`]);   // impresora compartida
    else await correr('lp', ['-d', nombre, '-o', 'raw', tmp]);                                              // Mac / Linux con CUPS
  } catch (e) { throw new Error(`no se pudo enviar a la impresora USB «${nombre}»: ${e.message}. ¿Está compartida con ese nombre?`); }
  finally { fs.promises.unlink(tmp).catch(() => {}); }
}
const tipoDe = (imp) => (imp.tipo || (imp.host ? 'red' : 'usb')).toLowerCase();
const enviar = (imp, datos) => (tipoDe(imp) === 'red' ? enviarRed(imp, datos) : enviarUsb(imp, datos));
const describir = (imp) => tipoDe(imp) === 'red' ? `red ${imp.host}:${imp.port || 9100}` : `USB «${imp.nombre || imp.impresora}»`;

/* ---------- Conexión con el servidor ---------- */
let token = null;
async function api(m, u, b) {
  const r = await fetch(BASE + '/api' + u, { method: m, headers: { 'content-type': 'application/json', 'X-Cliente': 'api', ...(token ? { authorization: 'Bearer ' + token } : {}) }, body: b ? JSON.stringify(b) : undefined });
  const j = await r.json().catch(() => null);
  if (r.status === 401 && token) { token = null; throw new Error('sesión vencida, entrando de nuevo'); }
  if (!r.ok) throw new Error((j && j.error) || 'HTTP ' + r.status);
  return j;
}
async function entrar() {
  const r = await api('POST', '/login', { usuario: CFG.usuario, password: CFG.clave });
  if (r.requiere_2fa) throw new Error('Ese usuario tiene verificación en dos pasos. Usa un usuario de cocina sin 2FA para el agente.');
  token = r.token; log('Conectado al sistema como', r.usuario);
}

/* ---------- Prueba ---------- */
if (BANDERA('--prueba')) {
  const lista = Object.entries(CFG.impresoras || {});
  if (!lista.length) { console.error('No hay impresoras en config.json'); process.exit(1); }
  for (const [zona, imp] of lista) {
    const j = { tipo: 'comanda', contenido: { zona: zona === 'todas' ? 'PRUEBA' : zona, numero: 17, tipo_pedido: 'mesa', mesa: '4', hora: new Date().toISOString(), otras: [], lineas: [
      { cantidad: 2, nombre: 'Pincho mixto', opciones: [{ nombre: 'Arroz' }, { nombre: 'Chorizo de cerdo' }], sin: ['cebolla'], nota: 'Bien asado' },
      { cantidad: 1, nombre: 'Prueba de tildes: ÁÉÍÓÚ Ñ ñ', opciones: [], sin: [] },
    ] } };
    try { await enviar(imp, comanda(j, imp)); log(`✔ Prueba enviada a «${zona}» (${describir(imp)})`); }
    catch (e) { err(`✘ «${zona}» (${describir(imp)}): ${e.message}`); }
  }
  process.exit(0);
}

/* ---------- Ciclo normal ---------- */
let zonas = null; const avisado = new Set(), caidas = new Map();
async function vuelta() {
  if (!token) await entrar();
  if (!zonas) zonas = await api('GET', '/zonas');
  for (const [nombre, imp] of Object.entries(CFG.impresoras || {})) {
    const z = nombre.toLowerCase() === 'todas' ? { id: 'todas' } : zonas.find((x) => x.nombre.toLowerCase() === nombre.toLowerCase());
    if (!z) { if (!avisado.has(nombre)) { avisado.add(nombre); err(`La zona «${nombre}» no existe en el sistema. Revisa los nombres en config.json`); } continue; }
    if ((caidas.get(nombre) || 0) > Date.now()) continue;   // impresora caída: espera unos segundos antes de reintentar
    const trabajos = await api('POST', '/impresion/tomar', { zona: z.id, estacion: ('agente ' + nombre).slice(0, 40) });
    for (const j of trabajos) {
      try {
        await enviar(imp, comanda(j, imp)); await api('POST', `/impresion/${j.id}/hecha`);
        log(`Impresa comanda #${j.contenido.numero} (${j.contenido.zona}${j.tipo !== 'comanda' ? ', ' + j.tipo : ''}) → ${describir(imp)}`);
        caidas.delete(nombre);
      } catch (e) {
        await api('POST', `/impresion/${j.id}/fallo`).catch(() => {});
        caidas.set(nombre, Date.now() + 10000);
        err(`No se pudo imprimir en «${nombre}» (${describir(imp)}): ${e.message}. Se reintenta en 10 s; la comanda sigue en cola.`);
        break;
      }
    }
  }
}
log(`Agente de impresión Pinchos la 17 · servidor ${BASE} · revisa cada ${CADA / 1000} s`);
for (const [n, imp] of Object.entries(CFG.impresoras || {})) log(`  ${n} → ${describir(imp)}`);
for (;;) {
  try { await vuelta(); } catch (e) { err('Error:', e.message); zonas = null; }
  if (process.env.UNA_VEZ) break;
  await new Promise((r) => setTimeout(r, CADA));
}

/* ---------- Funciones de ayuda para instalar ---------- */
async function buscarRed() {
  const redes = Object.values(os.networkInterfaces()).flat().filter((i) => i && i.family === 'IPv4' && !i.internal);
  if (!redes.length) { console.log('No se encontró ninguna red en este computador.'); process.exit(1); }
  console.log('Buscando impresoras de red (puerto 9100) en:', redes.map((r) => r.address.replace(/\.\d+$/, '.0/24')).join(', '), '…');
  const ips = [...new Set(redes.flatMap((r) => { const b = r.address.split('.').slice(0, 3).join('.'); return Array.from({ length: 254 }, (_, i) => `${b}.${i + 1}`); }))];
  const abiertas = [];
  const probar = (ip) => new Promise((ok) => { const s = net.createConnection({ host: ip, port: 9100, timeout: 700 }); s.on('connect', () => { abiertas.push(ip); s.destroy(); ok(); }); s.on('timeout', () => { s.destroy(); ok(); }); s.on('error', () => ok()); });
  for (let i = 0; i < ips.length; i += 64) await Promise.all(ips.slice(i, i + 64).map(probar));
  if (abiertas.length) { console.log('\nImpresoras encontradas:'); for (const ip of abiertas) console.log(`  ${ip}   →  en config.json: { "tipo": "red", "host": "${ip}", "port": 9100 }`); }
  else console.log('\nNo se encontró ninguna. Revisa que la impresora esté encendida y conectada a la MISMA red WiFi que este computador.');
  process.exit(0);
}
async function listarWindows() {
  if (process.platform !== 'win32') {
    console.log('En Mac/Linux: lpstat -p   (nombre CUPS)   o   ls /dev/usb/   (dispositivo, ej. /dev/usb/lp0)'); process.exit(0);
  }
  try {
    const so = await correr('powershell', ['-NoProfile', '-Command', 'Get-Printer | Select-Object Name,Shared,ShareName,PortName | Format-Table -AutoSize | Out-String -Width 200']);
    console.log(so);
    console.log('Usa el valor de "ShareName" en config.json: { "tipo": "usb", "nombre": "EL-SHARENAME" }. Si "Shared" es False, compártela primero (ver LEEME.md).');
  } catch (e) { console.error('No se pudo listar:', e.message); }
  process.exit(0);
}
