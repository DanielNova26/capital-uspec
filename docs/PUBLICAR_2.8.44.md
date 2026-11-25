# Web 2.8.44 (98) — 25 de noviembre de 2026

El registro y la corrección de actas de Interventoría conservan el error
original de sus transacciones. La captura de Popayán mostraba solamente
`Dart exception thrown from converted Future`, que no identifica la causa
interna. Se reutiliza el auxiliar `runTransactionLegible` ya existente.

El aviso de fallo aparece sobre el formulario, se puede seleccionar y muestra
el paso que falló. Cerrar el aviso conserva los campos. Si el acta ya estaba
guardada antes de fallar los comentarios, el aviso lo aclara para evitar que
se vuelva a registrar.

## Validación y publicación

- 32 pruebas pasan: repositorio con envoltorio JS simulado, rollback,
  duplicado concurrente sin sobrescritura, corrección ajena, cierre,
  identidad y auxiliar de transacciones. El diálogo conserva el campo
  diligenciado y no desborda a 390/768/1024/1366, con texto al 200 % y temas
  de plataforma Android/iOS.
- Análisis de los archivos afectados sin errores ni advertencias; tres
  informaciones anteriores en la pantalla de Interventoría.
- `flutter build web --release --no-pub` completado. Las advertencias del
  dry-run de Wasm no afectan la compilación JavaScript publicada.
- Hosting `to-do-gestion` publicado. Controles de CSP, archivos públicos y
  protección de Maps superados. No se publicaron reglas ni funciones.
- Ambos dominios, `to-do-gestion.com` y `to-do-gestion.web.app`, sirven
  `version.json` con versión 2.8.44 y build 98.
- Los hashes SHA-256 del JavaScript y bootstrap públicos coinciden con los
  artefactos locales. Informe privado ignorado:
  `outputs/support/web-2.8.44-verificada.json`.

## Pendientes reales

La causa operativa del registro de Popayán sigue sin identificar: se necesita
un reintento con esta versión y el mensaje original o un guardado confirmado.
El diálogo y las transacciones se validaron con pruebas automatizadas; no se
probó la cuenta real, el archivo afectado ni un registro operativo en
producción. No se verificaron dispositivos físicos, teclado o áreas seguras
en Android/iOS y no se generaron AAB/IPA en esta entrega. No cambia el acceso,
los roles, las cuotas ni los datos operativos.
