# AGENTS - ToDo

## Regla general de plataforma
La app debe funcionar en Web adaptable, Android e iOS (iPhone). Web y ambas
apps móviles comparten lógica de negocio, empresa activa, roles y permisos.
Pero no deben compartir exactamente la misma experiencia visual ni el mismo flujo de navegación.

El tamaño se decide por el espacio lógico disponible, no por pulgadas ni por
`kIsWeb`: una ventana Web estrecha debe seguir siendo usable en un portátil de
10 pulgadas, y una más amplia debe aprovechar un portátil de 14 pulgadas o
un monitor. Comprobar al menos 390, 768, 1024 y 1366 píxeles lógicos, además
de escala de texto aumentada. Evitar desbordes, botones fuera de pantalla y
diálogos más anchos que el área visible. Validar Android e iOS por separado,
incluidas áreas seguras, teclado, navegación y permisos de plataforma.

La Web debe aprovechar:
- espacio horizontal
- paneles laterales
- tablas
- filtros persistentes
- vistas maestro-detalle
- mayor densidad de información

El Móvil debe priorizar:
- foco por tarea
- menos elementos por pantalla
- navegación compacta
- acciones rápidas
- menor carga visual
- jerarquía clara

No quiero:
- una web que parezca una app móvil estirada
- un móvil que parezca una web comprimida

## Contrato obligatorio al crear o ampliar un módulo
Antes de dar un módulo por terminado, comprobar lo siguiente:

- Registrar **todos sus maestros y configuraciones por empresa en Admin**,
  con editor y fuente canónica allí. El módulo operativo consume esa fuente;
  no crea un segundo editor ni una copia del catálogo. Si existe un maestro
  histórico en el módulo, ofrecer revisión e incorporación segura en Admin
  antes de retirar el flujo anterior.
- Registrarlo en el catálogo común de apps y en Admin → Apps, roles y permisos, con el mismo identificador canónico en Web, móvil, backend y reglas.
- Respetar la empresa activa y la pertenencia/habilitación de la persona en cada lectura, escritura y navegación.
- Si hay más de un nivel operativo, incluir en la tarjeta de Admin el creador de roles (crear, editar, inactivar), niveles iniciales, asignación por persona, nivel individual y sincronización de cambios. Mantener una única fuente de verdad para nombres y capacidades. Si el módulo solo tiene acceso a la app, dejarlo explícito, sin inventar roles.
- Hacer coherentes los tres caminos de acceso de Admin: cambio individual, cambio masivo y editor general de módulos. Retirar acceso debe retirar o neutralizar el nivel efectivo; volver a concederlo no debe restaurar un privilegio antiguo. Conservar el nivel de quien ya tenía acceso. No cruzar empresas.
- Consolidar datos o permisos históricos de forma segura, sin sobrescribir asignaciones canónicas ni modificar producción automáticamente.
- Aplicar los niveles tanto en la navegación como en las reglas/servicios que protegen los datos. El módulo no se considera cerrado si la UI oculta una acción pero el backend permite ejecutarla sin permiso.
- Probar los flujos de creador, asignación, edición, revocación, reactivación, empresa secundaria y rol histórico. Registrar limitaciones de validación en `MEJORAS.md`.
- Compartir lógica de negocio y permisos entre Web y móvil, pero adaptar por separado la composición y la navegación según la regla de plataforma de este archivo.
- Probar Web en ancho estrecho y amplio, Android e iOS, con tamaños de texto y
  formularios reales; registrar cualquier plataforma no verificada en
  `MEJORAS.md`.

Los perfiles generales son plantillas opcionales de apps, gestionadas en
Admin → Apps, roles y permisos. No sustituyen el acceso efectivo ni los roles
internos del módulo. Antes de cambiar o desactivar un perfil histórico,
auditar los `roleKey`/`roleId` de autoridad que aún usa el backend (Desarrollo,
Gerencia y administradores históricos); una etiqueta inactiva no revoca por
sí sola esos privilegios.

Para coordinar cambios entre Codex y Claude, usar `MEJORAS.md` como bitácora compartida.

## Comunicación en cada conversación
Mostrar al usuario principalmente el resultado final: qué quedó hecho, validación y pendientes reales. No narrar comandos, razonamiento interno ni una cronología del proceso. Las actualizaciones intermedias, si son necesarias, deben ser breves y limitarse a hallazgos o bloqueos que cambien el resultado. Esta regla se aplica a Codex y Claude en cada conversación de este repositorio.

## Gemini
Responsable de:
- front visual
- layouts
- componentes
- SVG
- GIF
- animaciones
- consistencia visual
- experiencia premium
- diferenciación real entre Web y Móvil desde UX y diseño

No hace Git.

## Claude
Responsable de:
- Firestore
- reglas
- arquitectura
- repositorios
- validaciones
- integraciones
- estabilidad
- soporte técnico para diferencias reales entre Web y Móvil sin duplicar innecesariamente la lógica

No hace Git.

## Codex
Responsable de:
- flujo funcional
- jerarquía de acceso
- navegación por rol
- permisos por usuario
- pruebas funcionales
- integración entre front y back
- consolidación final
- Git y GitHub
- definir qué parte del flujo debe compartirse y qué parte debe diferenciarse entre Web y Móvil

Por defecto solo Codex hace:
- git add
- git commit
- git push

Si el usuario pide expresamente hacer Git por su cuenta, Codex entrega los
comandos seguros y no ejecuta add, commit ni push en esa conversación.

## Git: siempre en `main`, nunca en ramas
Regla del usuario (28 sep 2026), para no enredarnos entre Codex y Claude:
todo el trabajo va directo a `main`. No se crean ramas.

Esta regla se aplica desde el inicio de cada conversación. Claude edita el
checkout de `main` pero no ejecuta Git; Codex es el único responsable de
sincronizar, confirmar y subir los cambios.

- Codex, antes de empezar: `git pull origin main`.
- Codex, al terminar: commit y `git push origin main`.
- Si el push se rechaza porque `main` avanzó: `git pull --no-rebase origin main`,
  resolver, volver a correr las pruebas y subir. Nunca push forzado.
