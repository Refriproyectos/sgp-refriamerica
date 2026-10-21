# SGP — Sistema de Gestión de Proyectos · Grupo RefriAmerica

Sistema de gestión de recursos del Departamento de Proyectos. Hermano del Sistema de
Gestión de Servicios (SGS v8.5): misma arquitectura, base de datos propia.

Documentos de referencia:

- **RFA-PRY-MAN-001** — Manual de Procesos del Departamento de Proyectos (alcance funcional).
- **Especificación para réplica del SGS** — arquitectura, estándares y lecciones aprendidas.
- **Plan de arranque del SGP** — hoja de ruta por sesiones.

## Arquitectura

| Capa | Tecnología |
| --- | --- |
| Aplicación | PWA de un solo archivo (`app/index.html`), HTML + CSS + JavaScript sin framework |
| Datos, acceso y archivos | Supabase: PostgreSQL 16, Auth, Storage (depósito **privado**) |
| Publicación | Netlify (cuenta corporativa) |
| Respaldo | Proceso nocturno en GitHub Actions → Google Drive |

## Estructura

```
app/        Lo que se publica en Netlify (index.html, sw.js, manifest, vendor/, assets/)
sql/        Archivos SQL numerados, en orden de ejecución. Nunca se edita uno ya ejecutado.
pruebas/    Una prueba SQL por archivo de sql/
banco/      Banco de pruebas local que reconstruye la base desde cero
bitacora/   Un registro por versión: qué se pidió, qué se decidió y por qué
```

## Reglas de trabajo (heredadas del SGS)

1. **Un cambio de base = un archivo nuevo numerado** en `sql/`, ejecutado una sola vez en el
   editor SQL de Supabase. Nunca se edita un archivo ya ejecutado en producción.
2. Cada archivo corre dentro de una transacción y **se puede volver a ejecutar** sin daño.
3. Antes de redefinir una función se retira la anterior **nombrando su firma completa**
   (`drop function if exists f(tipos)`): `create or replace` con otros parámetros crea una
   segunda función.
4. Toda función termina con **permisos explícitos**:
   `revoke all ... from public, anon; grant execute ... to authenticated;`
5. Toda función `security definer` fija su `search_path`.
6. Cada archivo **termina con sus comprobaciones** (que revierten el archivo si fallan) y con una
   **consulta de resumen**, porque el editor SQL de Supabase no muestra los avisos `NOTICE`.
7. Cada archivo tiene su prueba en `pruebas/`, que se corre contra el banco reconstruido.
   Una prueba nueva se comprueba **viéndola fallar** sin el arreglo.
8. **Orden de despliegue: primero el SQL, después la aplicación.** El Service Worker sube
   de versión en cada despliegue.
9. **El control está en la base, no en la pantalla.** Ocultar un botón es una cortesía.
10. Nomenclatura en español: tablas en plural, prefijos `v_` vistas, `fn_` consultas,
    `rpc_` funciones que llama la aplicación, `trg_` disparadores, `p_` políticas.
11. Fechas en `America/Caracas`, escrita explícitamente en cada consulta.
12. **Nunca** se guardan en el repositorio contraseñas, la clave `service_role` ni cadenas de
    conexión. Solo la URL del proyecto y la clave pública `anon`.

## Banco de pruebas local

```bash
banco/reconstruir.sh          # crea una base limpia y ejecuta sql/ en orden
banco/probar.sh               # reconstruye y corre todas las pruebas de pruebas/
```

Requiere PostgreSQL 16 (la misma versión de Supabase).

## Prueba de la aplicación

```bash
npm i playwright
node pruebas/app_v0.2.mjs [carpeta_capturas]   # Supabase simulado, teléfono y computadora
```

## Publicación

Ver `bitacora/PUBLICACION.md`. Netlify publica la carpeta `app/` (archivo `netlify.toml`).
