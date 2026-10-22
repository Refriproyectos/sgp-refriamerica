// =============================================================================
// Prueba de la aplicación v0.4 (Levantamientos, sin señal, informe PDF) con Supabase SIMULADO.
// Sirve app/ en localhost y responde las llamadas a Supabase desde aquí, para probar la
// interfaz por rol sin tocar la base real.
//
// Uso:  node pruebas/app_v0.4.mjs [carpeta_capturas]
// Requiere: npm i playwright  (y un Chromium; ver PLAYWRIGHT_BROWSERS_PATH)
// =============================================================================
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'app');
const CAPTURAS = process.argv[2] || null;
const SUPA = 'https://lwhczkzhsnqawettzzfw.supabase.co';
const TIPOS = { '.json': 'application/json', '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.woff2': 'font/woff2', '.webmanifest': 'application/manifest+json' };

// ---------------------------------------------------------------- servidor local de app/
const servidor = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]); if (p === '/') p = '/index.html';
  const f = path.join(RAIZ, p);
  if (!f.startsWith(RAIZ) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  const csp = fs.readFileSync(path.join(RAIZ, '_headers'), 'utf8').match(/Content-Security-Policy: (.*)/)[1];
  res.writeHead(200, { 'Content-Type': TIPOS[path.extname(f)] || 'application/octet-stream', 'Content-Security-Policy': csp });
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
REQS.push(base({ id: 'r4', codigo: 'PRB-26-0004', cliente_id: 'c1', vendedor_id: 'p7', obra_nombre: 'Clínica Santa Ana — quirófanos', direccion: 'Calle 3',
  estado_geo: 'Miranda', ciudad: 'Los Teques', tipo_solicitud: 'sistema_nuevo', tipo_edificacion: 'salud', sistemas: ['uma', 'presurizacion'],
  descripcion: 'Adecuación de UMA y presurización de 3 quirófanos.', estado: 'asignado', modalidad: 'B', ingeniero_id: 'p3', registrado_en: '2026-10-22T12:00:00Z',
  contacto_nombre: 'Dr. Ramón Ruiz', contacto_telefono: '0412-0000000' }));
const LEVS = [], FOTOS = [], OBJETOS = new Map(), LEV_HIST = [];
const JPEG = fs.readFileSync(process.env.FOTO_PRUEBA);
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
const estado_red = { caida: false };   // simula «sin señal» hacia Supabase con la página abierta
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
  let cuerpo = null; try { cuerpo = req.postData() ? JSON.parse(req.postData()) : null; } catch { cuerpo = null; }
  llamadas.push({ m: req.method(), p: u.pathname, q: u.search, cuerpo, correo });
  if (estado_red.caida && !u.pathname.startsWith('/auth/v1/token')) return route.abort('internetdisconnected');
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
  // ---- Levantamientos
  const visiblesLev = () => { const ids = new Set(visibles(yo).map((r) => r.id)); return LEVS.filter((l) => ids.has(l.requerimiento_id)); };
  const editable = (l) => ['borrador', 'devuelto'].includes(l.estado) && (yo.rol === 'coordinador' || l.responsable_id === yo.perfil_id);
  if (u.pathname === '/rest/v1/levantamientos') {
    return lista(filtrar(visiblesLev(), u).map((l) => ({ ...l, requerimiento: (({ codigo, obra_nombre, ingeniero_id }) => ({ codigo, obra_nombre, ingeniero_id }))(REQS.find((r) => r.id === l.requerimiento_id)),
      responsable: nombre(l.responsable_id), aprobador: nombre(l.aprobado_por) })));
  }
  if (u.pathname === '/rest/v1/levantamiento_fotos') { const ids = new Set(visiblesLev().map((l) => l.id)); return lista(filtrar(FOTOS.filter((f) => ids.has(f.levantamiento_id)), u)); }
  if (u.pathname === '/rest/v1/levantamiento_estados') { const ids = new Set(visiblesLev().map((l) => l.id)); return lista(filtrar(LEV_HIST.filter((h) => ids.has(h.levantamiento_id)), u).map((h) => ({ ...h, perfil: nombre(h.perfil_id) }))); }
  if (u.pathname === '/rest/v1/rpc/rpc_levantamiento_crear') {
    const ya = LEVS.find((l) => l.id === cuerpo.p_id); if (ya) return json(200, { id: ya.id, codigo: ya.codigo, version: ya.version });
    const r = REQS.find((x) => x.id === cuerpo.p_requerimiento);
    if (!(yo.rol === 'coordinador' || r.ingeniero_id === yo.perfil_id)) return json(400, errorP('Solo el ingeniero asignado o la coordinación inician un levantamiento.'));
    const n = LEVS.filter((l) => l.requerimiento_id === r.id).length + 1;
    const l = { id: cuerpo.p_id, requerimiento_id: r.id, numero: n, codigo: `${r.codigo}-GE-IL-${String(n).padStart(3, '0')}`, tipo: cuerpo.p_contenido.tipo, estado: 'borrador',
      responsable_id: r.ingeniero_id, contenido: cuerpo.p_contenido, version: 1, observaciones_revision: null, aprobado_por: null, aprobado_en: null,
      creado_en: new Date().toISOString(), actualizado_en: new Date().toISOString() };
    LEVS.push(l); LEV_HIST.push({ levantamiento_id: l.id, estado_antes: null, estado_nuevo: 'borrador', motivo: null, en: l.creado_en, perfil_id: yo.perfil_id });
    if (r.estado === 'asignado') r.estado = 'en_levantamiento';
    return json(200, { id: l.id, codigo: l.codigo, version: 1 });
  }
  if (u.pathname === '/rest/v1/rpc/rpc_levantamiento_guardar') {
    const l = LEVS.find((x) => x.id === cuerpo.p_id);
    if (!editable(l)) return json(400, errorP('El levantamiento está en revisión: ya no se puede modificar.'));
    if (cuerpo.p_version !== null && cuerpo.p_version !== l.version) return json(400, errorP(`CONFLICTO: el levantamiento se modificó en otro equipo (versión ${l.version} en el servidor, ${cuerpo.p_version} en este equipo).`));
    l.contenido = cuerpo.p_contenido; l.tipo = l.contenido.tipo; l.version += 1; l.actualizado_en = new Date().toISOString(); return json(200, l.version);
  }
  if (u.pathname === '/rest/v1/rpc/rpc_foto_registrar') {
    const p = cuerpo.p; const l = LEVS.find((x) => x.id === p.levantamiento_id); const ruta = `${p.levantamiento_id}/${p.id}.jpg`;
    if (!l || !editable(l)) return json(400, errorP('No puede agregar fotos a este levantamiento.'));
    if (!OBJETOS.has(ruta)) return json(400, errorP('La foto no está en el depósito: súbala antes de registrarla.'));
    const ya = FOTOS.find((f) => f.id === p.id);
    if (ya) Object.assign(ya, { descripcion: p.descripcion || null, referencia: p.referencia, seccion: p.seccion });
    else FOTOS.push({ id: p.id, levantamiento_id: p.levantamiento_id, ruta, seccion: p.seccion, referencia: p.referencia || null, descripcion: p.descripcion || null, tomada_en: p.tomada_en, latitud: p.latitud, longitud: p.longitud });
    return json(200, null);
  }
  if (u.pathname === '/rest/v1/rpc/rpc_foto_eliminar') {
    const i = FOTOS.findIndex((f) => f.id === cuerpo.p_id); if (i < 0) return json(200, null);
    const ruta = FOTOS[i].ruta; FOTOS.splice(i, 1); return json(200, ruta);
  }
  if (u.pathname === '/rest/v1/rpc/rpc_levantamiento_enviar') {
    const l = LEVS.find((x) => x.id === cuerpo.p_id);
    if (!editable(l)) return json(400, errorP('Solo el responsable o la coordinación envían a revisión.'));
    if (!l.contenido.visita?.fecha) return json(400, errorP('Falta la fecha de la visita (paso 1).'));
    if (!(l.contenido.areas || []).length) return json(400, errorP('Registre al menos un área (paso 3).'));
    LEV_HIST.push({ levantamiento_id: l.id, estado_antes: l.estado, estado_nuevo: 'en_revision', motivo: null, en: new Date().toISOString(), perfil_id: yo.perfil_id });
    l.estado = 'en_revision'; l.observaciones_revision = null; return json(200, null);
  }
  if (u.pathname === '/rest/v1/rpc/rpc_levantamiento_revisar') {
    if (yo.rol !== 'coordinador') return json(400, errorP('Solo la coordinación o la gerencia revisan levantamientos.'));
    const l = LEVS.find((x) => x.id === cuerpo.p_id);
    if (!cuerpo.p_aprobar && !(cuerpo.p_observaciones || '').trim()) return json(400, errorP('Indique las observaciones para devolver el levantamiento.'));
    const n = cuerpo.p_aprobar ? 'aprobado' : 'devuelto';
    LEV_HIST.push({ levantamiento_id: l.id, estado_antes: 'en_revision', estado_nuevo: n, motivo: cuerpo.p_observaciones, en: new Date().toISOString(), perfil_id: yo.perfil_id });
    Object.assign(l, { estado: n, observaciones_revision: cuerpo.p_observaciones, aprobado_por: cuerpo.p_aprobar ? yo.perfil_id : null, aprobado_en: cuerpo.p_aprobar ? new Date().toISOString() : null });
    return json(200, null);
  }
  // ---- Depósito de fotos (Supabase Storage)
  const sto = '/storage/v1/object/';
  if (u.pathname.startsWith(sto + 'sign/levantamientos') && req.method() === 'POST') {
    return json(200, cuerpo.paths.map((p) => ({ path: p, signedURL: `/object/sign/levantamientos/${p}?token=t`, error: null })));
  }
  if (u.pathname.startsWith(sto + 'sign/levantamientos/') && req.method() === 'GET') {
    return route.fulfill({ status: 200, contentType: 'image/jpeg', headers: { 'access-control-allow-origin': '*' }, body: JPEG });
  }
  if (u.pathname.startsWith(sto + 'levantamientos/') && req.method() === 'POST') {
    const ruta = decodeURIComponent(u.pathname.slice((sto + 'levantamientos/').length));
    const l = LEVS.find((x) => x.id === ruta.split('/')[0]);
    if (!l || !editable(l)) return json(403, { statusCode: '403', error: 'Unauthorized', message: 'new row violates row-level security policy' });
    OBJETOS.set(ruta, req.postDataBuffer()); return json(200, { Key: 'levantamientos/' + ruta, Id: ruta });
  }
  if (u.pathname === sto + 'levantamientos' && req.method() === 'DELETE') { for (const x of cuerpo.prefixes) OBJETOS.delete(x); return json(200, []); }
  return json(404, { message: 'no simulado: ' + u.pathname });
}

// ---------------------------------------------------------------- utilidades de prueba
const navegador = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });
let fallas = 0, total = 0;
const errores = [];
async function caso(nombre, fn) {
  if (process.env.SOLO && !nombre.startsWith(process.env.SOLO + ' ')) return;
  total++;
  try { await fn(); console.log('✓ ' + nombre); }
  catch (e) { fallas++; console.log('✗ ' + nombre + '\n    ' + e.message.split('\n').filter((x) => /Timeout|waiting for|Error|no |debe|inesperad/.test(x)).slice(0, 3).join('\n    ')); }
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
const FOTO = process.env.FOTO_PRUEBA;
const ultima = (fin) => llamadas.findLast((l) => l.p.endsWith(fin));
const textoPDF = (f) => execFileSync('pdftotext', ['-layout', f, '-']).toString();
const paginasPDF = (f) => Number(/Pages:\s+(\d+)/.exec(execFileSync('pdfinfo', [f]).toString())[1]);
async function irPaso(p, n) { await p.click(`.pasos [data-paso="${n - 1}"]`); await p.waitForSelector(`.pasos [data-paso="${n - 1}"][aria-current="step"]`); }
async function esperarSinc(p) { await p.waitForSelector('#estado-sinc.ok', { timeout: 15000 }); }
let LEV_ID = null;

await caso('1 · ingeniero en sitio SIN señal: inicia, llena por pasos y toma fotos; al volver la señal recibe código y sube todo', async () => {
  const p = await pagina();
  await entrar(p, 'ing@refri.test');
  await p.click('.pestanas [data-ruta="requerimientos"]');
  await p.waitForSelector('#l-req .fila-req');
  afirmar(await p.isVisible('.pestanas [data-ruta="levantamientos"]'), 'el ingeniero debe tener la pestaña Levantamientos');
  await p.click('#l-req .fila-req:has-text("PRB-26-0004")');
  await p.waitForSelector('#b-iniciar-lev');
  // Se va la señal
  await p.context().setOffline(true);
  await p.click('#b-iniciar-lev');
  await p.waitForSelector('.paso-lev');
  afirmar((await p.textContent('.cabecera-modulo .codigo')).includes('Código pendiente'), 'sin señal debe decir «Código pendiente»');
  afirmar((await p.inputValue('[data-c="visita.cliente"]')).startsWith('Inversiones La Esquina'), 'el cliente no vino del requerimiento');
  afirmar(await p.isChecked('input[name="tipo"][value="nueva"]'), 'sistema nuevo debe proponer «Instalación nueva»');
  await p.fill('[data-c="visita.fecha"]', '2026-10-23');
  await p.fill('[data-c="visita.hora_inicio"]', '09:00'); await p.fill('[data-c="visita.hora_fin"]', '11:30');
  await p.fill('[data-c="visita.personal_apoyo"]', 'Téc. José Pérez');
  await captura(p, '40_paso1_sin_senal_telefono');
  await irPaso(p, 2);
  await p.fill('[data-c="antecedentes"]', 'El cliente requiere climatizar tres quirófanos nuevos con presurización positiva.');
  await irPaso(p, 3);
  await p.click('[data-accion="agregar"][data-l="areas"]');
  await p.fill('details[open] [data-c="nombre"]', 'Quirófano 1 · PB');
  await p.fill('details[open] [data-c="uso"]', 'Quirófano');
  await p.fill('details[open] [data-c="largo"]', '6,5'); await p.fill('details[open] [data-c="ancho"]', '5');
  afirmar((await p.textContent('details[open] .valor-calc')).includes('32,5 m²'), 'el área no se calculó: ' + await p.textContent('details[open] .valor-calc'));
  await p.fill('details[open] [data-c="paredes_sol"]', '2'); await p.fill('details[open] [data-c="techos_sol"]', '1');
  await p.check('details[open] input[data-c="orientacion"][value="O"]');
  await p.selectOption('details[open] [data-c="techo_tipo"]', 'losa');
  await p.setInputFiles('details[open] input[type=file][capture]', FOTO);
  await p.waitForSelector('details[open] .foto img');
  await p.fill('details[open] [data-desc]', 'Vista general del quirófano 1'); await p.press('details[open] [data-desc]', 'Tab');
  afirmar((await p.textContent('details[open] .nfoto')).includes('F-01'), 'la foto no se numeró F-01');
  await p.waitForTimeout(600);
  afirmar((await p.textContent('#estado-sinc')).includes('por subir'), 'debe indicar que hay datos por subir: ' + await p.textContent('#estado-sinc'));
  afirmar(await sinDesborde(p), 'el paso 3 desborda a 390 px');
  await captura(p, '41_paso3_area_telefono');
  await irPaso(p, 4);
  afirmar((await p.textContent('.paso-lev')).includes('No aplica en una instalación nueva'), 'el paso 4 debe indicar que no aplica');
  await irPaso(p, 7);
  afirmar((await p.textContent('.paso-lev h2')).includes('Condicionantes del sitio'), 'en instalación nueva el paso 7 es «Condicionantes del sitio»');
  await p.click('[data-accion="agregar"][data-l="hallazgos"]');
  await p.fill('details[open] [data-c="descripcion"]', 'Sin espacio en techo para condensadoras');
  await p.selectOption('details[open] [data-c="severidad"]', 'alta');
  afirmar(!llamadas.some((l) => l.p.endsWith('rpc_levantamiento_crear')), 'sin señal no debe llamar a la base');
  // Vuelve la señal
  await p.context().setOffline(false);
  await p.evaluate(() => window.dispatchEvent(new Event('online')));
  await esperarSinc(p);
  await p.waitForFunction(() => /PRB-26-0004-GE-IL-001/.test(document.querySelector('.cabecera-modulo .codigo')?.textContent || ''), null, { timeout: 8000 });
  const l = LEVS[0]; LEV_ID = l.id;
  afirmar(l && l.codigo === 'PRB-26-0004-GE-IL-001', 'no se registró con código');
  afirmar(l.contenido.areas[0].paredes_sol === '2' && l.contenido.areas[0].nombre === 'Quirófano 1 · PB' && l.contenido.hallazgos.length === 1, 'el contenido subido no es el llenado: ' + JSON.stringify(l.contenido.hallazgos) + ' v' + l.version + ' ' + llamadas.filter((x) => x.p.includes('rpc_lev') || x.p.includes('storage')).map((x) => x.p.split('/').pop() + (x.cuerpo?.p_contenido ? ':h' + (x.cuerpo.p_contenido.hallazgos || []).length : '')).join(' '));
  afirmar(FOTOS.length === 1 && FOTOS[0].descripcion === 'Vista general del quirófano 1' && FOTOS[0].referencia === l.contenido.areas[0].id, 'la foto no se registró con su descripción y área');
  afirmar(OBJETOS.size === 1, 'el archivo de la foto no llegó al depósito');
  afirmar(REQS.find((r) => r.id === 'r4').estado === 'en_levantamiento', 'el requerimiento no pasó a En levantamiento');
  await captura(p, '42_sincronizado_telefono');
  await p.context().close();
});

await caso('2 · abrir la app sin conexión con la sesión guardada: entra y ve su levantamiento', async () => {
  const p = await pagina();
  await entrar(p, 'ing@refri.test');
  await p.waitForSelector('h1:has-text("Hola, Luis")');
  await p.goto(URL_APP + '#/levantamientos/' + LEV_ID); await p.reload();
  await p.waitForSelector('.paso-lev');      // con señal: queda guardado en el equipo
  estado_red.caida = true;
  try {
    await p.reload();
    await p.waitForSelector('.paso-lev', { timeout: 10000 });
    afirmar(!(await p.$('#f-login')), 'sin conexión no debe pedir iniciar sesión');
    afirmar((await p.textContent('.cabecera-modulo .codigo')).includes('PRB-26-0004-GE-IL-001'), 'no muestra el levantamiento guardado');
  } finally { estado_red.caida = false; }
  await p.context().close();
});

await caso('3 · conflicto: el levantamiento cambió en otro equipo; la persona elige qué copia conservar', async () => {
  const p = await pagina();
  await entrar(p, 'ing@refri.test');
  await p.goto(URL_APP + '#/levantamientos/' + LEV_ID); await p.reload();
  await p.waitForSelector('.paso-lev');
  LEVS[0].version += 1; LEVS[0].contenido = { ...LEVS[0].contenido, conclusiones: 'Escrito desde la computadora' };
  await irPaso(p, 8);
  await p.fill('[data-c="analisis"]', 'Se propone UMA con filtración HEPA y presurización positiva.');
  await p.waitForSelector('#b-usar-mia', { timeout: 10000 });
  await captura(p, '43_conflicto_telefono');
  await p.click('#b-usar-mia');
  await p.waitForSelector('#b-usar-mia', { state: 'detached' });
  afirmar(ultima('rpc_levantamiento_guardar').cuerpo.p_version === null, 'conservar la copia local debe sobrescribir explícitamente');
  afirmar(LEVS[0].contenido.analisis.startsWith('Se propone UMA'), 'no se guardó la copia elegida');
  await p.context().close();
});

await caso('4 · enviar a revisión, devolución con observaciones y aprobación (computadora)', async () => {
  const p = await pagina();
  await entrar(p, 'ing@refri.test');
  await p.goto(URL_APP + '#/levantamientos/' + LEV_ID); await p.reload();
  await p.waitForSelector('.paso-lev');
  await irPaso(p, 9);
  await p.waitForSelector('.chequeo');
  await captura(p, '44_revision_telefono');
  await p.click('#b-enviar-lev'); await p.click('dialog [data-aceptar]');
  await p.waitForSelector('.distintivo:has-text("En revisión")');
  afirmar(LEVS[0].estado === 'en_revision', 'no pasó a En revisión');
  await p.context().close();

  const c = await pagina({ ancho: 1280, alto: 860 });
  await entrar(c, 'coord@refri.test');
  await c.waitForSelector('#resumen-lev .contadores');
  await c.click('.lateral [data-ruta="levantamientos"]');
  await c.selectOption('#f-estado-lev', 'en_revision');
  await c.click('#l-lev .fila-req');
  await c.waitForSelector('.paso-lev');
  await irPaso(c, 9);
  await c.waitForSelector('#b-devolver-lev');
  await c.click('#b-devolver-lev'); await c.click('dialog [data-aceptar]');
  afirmar((await c.textContent('dialog .aviso-error')).includes('observaciones'), 'devolver debe exigir observaciones');
  await c.fill('#r-obs', 'Falta la capacidad disponible del tablero (paso 5).');
  await c.click('dialog [data-aceptar]');
  await c.waitForSelector('.distintivo:has-text("Devuelto")');
  await c.context().close();

  const p2 = await pagina();
  await entrar(p2, 'ing@refri.test');
  await p2.goto(URL_APP + '#/levantamientos/' + LEV_ID); await p2.reload();
  await p2.waitForSelector('.aviso-alerta:has-text("Devuelto por la coordinación")');
  await irPaso(p2, 5);
  await p2.fill('[data-c="facilidades.electrica.capacidad"]', '3 breakers libres de 30 A');
  await p2.selectOption('[data-c="facilidades.estado_obra"]', 'construccion');
  await esperarSinc(p2);
  await irPaso(p2, 9);
  await p2.waitForSelector('#b-enviar-lev:not([disabled])');
  await p2.click('#b-enviar-lev'); await p2.click('dialog [data-aceptar]');
  await p2.waitForSelector('.distintivo:has-text("En revisión")');
  await p2.context().close();

  const c2 = await pagina({ ancho: 1280, alto: 860 });
  await entrar(c2, 'coord@refri.test');
  await c2.goto(URL_APP + '#/levantamientos/' + LEV_ID); await c2.reload();
  await c2.waitForSelector('.paso-lev'); await irPaso(c2, 9);
  await c2.click('#b-aprobar-lev'); await c2.click('dialog [data-aceptar]');
  await c2.waitForSelector('.distintivo:has-text("Aprobado")');
  afirmar(LEVS[0].estado === 'aprobado' && LEVS[0].aprobado_por === 'p1', 'no quedó aprobado por la coordinación');
  afirmar(LEV_HIST.filter((h) => h.levantamiento_id === LEV_ID).length === 5, 'el historial no tiene los 5 movimientos');
  await captura(c2, '45_aprobado_computadora');
  await c2.context().close();
});

await caso('5 · informe PDF aprobado según la plantilla (con la CSP de producción)', async () => {
  const c = await pagina({ ancho: 1280, alto: 860 });
  await entrar(c, 'coord@refri.test');
  await c.goto(URL_APP + '#/levantamientos/' + LEV_ID); await c.reload();
  await c.waitForSelector('.paso-lev'); await irPaso(c, 9);
  const [desc] = await Promise.all([c.waitForEvent('download', { timeout: 30000 }), c.click('#b-pdf')])
    .catch(async (e) => { throw new Error('sin descarga · ' + (await c.textContent('.toast').catch(() => '')) + ' · ' + e.message.split('\n')[0]); });
  const destino = path.join(CAPTURAS || '/tmp', desc.suggestedFilename());
  await desc.saveAs(destino);
  afirmar(desc.suggestedFilename() === 'PRB-26-0004-GE-IL-001_Rev0.pdf', 'nombre de archivo inesperado: ' + desc.suggestedFilename());
  const t = textoPDF(destino);
  for (const x of ['Informe de Levantamiento de Campo', 'PRB-26-0004-GE-IL-001', 'Control del documento', '1. Datos generales', '1.1 Áreas del sitio',
    '1.2 Datos para el cálculo de cargas', 'Quirófano 1 · PB', '32,5', '2. Antecedentes y motivo de la visita', '5. Descripción del sitio',
    '5.1 Facilidades para la instalación', '3 breakers libres de 30 A', 'En construcción', '6. Condicionantes del sitio', 'C-01',
    'Impacto en el diseño', '7. Criterios preliminares de diseño', '10.1 Registro fotográfico', 'Foto F-01.', 'Vista general del quirófano 1',
    'Página 1', 'Grupo RefriAmerica · Ventas, instalación y servicio de sistemas HVAC-R', 'Revisado / Aprobado por:', 'Juan Escalante']) {
    afirmar(t.includes(x), 'el PDF no contiene: ' + x);
  }
  afirmar(!t.includes('BORRADOR'), 'el PDF aprobado no debe decir BORRADOR');
  afirmar(!t.includes('Equipos existentes'), 'en instalación nueva no va la tabla de equipos existentes');
  afirmar(paginasPDF(destino) >= 4, 'el PDF tiene pocas páginas');
  await c.context().close();
});

await caso('6 · tipo existente y mixto: equipos con destino; informe en borrador; salir con datos pendientes avisa', async () => {
  REQS.find((r) => r.id === 'r4').estado = 'en_levantamiento';
  const p = await pagina();
  await entrar(p, 'ing@refri.test');
  await p.click('.pestanas [data-ruta="requerimientos"]');
  await p.click('#l-req .fila-req:has-text("PRB-26-0004")');
  await p.waitForSelector('#b-iniciar-lev'); await p.click('#b-iniciar-lev');
  await p.waitForSelector('.paso-lev');
  await p.check('input[name="tipo"][value="mixto"]');
  await p.waitForSelector('input[name="tipo"][value="mixto"]:checked');
  await p.fill('[data-c="visita.fecha"]', '2026-10-24');
  await irPaso(p, 3); await p.click('[data-accion="agregar"][data-l="areas"]'); await p.fill('details[open] [data-c="nombre"]', 'Salón');
  await irPaso(p, 4);
  await p.click('[data-accion="agregar"][data-l="equipos"]');
  afirmar((await p.inputValue('details[open] [data-c="tag"]')) === 'EQ-01', 'el TAG no se propuso');
  await p.selectOption('details[open] [data-c="tipo"]', 'piso_techo');
  await p.selectOption('details[open] [data-c="destino"]', 'retira');
  await p.selectOption('details[open] [data-c="area_id"]', { label: 'Salón' });
  await captura(p, '46_equipo_mixto_telefono');
  await esperarSinc(p);
  await irPaso(p, 9);
  const [desc] = await Promise.all([p.waitForEvent('download', { timeout: 30000 }), p.click('#b-pdf')]);
  const destino = path.join(CAPTURAS || '/tmp', desc.suggestedFilename()); await desc.saveAs(destino);
  const t = textoPDF(destino);
  afirmar(desc.suggestedFilename().endsWith('_BORRADOR.pdf') && t.includes('BORRADOR'), 'el borrador debe marcarse como tal');
  afirmar(t.includes('5.1 Equipos existentes') && t.includes('Se retira') && t.includes('6. Hallazgos'), 'el informe mixto no lleva equipos con destino');
  // Datos sin subir y cierre de sesión
  await p.context().setOffline(true);
  await irPaso(p, 2); await p.fill('[data-c="exclusiones"]', 'Tablero principal del edificio');
  await p.waitForTimeout(600);
  await p.click('.pestanas [data-ruta="cuenta"]'); await p.click('#b-salir');
  await p.waitForSelector('dialog[open]');
  afirmar((await p.textContent('dialog')).includes('se pierden'), 'debe advertir que hay datos sin subir');
  await p.click('dialog [data-cancelar]');
  await p.context().setOffline(false);
  await p.context().close();
});

await caso('7 · vendedor: ve el levantamiento de su requerimiento, sin poder modificarlo', async () => {
  const p = await pagina();
  await entrar(p, 'ventas@refri.test');
  await p.goto(URL_APP + '#/levantamientos/' + LEV_ID); await p.reload();
  await p.waitForSelector('.paso-lev');
  afirmar(await p.isDisabled('[data-c="visita.fecha"]'), 'el vendedor no debe poder modificar');
  afirmar(!(await p.$('[data-accion="agregar"]')), 'el vendedor no debe ver «Agregar»');
  await p.context().close();
});

await navegador.close(); servidor.close();
const graves = errores.filter((e) => !/404|Failed to load resource/.test(e));
if (graves.length) { console.log('\nErrores de consola:\n  ' + [...new Set(graves)].join('\n  ')); fallas++; }
console.log(`\nPruebas de la aplicación: ${total - Math.min(fallas, total)} de ${total} correctas${graves.length ? ' · con errores de consola' : ''}.`);
process.exit(fallas ? 1 : 0);
