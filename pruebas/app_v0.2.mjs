// =============================================================================
// Prueba de la aplicación v0.2 con Supabase SIMULADO.
// Sirve app/ en localhost y responde las llamadas a Supabase desde aquí, para probar la
// interfaz por rol sin tocar la base real.
//
// Uso:  node pruebas/app_v0.2.mjs [carpeta_capturas]
// Requiere: npm i playwright  (y un Chromium; ver PLAYWRIGHT_BROWSERS_PATH)
// =============================================================================
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'app');
const CAPTURAS = process.argv[2] || null;
const SUPA = 'https://lwhczkzhsnqawettzzfw.supabase.co';
const TIPOS = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.woff2': 'font/woff2', '.webmanifest': 'application/manifest+json' };

// ---------------------------------------------------------------- servidor local de app/
const servidor = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]); if (p === '/') p = '/index.html';
  const f = path.join(RAIZ, p);
  if (!f.startsWith(RAIZ) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': TIPOS[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
});
await new Promise((r) => servidor.listen(8765, r));
const URL_APP = 'http://localhost:8765/';

// ---------------------------------------------------------------- Supabase simulado
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const USUARIOS = {
  'coord@refri.test':   { id: '11111111-1111-4111-8111-111111111111', perfil: { perfil_id: 'p1', nombre: 'Juan Escalante', cargo: 'Coordinador de Proyectos', rol: 'coordinador', disciplina: 'HV' } },
  'admin@refri.test':   { id: '22222222-2222-4222-8222-222222222222', perfil: { perfil_id: 'p2', nombre: 'Andrés Admin', cargo: null, rol: 'admin', disciplina: null } },
  'ing@refri.test':     { id: '33333333-3333-4333-8333-333333333333', perfil: { perfil_id: 'p3', nombre: 'Luis Ingeniero', cargo: 'Ingeniero de Proyectos', rol: 'ingeniero', disciplina: 'AU' } },
  'nuevo@refri.test':   { id: '44444444-4444-4444-8444-444444444444', perfil: { perfil_id: 'p4', nombre: 'nuevo', cargo: null, rol: null, disciplina: null } },
  'huerfano@refri.test':{ id: '55555555-5555-4555-8555-555555555555', perfil: null },
};
const PERSONAL = [
  { id: 'p1', nombre: 'Juan Escalante', cargo: 'Coordinador de Proyectos', rol: 'coordinador', correo: 'juan.escalante@refriamerica.com', telefono: null, disciplina: 'HV', numero_civ: '000000', activo: true, auth_id: 'x' },
  { id: 'p3', nombre: 'Luis Ingeniero', cargo: 'Ingeniero de Proyectos', rol: 'ingeniero', correo: 'luis@refriamerica.com', telefono: null, disciplina: 'AU', numero_civ: null, activo: true, auth_id: null },
  { id: 'p5', nombre: 'Josehil Castillo', cargo: 'Ing. de Control de Gestión y Procedimientos', rol: 'control_gestion', correo: null, telefono: null, disciplina: null, numero_civ: null, activo: true, auth_id: null },
  { id: 'p6', nombre: 'Ficha automática', cargo: null, rol: null, correo: 'vieja@refriamerica.com', telefono: null, disciplina: null, numero_civ: null, activo: false, auth_id: null },
];
const AVISOS = [
  { id: 3, tipo: 'prueba', titulo: 'Requerimiento asignado', cuerpo: 'PRY-26-0001 · Rest. La Esquina', enlace: null, leida_en: null, creado_en: '2026-10-21T15:10:00Z' },
  { id: 2, tipo: 'prueba', titulo: 'Documento para revisión', cuerpo: 'PRY-26-0001-HV-MC-001 Rev. A', enlace: null, leida_en: null, creado_en: '2026-10-21T14:00:00Z' },
  { id: 1, tipo: 'prueba', titulo: 'Bienvenido al sistema', cuerpo: null, enlace: null, leida_en: '2026-10-20T12:00:00Z', creado_en: '2026-10-20T11:00:00Z' },
];
const llamadas = [];

function sesionPara(correo) {
  const u = USUARIOS[correo];
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const token = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: u.id, email: correo, role: 'authenticated', aud: 'authenticated', exp, iat: exp - 3600 })}.firma`;
  return { access_token: token, token_type: 'bearer', expires_in: 3600, expires_at: exp, refresh_token: 'r-' + u.id,
           user: { id: u.id, aud: 'authenticated', role: 'authenticated', email: correo, app_metadata: {}, user_metadata: {}, created_at: '2026-10-21T00:00:00Z' } };
}
function correoDelToken(h) {
  const t = (h.authorization || '').replace('Bearer ', '');
  try { return JSON.parse(Buffer.from(t.split('.')[1], 'base64url').toString()).email; } catch { return null; }
}

async function simular(route) {
  const req = route.request(); const u = new URL(req.url()); const h = req.headers();
  const json = (status, cuerpo, extra = {}) => route.fulfill({ status, contentType: 'application/json', headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', ...extra }, body: cuerpo === undefined ? '' : JSON.stringify(cuerpo) });
  if (req.method() === 'OPTIONS') return route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
  const correo = correoDelToken(h);
  llamadas.push({ m: req.method(), p: u.pathname, q: u.search, cuerpo: req.postData(), correo });

  if (u.pathname === '/auth/v1/token') {
    const b = JSON.parse(req.postData() || '{}');
    if (USUARIOS[b.email] && b.password === 'Clave-correcta1') return json(200, sesionPara(b.email));
    return json(400, { code: 400, error_code: 'invalid_credentials', msg: 'Invalid login credentials' });
  }
  if (u.pathname === '/auth/v1/user') return json(200, sesionPara(correo).user);
  if (u.pathname === '/auth/v1/logout') return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*' } });
  if (u.pathname === '/rest/v1/rpc/rpc_mi_sesion') {
    const p = USUARIOS[correo]?.perfil;
    if (!p) return json(400, { code: 'P0001', message: 'Su cuenta no está vinculada a una ficha de personal. Avise a la Coordinación de Proyectos.' });
    return json(200, { ...p, modo: 'prueba', version_esquema: '0.1', zona_horaria: 'America/Caracas' });
  }
  if (u.pathname === '/rest/v1/notificaciones') {
    if (req.method() === 'HEAD') return json(200, undefined, { 'content-range': `*/${AVISOS.filter((a) => !a.leida_en).length}` });
    return json(200, AVISOS);
  }
  if (u.pathname === '/rest/v1/perfiles') return json(200, PERSONAL);
  if (u.pathname === '/rest/v1/rpc/rpc_personal_guardar') {
    const b = JSON.parse(req.postData());
    if (USUARIOS[correo]?.perfil?.rol === 'coordinador' && b.p_rol === 'admin') return json(400, { code: 'P0001', message: 'Solo un administrador puede otorgar o retirar el rol de administrador.' });
    return json(200, 'p-nuevo');
  }
  if (u.pathname === '/rest/v1/rpc/rpc_marcar_leida') { AVISOS.find((a) => a.id === JSON.parse(req.postData()).p_id).leida_en = new Date().toISOString(); return json(200, null); }
  return json(404, { message: 'no simulado: ' + u.pathname });
}

// ---------------------------------------------------------------- utilidades de prueba
const navegador = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });
let fallas = 0, total = 0;
const errores = [];
async function caso(nombre, fn) {
  total++;
  try { await fn(); console.log('✓ ' + nombre); }
  catch (e) { fallas++; console.log('✗ ' + nombre + '\n    ' + e.message.split('\n')[0]); }
}
function afirmar(c, m) { if (!c) throw new Error(m); }
async function pagina({ ancho = 390, alto = 844, oscuro = false } = {}) {
  const ctx = await navegador.newContext({ viewport: { width: ancho, height: alto }, colorScheme: oscuro ? 'dark' : 'light', serviceWorkers: 'block', locale: 'es-VE', timezoneId: 'America/Caracas' });
  const p = await ctx.newPage();
  p.on('console', (m) => { if (m.type() === 'error') errores.push(m.text()); });
  p.on('pageerror', (e) => errores.push(e.message));
  await p.route(SUPA + '/**', simular);
  await p.goto(URL_APP);
  return p;
}
async function entrar(p, correo, clave = 'Clave-correcta1') {
  await p.fill('#correo', correo); await p.fill('#clave', clave); await p.click('#f-login button[type=submit]');
}
async function captura(p, nombre) { if (CAPTURAS) await p.screenshot({ path: path.join(CAPTURAS, nombre + '.png'), fullPage: true }); }
const sinDesborde = async (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);

// ---------------------------------------------------------------- casos
await caso('1 · contraseña incorrecta muestra un mensaje en castellano', async () => {
  const p = await pagina();
  await captura(p, '01_login_telefono');
  await entrar(p, 'coord@refri.test', 'mala');
  await p.waitForSelector('.aviso-error');
  afirmar((await p.textContent('.aviso-error')).includes('Correo o contraseña incorrectos'), 'mensaje inesperado');
  await p.context().close();
});

await caso('2 · coordinador en teléfono: inicio, menú con Personal y contador de avisos', async () => {
  const p = await pagina();
  await entrar(p, 'coord@refri.test');
  await p.waitForSelector('h1:has-text("Hola, Juan")');
  afirmar(await p.isVisible('.pestanas'), 'no se ven las pestañas inferiores');
  afirmar(!(await p.isVisible('.lateral')), 'el menú lateral no debe verse en teléfono');
  afirmar(await p.isVisible('.pestanas [data-ruta="personal"]'), 'falta Personal para el coordinador');
  await p.waitForSelector('#contador:not([hidden])');
  afirmar((await p.textContent('#contador')) === '2', 'el contador no muestra 2 avisos sin leer');
  afirmar(await p.isVisible('.franja-modo'), 'no se ve la franja de modo prueba');
  afirmar(await sinDesborde(p), 'la página se desborda horizontalmente a 390 px');
  await captura(p, '02_inicio_telefono');
  // Personal
  await p.click('.pestanas [data-ruta="personal"]');
  await p.waitForSelector('#l-personal li .nombre');
  afirmar((await p.$$('#l-personal > li')).length === 3, 'deben listarse 3 activos');
  await captura(p, '03_personal_telefono');
  await p.fill('#f-buscar', 'josehil');
  afirmar((await p.$$('#l-personal > li')).length === 1, 'la búsqueda no filtra');
  await p.fill('#f-buscar', '');
  // Alta
  await p.click('#b-nueva');
  await p.waitForSelector('dialog[open]');
  afirmar(!(await p.$('#p-rol option[value="admin"]')), 'el coordinador no debe ver la opción Administrador');
  await p.click('#p-guardar');
  afirmar((await p.textContent('dialog .aviso-error')).includes('nombre es obligatorio'), 'no valida el nombre');
  await p.fill('#p-nombre', 'Pedro Proyectista'); await p.fill('#p-cargo', 'Ingeniero de Proyectos');
  await p.selectOption('#p-rol', 'ingeniero'); await p.selectOption('#p-disc', 'AU');
  await p.fill('#p-correo', 'pedro@refriamerica.com'); await p.fill('#p-civ', '123456');
  await captura(p, '04_alta_persona_telefono');
  await p.click('#p-guardar');
  await p.waitForSelector('.toast');
  const alta = llamadas.findLast((l) => l.p.endsWith('rpc_personal_guardar'));
  const cuerpo = JSON.parse(alta.cuerpo);
  afirmar(cuerpo.p_nombre === 'Pedro Proyectista' && cuerpo.p_rol === 'ingeniero' && cuerpo.p_disciplina === 'AU' && cuerpo.p_id === null, 'la llamada de alta no lleva los datos correctos');
  // Avisos
  await p.click('#b-campana');
  await p.waitForSelector('.aviso-item.no-leido');
  await captura(p, '05_avisos_telefono');
  await p.click('[data-leer="3"]');
  await p.waitForFunction(() => document.querySelector('#contador')?.textContent === '1');
  // Mi cuenta y salir
  await p.click('.pestanas [data-ruta="cuenta"]');
  await captura(p, '06_cuenta_telefono');
  await p.click('#b-salir');
  await p.waitForSelector('#f-login');
  await p.context().close();
});

await caso('3 · administrador en computadora, modo oscuro: menú lateral y opción Administrador', async () => {
  const p = await pagina({ ancho: 1280, alto: 800, oscuro: true });
  await captura(p, '07_login_computadora_oscuro');
  await entrar(p, 'admin@refri.test');
  await p.waitForSelector('h1:has-text("Hola, Andrés")');
  afirmar(await p.isVisible('.lateral'), 'no se ve el menú lateral');
  afirmar(!(await p.isVisible('.pestanas')), 'las pestañas inferiores no deben verse en computadora');
  await captura(p, '08_inicio_computadora_oscuro');
  await p.click('.lateral [data-ruta="personal"]');
  await p.waitForSelector('#l-personal li .nombre');
  await p.click('[data-editar="p3"]');
  await p.waitForSelector('dialog[open]');
  afirmar(!!(await p.$('#p-rol option[value="admin"]')), 'el administrador debe poder otorgar Administrador');
  await captura(p, '09_editar_computadora_oscuro');
  await p.click('#p-retirar');
  afirmar(await p.isVisible('#p-motivo'), 'retirar debe pedir el motivo');
  await p.context().close();
});

await caso('4 · ingeniero: sin módulo Personal', async () => {
  const p = await pagina();
  await entrar(p, 'ing@refri.test');
  await p.waitForSelector('h1:has-text("Hola, Luis")');
  afirmar(!(await p.$('[data-ruta="personal"]')), 'un ingeniero no debe ver Personal');
  await p.goto(URL_APP + '#/personal'); await p.reload();
  await p.waitForSelector('h1');
  afirmar((await p.textContent('h1')).startsWith('Hola'), 'la dirección #/personal no debe abrir Personal a un ingeniero');
  await p.context().close();
});

await caso('5 · cuenta sin rol: aviso claro y sin módulos', async () => {
  const p = await pagina();
  await entrar(p, 'nuevo@refri.test');
  await p.waitForSelector('.aviso-alerta');
  afirmar((await p.textContent('.aviso-alerta')).includes('todavía no tiene un rol'), 'falta el aviso de rol');
  afirmar(!(await p.$('[data-ruta="avisos"]')) && !(await p.$('#b-campana')), 'sin rol no debe haber avisos');
  await captura(p, '10_sin_rol_telefono');
  await p.context().close();
});

await caso('6 · cuenta sin ficha: vuelve al inicio de sesión con el motivo', async () => {
  const p = await pagina();
  await entrar(p, 'huerfano@refri.test');
  await p.waitForSelector('#f-login');
  await p.waitForSelector('#msj .aviso');
  afirmar((await p.textContent('#msj')).includes('no está vinculada'), 'no muestra el motivo');
  await p.context().close();
});

await caso('7 · recuperar contraseña: no revela si el correo existe', async () => {
  const p = await pagina();
  await p.route(SUPA + '/auth/v1/recover**', (r) => r.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*' }, contentType: 'application/json', body: '{}' }));
  await p.click('#b-olvido');
  await p.fill('#correo', 'cualquiera@refriamerica.com');
  await p.click('#f-rec button');
  await p.waitForSelector('.aviso-ok');
  afirmar((await p.textContent('.aviso-ok')).includes('Si el correo tiene una cuenta'), 'mensaje inesperado');
  await p.context().close();
});

await caso('8 · enlace de invitación: pide definir contraseña', async () => {
  const p = await pagina();
  // Simula volver del correo de invitación con la sesión en la dirección
  const s = sesionPara('ing@refri.test');
  await p.goto(`${URL_APP}#access_token=${s.access_token}&expires_in=3600&expires_at=${s.expires_at}&refresh_token=${s.refresh_token}&token_type=bearer&type=invite`);
  await p.reload();   // el enlace del correo abre una carga nueva de la página
  await p.waitForSelector('#f-clave');
  await p.fill('#c1', 'corta'); await p.fill('#c2', 'corta'); await p.click('#f-clave button');
  afirmar((await p.textContent('#msj')).includes('al menos 8'), 'no valida el largo');
  await captura(p, '11_definir_clave');
  await p.context().close();
});

await navegador.close(); servidor.close();
const graves = errores.filter((e) => !/404|Failed to load resource/.test(e));
if (graves.length) { console.log('\nErrores de consola:\n  ' + [...new Set(graves)].join('\n  ')); fallas++; }
console.log(`\nPruebas de la aplicación: ${total - Math.min(fallas, total)} de ${total} correctas${graves.length ? ' · con errores de consola' : ''}.`);
process.exit(fallas ? 1 : 0);
