// =============================================================================
// Prueba de la aplicación v0.3 (Clientes y Requerimientos) con Supabase SIMULADO.
// Sirve app/ en localhost y responde las llamadas a Supabase desde aquí, para probar la
// interfaz por rol sin tocar la base real.
//
// Uso:  node pruebas/app_v0.3.mjs [carpeta_capturas]
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
// Base en memoria con las reglas esenciales de SQL 01 (permisos, transiciones, motivo).
// No sustituye a pruebas/01_clientes_y_requerimientos.sql: aquí se prueba la interfaz.
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const USUARIOS = {
  'coord@refri.test':  { id: 'a1111111-1111-4111-8111-111111111111', perfil: { perfil_id: 'p1', nombre: 'Juan Escalante', cargo: 'Coordinador de Proyectos', rol: 'coordinador', disciplina: 'HV' } },
  'ing@refri.test':    { id: 'a3333333-3333-4333-8333-333333333333', perfil: { perfil_id: 'p3', nombre: 'Luis Ingeniero', cargo: 'Ingeniero de Proyectos', rol: 'ingeniero', disciplina: 'AU' } },
  'ventas@refri.test': { id: 'a7777777-7777-4777-8777-777777777777', perfil: { perfil_id: 'p7', nombre: 'María Ventas', cargo: 'Ejecutiva de Ventas', rol: 'ventas', disciplina: null } },
};
const PERFILES = [
  { id: 'p1', nombre: 'Juan Escalante', rol: 'coordinador', disciplina: 'HV', activo: true, auth_id: 'x' },
  { id: 'p3', nombre: 'Luis Ingeniero', rol: 'ingeniero', disciplina: 'AU', activo: true, auth_id: 'x' },
  { id: 'p7', nombre: 'María Ventas', rol: 'ventas', disciplina: null, activo: true, auth_id: 'x' },
  { id: 'p8', nombre: 'Pedro Vendedor', rol: 'ventas', disciplina: null, activo: true, auth_id: null },
];
const CLIENTES = [
  { id: 'c1', codigo: 'CLI-0001', razon_social: 'Inversiones La Esquina, C.A.', nombre_comercial: 'Rest. La Esquina', rif: 'J-12345678-9', tipo: 'privado',
    direccion_fiscal: 'Av. Principal, Caracas', contacto_nombre: 'Ana Pérez', contacto_cargo: 'Gerente', contacto_telefono: '0412-0000000', contacto_correo: 'ana@esquina.test', activo: true },
];
const base = (o) => ({ canal: null, contacto_nombre: null, contacto_cargo: null, contacto_telefono: null, contacto_correo: null, tipo_edificacion: null, area_m2: null, niveles: null,
  contacto_sitio: null, sistemas: [], info_recibida: [], requiere_levantamiento: null, fecha_requerida: null, prioridad: 'normal', presupuesto_estimado_usd: null,
  modalidad: null, ingeniero_id: null, disciplinas: [], fecha_compromiso: null, observaciones: null, motivo_estado: null, es_prueba: true, ...o });
const REQS = [
  base({ id: 'r1', codigo: 'PRB-26-0001', cliente_id: 'c1', vendedor_id: 'p7', obra_nombre: 'Restaurante La Esquina — salón principal', direccion: 'Av. Principal de Las Mercedes',
    estado_geo: 'Miranda', ciudad: 'Caracas', tipo_solicitud: 'sistema_nuevo', sistemas: ['expansion_directa', 'ventilacion_extraccion'], descripcion: 'Climatización del salón y extracción de cocina.',
    estado: 'enviado_ventas', modalidad: 'B', ingeniero_id: 'p3', disciplinas: ['HV'], fecha_compromiso: '2026-10-30', prioridad: 'alta', registrado_en: '2026-10-20T13:00:00Z' }),
  base({ id: 'r2', codigo: 'PRB-26-0002', cliente_id: 'c1', vendedor_id: 'p8', obra_nombre: 'Depósito Guarenas', direccion: 'Zona industrial', estado_geo: 'Miranda', ciudad: 'Guarenas',
    tipo_solicitud: 'diagnostico', descripcion: 'Diagnóstico de extracción.', estado: 'registrado', registrado_en: '2026-10-21T13:00:00Z' }),
];
const HIST = [
  { requerimiento_id: 'r1', estado_antes: null, estado_nuevo: 'registrado', motivo: null, en: '2026-10-20T13:00:00Z', perfil_id: 'p7' },
  { requerimiento_id: 'r1', estado_antes: 'registrado', estado_nuevo: 'asignado', motivo: null, en: '2026-10-20T14:00:00Z', perfil_id: 'p1' },
  { requerimiento_id: 'r1', estado_antes: 'asignado', estado_nuevo: 'en_ingenieria', motivo: null, en: '2026-10-21T09:00:00Z', perfil_id: 'p3' },
  { requerimiento_id: 'r1', estado_antes: 'en_ingenieria', estado_nuevo: 'enviado_ventas', motivo: 'Memoria y cómputos entregados.', en: '2026-10-22T10:00:00Z', perfil_id: 'p3' },
  { requerimiento_id: 'r2', estado_antes: null, estado_nuevo: 'registrado', motivo: null, en: '2026-10-21T13:00:00Z', perfil_id: 'p1' },
];
const AVISOS = [
  { id: 9, tipo: 'requerimiento', titulo: 'Requerimiento enviado a Ventas', cuerpo: 'PRB-26-0001 · Restaurante La Esquina', enlace: '#/requerimientos/r1', leida_en: null, creado_en: '2026-10-22T10:00:00Z' },
];
const llamadas = [];
let correlativo = 2, nCli = 1;
const TRANS = { asignado: ['en_levantamiento', 'en_ingenieria'], en_levantamiento: ['en_ingenieria'], en_ingenieria: ['enviado_ventas'],
  enviado_ventas: ['aprobado', 'en_espera', 'rechazado'], en_espera: ['enviado_ventas', 'aprobado', 'rechazado'], aprobado: ['cerrado'], rechazado: ['cerrado'] };

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
// Filtros PostgREST mínimos: eq., in.()
function filtrar(filas, u) {
  for (const [k, v] of u.searchParams) {
    if (['select', 'order', 'limit', 'offset'].includes(k)) continue;
    if (v.startsWith('eq.')) { const x = v.slice(3); filas = filas.filter((f) => String(f[k]) === x); }
    else if (v.startsWith('in.(')) { const xs = v.slice(4, -1).split(','); filas = filas.filter((f) => xs.includes(String(f[k]))); }
  }
  return filas;
}
const nombre = (id) => { const p = PERFILES.find((x) => x.id === id); return p ? { nombre: p.nombre } : null; };
const conEmbebidos = (r) => ({ ...r, cliente: (({ codigo, razon_social, rif }) => ({ codigo, razon_social, rif }))(CLIENTES.find((c) => c.id === r.cliente_id)),
  vendedor: nombre(r.vendedor_id), ingeniero: nombre(r.ingeniero_id) });
const visibles = (yo) => REQS.filter((r) => ['coordinador', 'admin', 'gerente', 'control_gestion'].includes(yo.rol) || r.vendedor_id === yo.perfil_id || r.ingeniero_id === yo.perfil_id);
const errorP = (m) => ({ code: 'P0001', message: m });

async function simular(route) {
  const req = route.request(); const u = new URL(req.url()); const h = req.headers();
  const json = (status, cuerpo, extra = {}) => route.fulfill({ status, contentType: 'application/json', headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', ...extra }, body: cuerpo === undefined ? '' : JSON.stringify(cuerpo) });
  if (req.method() === 'OPTIONS') return route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
  const correo = correoDelToken(h); const yo = USUARIOS[correo]?.perfil;
  const cuerpo = req.postData() ? JSON.parse(req.postData()) : null;
  llamadas.push({ m: req.method(), p: u.pathname, q: u.search, cuerpo, correo });
  const lista = (filas) => (h.accept || '').includes('pgrst.object') ? (filas.length === 1 ? json(200, filas[0]) : json(406, { code: 'PGRST116', message: 'no rows' })) : json(200, filas);

  if (u.pathname === '/auth/v1/token') {
    if (USUARIOS[cuerpo.email] && cuerpo.password === 'Clave-correcta1') return json(200, sesionPara(cuerpo.email));
    return json(400, { code: 400, error_code: 'invalid_credentials', msg: 'Invalid login credentials' });
  }
  if (u.pathname === '/auth/v1/user') return json(200, sesionPara(correo).user);
  if (u.pathname === '/auth/v1/logout') return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*' } });
  if (u.pathname === '/rest/v1/rpc/rpc_mi_sesion') return json(200, { ...yo, modo: 'prueba', version_esquema: '0.2', zona_horaria: 'America/Caracas' });
  if (u.pathname === '/rest/v1/notificaciones') {
    if (req.method() === 'HEAD') return json(200, undefined, { 'content-range': `*/${AVISOS.filter((a) => !a.leida_en).length}` });
    return json(200, AVISOS);
  }
  if (u.pathname === '/rest/v1/rpc/rpc_marcar_leida') { const a = AVISOS.find((x) => x.id === cuerpo.p_id); if (a) a.leida_en = new Date().toISOString(); return json(200, null); }
  if (u.pathname === '/rest/v1/perfiles') return lista(filtrar(PERFILES, u));
  if (u.pathname === '/rest/v1/clientes') return lista(filtrar(CLIENTES, u));
  if (u.pathname === '/rest/v1/requerimientos') return lista(filtrar(visibles(yo), u).map(conEmbebidos));
  if (u.pathname === '/rest/v1/requerimiento_estados') {
    const ids = new Set(visibles(yo).map((r) => r.id));
    return lista(filtrar(HIST.filter((x) => ids.has(x.requerimiento_id)), u).map((x) => ({ ...x, perfil: nombre(x.perfil_id) })));
  }
  if (u.pathname === '/rest/v1/rpc/rpc_cliente_guardar') {
    if (!['coordinador', 'ventas'].includes(yo.rol)) return json(400, errorP('No tiene permiso para registrar clientes.'));
    const p = cuerpo.p;
    if (CLIENTES.some((c) => c.rif && c.rif === p.rif && c.id !== cuerpo.p_id)) return json(400, errorP('Ya existe un cliente con ese RIF.'));
    if (cuerpo.p_id) { Object.assign(CLIENTES.find((c) => c.id === cuerpo.p_id), p); return json(200, { id: cuerpo.p_id, codigo: CLIENTES.find((c) => c.id === cuerpo.p_id).codigo }); }
    const c = { id: 'c' + (++nCli), codigo: 'CLI-' + String(nCli).padStart(4, '0'), activo: true, ...p }; CLIENTES.push(c);
    return json(200, { id: c.id, codigo: c.codigo });
  }
  if (u.pathname === '/rest/v1/rpc/rpc_requerimiento_registrar') {
    const p = cuerpo.p;
    const vend = yo.rol === 'ventas' ? yo.perfil_id : p.vendedor_id;
    if (!vend) return json(400, errorP('Indique el vendedor responsable.'));
    const r = base({ ...p, id: 'r' + (++correlativo), codigo: 'PRB-26-' + String(correlativo).padStart(4, '0'), vendedor_id: vend, estado: 'registrado', registrado_en: new Date().toISOString(),
      area_m2: p.area_m2 ? Number(p.area_m2) : null, niveles: p.niveles ? Number(p.niveles) : null, presupuesto_estimado_usd: p.presupuesto_estimado_usd === '' ? null : Number(p.presupuesto_estimado_usd),
      requiere_levantamiento: p.requiere_levantamiento === null ? null : p.requiere_levantamiento === 'true', canal: p.canal || null, fecha_requerida: p.fecha_requerida || null });
    REQS.push(r); HIST.push({ requerimiento_id: r.id, estado_antes: null, estado_nuevo: 'registrado', motivo: null, en: r.registrado_en, perfil_id: yo.perfil_id });
    return json(200, { id: r.id, codigo: r.codigo });
  }
  if (u.pathname === '/rest/v1/rpc/rpc_requerimiento_asignar') {
    if (yo.rol !== 'coordinador') return json(400, errorP('Solo la Coordinación de Proyectos asigna requerimientos.'));
    const r = REQS.find((x) => x.id === cuerpo.p_id);
    Object.assign(r, { modalidad: cuerpo.p_modalidad, ingeniero_id: cuerpo.p_ingeniero, disciplinas: cuerpo.p_disciplinas, fecha_compromiso: cuerpo.p_fecha_compromiso, observaciones: cuerpo.p_observaciones });
    if (r.estado === 'registrado') { HIST.push({ requerimiento_id: r.id, estado_antes: 'registrado', estado_nuevo: 'asignado', motivo: null, en: new Date().toISOString(), perfil_id: yo.perfil_id }); r.estado = 'asignado'; }
    return json(200, null);
  }
  if (u.pathname === '/rest/v1/rpc/rpc_requerimiento_estado') {
    const r = REQS.find((x) => x.id === cuerpo.p_id); const n = cuerpo.p_nuevo;
    const ok = (TRANS[r.estado] || []).includes(n) || (n === 'cerrado' && r.modalidad === 'A' && ['asignado', 'en_levantamiento', 'en_ingenieria'].includes(r.estado));
    if (!ok) return json(400, errorP('No se puede pasar de ese estado al solicitado.'));
    if (['rechazado', 'en_espera'].includes(n) && !(cuerpo.p_motivo || '').trim()) return json(400, errorP('Indique el motivo.'));
    HIST.push({ requerimiento_id: r.id, estado_antes: r.estado, estado_nuevo: n, motivo: cuerpo.p_motivo, en: new Date().toISOString(), perfil_id: yo.perfil_id });
    r.estado = n; r.motivo_estado = cuerpo.p_motivo; return json(200, null);
  }
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
const ultima = (fin) => llamadas.findLast((l) => l.p.endsWith(fin));

await caso('1 · coordinador en teléfono: resumen en Inicio, pestañas ≤ 5, lista y filtro', async () => {
  const p = await pagina();
  await entrar(p, 'coord@refri.test');
  await p.waitForSelector('#resumen-req .contadores');
  const cifras = await p.$$eval('#resumen-req .cifra', (xs) => xs.map((x) => x.textContent));
  afirmar(JSON.stringify(cifras) === '["1","0","1","2"]', 'contadores inesperados: ' + cifras);
  afirmar((await p.$$('.pestanas a')).length <= 5, 'más de 5 pestañas en teléfono');
  afirmar(!(await p.$('.pestanas [data-ruta="clientes"]')), 'Clientes no debe ocupar una pestaña del teléfono');
  await captura(p, '20_inicio_resumen_telefono');
  await p.click('#resumen-req [data-filtro="registrado"]');
  await p.waitForSelector('#l-req .fila-req');
  afirmar((await p.$$('#l-req .fila-req')).length === 1, 'el filtro Sin asignar debe dejar 1');
  await p.selectOption('#f-grupo', 'todos');
  afirmar((await p.$$('#l-req .fila-req')).length === 2, 'Todos debe mostrar 2');
  await p.fill('#f-buscar', 'guarenas');
  afirmar((await p.$$('#l-req .fila-req')).length === 1, 'la búsqueda no filtra');
  await p.fill('#f-buscar', '');
  afirmar(await sinDesborde(p), 'la lista se desborda a 390 px');
  await captura(p, '21_lista_requerimientos_telefono');
  await p.context().close();
});

await caso('2 · coordinador: cliente nuevo (valida RIF), registro de requerimiento y asignación', async () => {
  const p = await pagina();
  await entrar(p, 'coord@refri.test');
  await p.click('.pestanas [data-ruta="requerimientos"]');
  await p.click('#b-nuevo-req');
  await p.waitForSelector('#f-req');
  await p.waitForFunction(() => document.querySelectorAll('#r-vendedor option').length === 3);
  afirmar((await p.textContent('#r-vendedor')).includes('Pedro Vendedor (sin cuenta)'), 'debe ofrecer vendedores sin cuenta');
  await p.click('#b-registrar');
  const falta = await p.textContent('#msj');
  afirmar(falta.includes('vendedor') && falta.includes('cliente') && falta.includes('descripción del alcance'), 'no lista lo que falta: ' + falta);
  afirmar(!llamadas.some((l) => l.p.endsWith('rpc_requerimiento_registrar')), 'no debe llamar a la base con la ficha incompleta');
  // cliente nuevo desde la ficha
  await p.click('#b-cliente-nuevo'); await p.waitForSelector('dialog[open]');
  await p.fill('#c-razon', 'Clínica Santa Ana, C.A.'); await p.fill('#c-rif', 'j123');
  await p.click('dialog [data-aceptar]');
  afirmar((await p.textContent('dialog .aviso-error')).includes('J-12345678-9'), 'no valida el formato del RIF');
  await p.fill('#c-rif', 'j-30111222-3'); await p.selectOption('#c-tipo', 'privado');
  await captura(p, '22_cliente_nuevo_telefono');
  await p.click('dialog [data-aceptar]');
  await p.waitForSelector('dialog[open]', { state: 'detached' });
  afirmar(ultima('rpc_cliente_guardar').cuerpo.p.rif === 'J-30111222-3', 'el RIF no se normaliza a mayúsculas');
  await p.waitForFunction(() => document.querySelector('#r-cliente').selectedOptions[0]?.textContent.includes('Clínica Santa Ana'));
  // ficha
  await p.selectOption('#r-cliente', 'c1');
  afirmar((await p.inputValue('#r-cnombre')) === 'Ana Pérez', 'no propone el contacto del cliente');
  await p.fill('#r-cnombre', 'Dr. Ramón Ruiz'); await p.selectOption('#r-cliente', 'c2');
  afirmar((await p.inputValue('#r-cnombre')) === 'Dr. Ramón Ruiz', 'no debe pisar un contacto ya escrito');
  await p.selectOption('#r-vendedor', 'p8'); await p.selectOption('#r-canal', 'whatsapp');
  await p.fill('#r-obra', 'Clínica Santa Ana — quirófanos'); await p.fill('#r-dir', 'Calle 3, Los Teques');
  await p.selectOption('#r-edo', 'Miranda'); await p.fill('#r-ciudad', 'Los Teques');
  await p.selectOption('#r-edif', 'salud'); await p.fill('#r-area', '1.250,5'); await p.fill('#r-niveles', '2');
  await p.selectOption('#r-tsol', 'adecuacion');
  await p.check('input[name="sistemas"][value="uma"]'); await p.check('input[name="sistemas"][value="presurizacion"]');
  await p.fill('#r-desc', 'Adecuación de UMA y presurización de 3 quirófanos.');
  await p.check('input[name="info"][value="planos"]'); await p.selectOption('#r-lev', 'true');
  await p.fill('#r-ppto', 'abc');
  await p.click('#b-registrar');
  afirmar((await p.textContent('#msj')).includes('presupuesto'), 'no valida el presupuesto');
  await p.fill('#r-ppto', '45000'); await p.selectOption('#r-prio', 'urgente');
  afirmar(await sinDesborde(p), 'la ficha se desborda a 390 px');
  await captura(p, '23_ficha_nueva_telefono');
  await p.click('#b-registrar');
  await p.waitForSelector('#b-asignar');
  const f = ultima('rpc_requerimiento_registrar').cuerpo.p;
  afirmar(f.vendedor_id === 'p8' && f.area_m2 === '1250.5' && f.niveles === '2' && JSON.stringify(f.sistemas) === '["uma","presurizacion"]'
    && JSON.stringify(f.info_recibida) === '["planos"]' && f.requiere_levantamiento === 'true' && f.estado_geo === 'Miranda', 'la ficha enviada no es la esperada: ' + JSON.stringify(f));
  afirmar((await p.textContent('.codigo')).startsWith('PRB-26-'), 'la ficha no muestra el código');
  afirmar(p.url().endsWith('#/requerimientos/r3'), 'no navega a la ficha del registrado');
  await captura(p, '24_ficha_registrada_telefono');
  // asignación
  await p.click('#b-asignar'); await p.waitForSelector('dialog[open]');
  await p.click('dialog [data-aceptar]');
  afirmar((await p.textContent('dialog .aviso-error')).includes('modalidad'), 'no exige modalidad');
  await p.selectOption('#a-mod', 'B'); await p.selectOption('#a-ing', 'p3'); await p.check('input[name="disc"][value="HV"]');
  await p.fill('#a-fecha', '2026-11-05');
  await captura(p, '25_asignar_telefono');
  await p.click('dialog [data-aceptar]');
  await p.waitForSelector('dialog[open]', { state: 'detached' });
  await p.waitForSelector('.distintivo:has-text("Asignado")');
  const a = ultima('rpc_requerimiento_asignar').cuerpo;
  afirmar(a.p_modalidad === 'B' && a.p_ingeniero === 'p3' && JSON.stringify(a.p_disciplinas) === '["HV"]' && a.p_fecha_compromiso === '2026-11-05', 'asignación incorrecta');
  afirmar(await p.isVisible('[data-estado="en_ingenieria"]') && await p.isVisible('#b-asignar'), 'tras asignar debe ofrecer avanzar y reasignar');
  afirmar((await p.$$('.historial li')).length === 2, 'el historial debe tener 2 movimientos');
  await p.context().close();
});

await caso('3 · ventas: ficha con su nombre fijo; decide sobre lo enviado; rechazo exige motivo', async () => {
  const p = await pagina();
  await entrar(p, 'ventas@refri.test');
  await p.waitForSelector('h1:has-text("Hola, María")');
  await p.click('.pestanas [data-ruta="requerimientos"]');
  await p.waitForSelector('#l-req .fila-req');
  afirmar((await p.$$('#l-req .fila-req')).length === 1, 'ventas solo debe ver sus requerimientos');
  await p.click('#b-nuevo-req'); await p.waitForSelector('#f-req');
  afirmar(!(await p.$('#r-vendedor')), 'ventas no debe elegir vendedor');
  await p.click('#b-volver');
  await p.click('#l-req .fila-req');
  await p.waitForSelector('[data-estado="rechazado"]');
  const botones = await p.$$eval('[data-estado]', (xs) => xs.map((x) => x.dataset.estado));
  afirmar(JSON.stringify(botones) === '["aprobado","en_espera","rechazado"]', 'botones de ventas: ' + botones);
  afirmar(!(await p.$('#b-asignar')), 'ventas no asigna');
  await captura(p, '26_ficha_ventas_telefono');
  await p.click('[data-estado="rechazado"]'); await p.waitForSelector('dialog[open]');
  await p.click('dialog [data-aceptar]');
  afirmar((await p.textContent('dialog .aviso-error')).includes('motivo'), 'el rechazo no exige motivo');
  afirmar(!llamadas.some((l) => l.p.endsWith('rpc_requerimiento_estado')), 'sin motivo no debe llamar a la base');
  await p.fill('#e-motivo', 'El cliente pospuso la inversión para 2027.');
  await captura(p, '27_rechazo_telefono');
  await p.click('dialog [data-aceptar]');
  await p.waitForSelector('.distintivo.error:has-text("Rechazado")');
  afirmar((await p.textContent('main')).includes('pospuso la inversión'), 'no muestra el motivo');
  afirmar(!(await p.$('[data-estado]')), 'tras rechazar, ventas no tiene más acciones (cierra la Coordinación)');
  await p.context().close();
});

await caso('4 · ingeniero: sin registro ni Clientes; solo los estados técnicos', async () => {
  REQS.find((r) => r.id === 'r1').estado = 'en_ingenieria';
  const p = await pagina();
  await entrar(p, 'ing@refri.test');
  await p.click('.pestanas [data-ruta="requerimientos"]');
  await p.waitForSelector('#l-req .fila-req');
  afirmar(!(await p.$('#b-nuevo-req')) && !(await p.$('#b-clientes')), 'el ingeniero no registra ni ve Clientes');
  await p.goto(URL_APP + '#/clientes'); await p.reload(); await p.waitForSelector('h1');
  afirmar((await p.textContent('h1')).startsWith('Hola'), '#/clientes no debe abrir para un ingeniero');
  await p.goto(URL_APP + '#/requerimientos/r1'); await p.reload();
  await p.waitForSelector('[data-estado]');
  const botones = await p.$$eval('[data-estado]', (xs) => xs.map((x) => x.dataset.estado));
  afirmar(JSON.stringify(botones) === '["enviado_ventas"]', 'botones del ingeniero: ' + botones);
  // Con Ventas, la decisión no es del ingeniero
  REQS.find((r) => r.id === 'r1').estado = 'enviado_ventas';
  await p.reload(); await p.waitForSelector('.historial');
  afirmar(!(await p.$('[data-estado]')), 'el ingeniero no debe aprobar ni rechazar');
  await p.context().close();
});

await caso('5 · computadora: Clientes en el menú lateral, edición y aviso que abre la ficha', async () => {
  const p = await pagina({ ancho: 1280, alto: 860 });
  await entrar(p, 'coord@refri.test');
  await p.waitForSelector('.lateral [data-ruta="clientes"]');
  await p.click('.lateral [data-ruta="clientes"]');
  await p.waitForSelector('#l-cli li .nombre');
  await p.fill('#f-buscar', 'j-12345678');
  afirmar((await p.$$('#l-cli > li')).length === 1, 'la búsqueda por RIF no filtra');
  await p.fill('#f-buscar', '');
  await captura(p, '28_clientes_computadora');
  await p.click('[data-editar="c1"]'); await p.waitForSelector('dialog[open]');
  afirmar((await p.inputValue('#c-razon')).startsWith('Inversiones La Esquina'), 'no carga los datos al editar');
  await p.click('dialog [data-cancelar]');
  await p.click('.lateral [data-ruta="avisos"]');
  await p.waitForSelector('[data-abrir]');
  await p.click('[data-abrir]');
  await p.waitForSelector('.historial');
  afirmar(p.url().endsWith('#/requerimientos/r1'), 'el aviso no abre la ficha');
  await captura(p, '29_ficha_computadora');
  const oscuro = await pagina({ ancho: 1280, alto: 860, oscuro: true });
  await entrar(oscuro, 'coord@refri.test');
  await oscuro.waitForSelector('#resumen-req .contadores');
  await oscuro.click('.lateral [data-ruta="requerimientos"]'); await oscuro.waitForSelector('#l-req .fila-req');
  await captura(oscuro, '30_lista_computadora_oscuro');
  await oscuro.context().close();
  await p.context().close();
});

await navegador.close(); servidor.close();
const graves = errores.filter((e) => !/404|Failed to load resource/.test(e));
if (graves.length) { console.log('\nErrores de consola:\n  ' + [...new Set(graves)].join('\n  ')); fallas++; }
console.log(`\nPruebas de la aplicación: ${total - Math.min(fallas, total)} de ${total} correctas${graves.length ? ' · con errores de consola' : ''}.`);
process.exit(fallas ? 1 : 0);
