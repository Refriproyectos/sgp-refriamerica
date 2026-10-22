# Configuración de cuentas — paso a paso

Todas las cuentas se crean con el **correo corporativo del sistema, `gestion.proyectos@refriamerica.com`**, nunca con un correo
personal. Cada una tiene un segundo administrador.

**Regla de seguridad:** la contraseña de la base de datos y la clave `service_role` de
Supabase **no se envían por chat ni se guardan en el repositorio**. Se guardan en un gestor de
contraseñas de la empresa.

## 1. Correo corporativo
- [ ] Crear `gestion.proyectos@refriamerica.com`.
- [ ] Activar verificación en dos pasos.

## 2. GitHub
- [ ] Crear la cuenta con el correo corporativo y activar verificación en dos pasos.
- [ ] Crear el repositorio **privado** `sgp-refriamerica`, vacío (sin README ni licencia).
- [ ] Invitar al segundo administrador como colaborador.

## 3. Supabase
- [ ] Crear la cuenta con el correo corporativo.
- [ ] Crear el proyecto `sgp-refriamerica`, región **East US (North Virginia) · us-east-1**.
- [ ] Guardar la contraseña de la base en el gestor de contraseñas.
- [ ] Copiar y enviar **solo**: la URL del proyecto (`https://<ref>.supabase.co`) y la clave
      pública `anon` (Project Settings → API).
- [ ] Authentication → Providers: dejar activo solo *Email*; desactivar el registro abierto
      (las cuentas las crea el administrador).
- [ ] Invitar al segundo administrador a la organización.

## 4. Netlify
- [ ] Crear la cuenta con el correo corporativo. El sitio se crea en el paso de publicación.

## 5. Google Drive
- [ ] Crear la carpeta `SGP` con `Respaldos/BaseDatos`, `Respaldos/Archivos` y `Proyectos`.
- [ ] Compartirla con el segundo administrador como editor.
- [ ] Confirmar si la empresa usa Google Workspace (permite que la carpeta pertenezca a la
      empresa y no a una persona).

## 6. Primera ejecución en Supabase (cuando el proyecto exista)
1. Abrir **SQL Editor** → *New query*.
2. Pegar el contenido completo de `sql/00_base_comun.sql` y ejecutar.
3. Verificar que al final aparezcan las tres líneas `OK ·`.
4. En **Authentication → Users → Add user**, crear la cuenta del administrador.
5. En SQL Editor, asignarle el rol (única vez que se hace a mano):
   `update public.perfiles set rol = 'admin' where correo = '<correo del admin>';`

## 7. Usuarios con correo de otro dominio (decisión del 21/10/2026)

Parte del personal de la empresa usa un correo corporativo de **otro dominio, que no es Google
Workspace**. Para el sistema son usuarios **internos**, con los mismos roles que el resto:

- **Acceso al sistema:** correo y contraseña de Supabase, igual que cualquier usuario. No
  depende de Google.
- **Unidad compartida de Drive:** para Workspace son usuarios externos. Para darles acceso a
  los archivos de trabajo:
  1. Cada persona crea una **cuenta de Google con su correo actual** (sin Gmail), en
     https://accounts.google.com/signup → "Usar mi dirección de correo electrónico actual".
  2. El administrador de Workspace permite compartir con ese dominio (**Consola de
     administración → Apps → Google Workspace → Drive y Documentos → Configuración para
     compartir**, lista de dominios permitidos).
  3. Se les agrega como miembros de la unidad compartida.
- **Correos del sistema** (invitación, recuperación de contraseña): pueden llegar a la carpeta
  de correo no deseado de otros dominios. Pedir a cada persona que la revise la primera vez.

## 8. Carpetas de Google Drive (21/10/2026)

Ubicación: **unidad compartida `SGP`** de Google Workspace (pertenece a la empresa, no a una
cuenta). Las carpetas creadas antes en *Mi unidad* de `gestion.proyectos@` quedan sin uso.

| Carpeta | Identificador de Drive |
| --- | --- |
| Unidad compartida `SGP` (raíz) | `0AIjs8_Zac5QIUk9PVA` |
| `SGP/Proyectos` | `1bWCUBQKPTqXZSpVCQWtrJ7_Q_VSh3XV8` |
| `SGP/Respaldos/BaseDatos` | `1K3U3NHrQsRiyO0bgLcZupzCP3cOLcAoh` |
| `SGP/Respaldos/Archivos` | `1R_6eXCSlIwvvOTA6N8MT9OqPKObKWaIt` |

Verificado el 21/10/2026: las tres carpetas están en la unidad compartida (sin dueño individual).

Los procesos usan el **identificador**, no el nombre: renombrar o mover una carpeta no los afecta.
