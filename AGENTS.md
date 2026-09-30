# AGENTS - ToDo

## Regla general de plataforma
Web y móvil comparten lógica de negocio, empresa activa, roles y permisos.
Pero no deben compartir exactamente la misma experiencia visual ni el mismo flujo de navegación.

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

## Maestros por módulo (decisión del usuario, 30 sep 2026)
- Cada módulo crea y edita sus maestros **en su módulo**, en su propia
  empresa. En Compras, proveedores, productos, marcas y fichas técnicas los
  crea y edita el equipo de Compras uno a uno: es así a propósito y **no es
  un pendiente de Admin**.
- **Admin › Maestros por módulo** tiene dos cosas: la configuración que es
  de Administración (en Compras: las cargas por Excel de proveedores,
  productos y requisitos documentales, y el plazo de rechazados; además
  Correo, Tokens DIAN y WhatsApp) y **"Copiar a otras empresas"**. Bodegas y
  grupos de Compras también se crean en Admin.
- Ningún módulo muestra otras empresas: nada de "copiar a otra empresa"
  dentro de un módulo. Lo que mueve datos entre empresas va en Admin
  (Maestros por módulo, o Usuarios › Multiempresa para personas, áreas,
  cargos y centros).
- La copia (`adminSincronizarMaestros`, `functions/src/maestros.ts`) solo
  agrega lo que el destino no tiene y nunca pisa. Un maestro nuevo se agrega
  al catálogo del servidor y a `kModulosMaestros`
  (`lib/admin/maestros_sync_service.dart`); `test/admin/maestros_sync_test.dart`
  falla si no coinciden.

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

Solo Codex hace:
- git add
- git commit
- git push

## Git: siempre en `main`, nunca en ramas
Regla del usuario (28 sep 2026), para no enredarnos entre Codex y Claude:
todo el trabajo va directo a `main`. No se crean ramas.

- Antes de empezar: `git pull origin main`.
- Al terminar: commit y `git push origin main`.
- Si el push se rechaza porque `main` avanzó: `git pull --no-rebase origin main`,
  resolver, volver a correr las pruebas y subir. Nunca push forzado.
