# Publicación — paso a paso

Orden obligatorio en cada versión: **primero el SQL en Supabase, después la aplicación en
Netlify.** En la v0.2 no hay SQL nuevo: la base 0.1 ya está instalada.

## Paso 1 — Subir el código a GitHub (una sola vez, ~5 min)

1. Descomprima `sgp-refriamerica_v0.2.zip` en su computadora. Queda una carpeta `sgp-refriamerica`.
2. Abra **https://github.com/Refriproyectos/sgp-refriamerica** con la cuenta
   `gestion.proyectos@refriamerica.com`.
3. En la página del repositorio vacío, pulse el enlace **uploading an existing file**.
4. Abra la carpeta `sgp-refriamerica` y **arrastre todo su contenido** (las carpetas `app`,
   `banco`, `bitacora`, `pruebas`, `sql` y los archivos `README.md`, `netlify.toml`,
   `.gitignore`) a la ventana del navegador. No arrastre la carpeta, sino lo que está dentro.
   - Si el archivo `.gitignore` no aparece porque está oculto, no importa en este paso.
5. Abajo, en *Commit changes*, escriba `v0.2: aplicación base` y pulse **Commit changes**.
6. Verifique que en la página del repositorio aparecen las carpetas `app`, `sql`, etc.

## Paso 2 — Publicar en Netlify conectado a GitHub (una sola vez, ~5 min)

1. Abra **https://app.netlify.com** con la cuenta corporativa.
2. **Add new project → Import an existing project → GitHub**. Autorice a Netlify y elija el
   repositorio `Refriproyectos/sgp-refriamerica`.
3. En la configuración verá *Publish directory: `app`* (lo lee del archivo `netlify.toml`).
   Deje *Build command* vacío. Pulse **Deploy**.
4. En **Project configuration → Change project name**, use `sgp-refriamerica`. La dirección
   quedará `https://sgp-refriamerica.netlify.app` (si el nombre está tomado, Netlify
   propone otro: anótelo).

Desde entonces, cada cambio que se suba a GitHub se publica solo.

## Paso 3 — Decirle a Supabase cuál es la dirección del sistema (~2 min)

Sin esto, los enlaces de recuperación de contraseña y de invitación no funcionan.

1. Supabase → proyecto `sgp-refriamerica` → **Authentication → URL Configuration**.
2. **Site URL:** `https://sgp-refriamerica.netlify.app` (la dirección real del paso 2).
3. **Redirect URLs → Add URL:** la misma dirección terminada en `/**`
   (`https://sgp-refriamerica.netlify.app/**`). Guarde.

## Paso 4 — Probar en los tres dispositivos

| Dispositivo | Cómo instalar | Qué comprobar |
| --- | --- | --- |
| Computadora (Chrome o Edge) | Ícono de instalar en la barra de direcciones | Inicio de sesión, menú lateral, Personal |
| Android (Chrome) | Menú ⋮ → **Instalar aplicación** | Ícono en la pantalla de inicio, pestañas inferiores |
| iPhone (Safari) | Botón **Compartir → Agregar a pantalla de inicio** | Se abre a pantalla completa, sin barra de Safari |

En los tres: iniciar sesión con su cuenta de administrador, abrir **Personal** y agregar a una
persona del departamento con su correo y su rol.

## Paso 5 — Dar acceso a una persona

1. En la aplicación, **Personal → Agregar persona**, con su correo corporativo y su rol.
2. En Supabase → **Authentication → Users → Add user → Send invitation**, con **el mismo
   correo**. La cuenta se enlaza sola con la ficha.
3. La persona recibe un correo, abre el enlace y define su contraseña en la aplicación.

> El servicio de correo incluido en Supabase envía pocos correos por hora. Alcanza para la
> puesta en marcha; para operación real conviene configurar el correo de la empresa (SMTP).
