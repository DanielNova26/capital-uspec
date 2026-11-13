# Demo de Capital y Servir

Abre la [Demo local](http://127.0.0.1:8787) en este computador. Usa la cédula de la tabla y la contraseña local `SoloDemoLocal2026!`.

| Área | Director | Coordinador | Analista | Módulos del área, además de Tareas |
| --- | --- | --- | --- | --- |
| Calidad | `9900001001` | `9900001002` | `9900001003` | Compras, Interventoría, Visitas y Biblioteca |
| Compras | `9900001004` | `9900001005` | `9900001006` | Compras |
| Contabilidad | `9900001007` | `9900001008` | `9900001009` | Planillas de Pago, Tokens DIAN, Compras y Biblioteca |
| Desarrollo | `9900001010` | `9900001011` | `9900001012` | Administración para el director |
| Facturación | `9900001013` | `9900001014` | `9900001015` | Facturación |
| Gerencia | `9900001016` | `9900001017` | `9900001018` | Gerencia de su área y Biblioteca |
| Jurídica | `9900001019` | `9900001020` | `9900001021` | Correo, Correspondencia y Biblioteca |
| Logística | `9900001022` | `9900001023` | `9900001024` | Compras y Rutas |
| Mantenimiento | `9900001025` | `9900001026` | `9900001027` | Mantenimiento y Visitas |
| Operaciones | `9900001028` | `9900001029` | `9900001030` | Interventoría, Facturación, Nutrición y Visitas |
| Planeación | `9900001031` | `9900001032` | `9900001033` | Gerencia de su área y Visitas para director y coordinador |
| Sistemas | `9900001034` | `9900001035` | `9900001036` | Biblioteca |
| Talento Humano | `9900001037` | `9900001038` | `9900001039` | Talento Humano y Biométrico |
| Gestión de Proyectos | `9900001040` | `9900001041` | `9900001042` | Tareas |

**Gerente General `9900001000`** supervisa todas las áreas de la Demo, tiene acceso a los módulos de negocio con los niveles de cada módulo y firma Planillas de Pago. El usuario de Administración es el director de Desarrollo.

La jerarquía va de Gerente General a director, coordinador y analista. En Calidad se pueden comparar los permisos de Visitas e Interventoría. En Contabilidad, el analista carga las planillas, el coordinador o director audita y Gerencia firma. El analista de Operaciones tiene asignado el Establecimiento Demo en Facturación.

Las 13 áreas de Capital y Servir se tomaron como referencia y se incluyó Gestión de Proyectos, que ya existía en la Demo. Los cargos, relaciones de reporte, accesos y sede se prepararon para pruebas. La carga contiene personas, estructura y permisos ficticios. Los flujos empiezan con sus registros operativos vacíos. Correo, DIAN y WhatsApp carecen de conexiones externas.

Interventoría incluye las cuatro plantillas PEC USPEC habilitadas en Capital y Servir y 140 reglas de subsanación adaptadas a los cargos de la Demo. Para los numerales compartidos se tomó Capital como referencia y Servir aportó los faltantes. Puedes probar el registro de un acta con PDF desde el analista de Calidad y abrirla desde el coordinador. El almacenamiento local permite PDF e imágenes para actas y conceptos sanitarios según el rol de Interventoría.

En Tareas, el responsable puede reportar avances, comunicar novedades y solicitar la finalización con evidencias. Si la tarea viene de un hallazgo de Interventoría, su aprobador puede revisar las evidencias y cerrar la tarea desde el hallazgo.

El director, coordinador y analista de Mantenimiento y Gerencia General tienen acceso operativo a Mantenimiento. La carga completa la autorización de quienes conservan la app asignada en la Demo y respeta los permisos que ya estén guardados.

## Reiniciar el entorno local

Desde la raíz del repositorio, con Java, Firebase CLI, Flutter y las dependencias de Functions instaladas, ejecuta en PowerShell:

```powershell
./tool/demo/iniciar.ps1
```

Deja abierta esa terminal. Si es la primera carga, en otra terminal ejecuta:

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
node tool/demo/poblar.cjs
```

La carga puede repetirse y agrega las reglas de Interventoría y los accesos de Mantenimiento que falten. Para guardar tus pruebas al terminar, detén el emulador con `Ctrl+C` y espera a que exporte los datos. El siguiente arranque recupera esa exportación. Usa `-Recompilar` para actualizar la web local después de cambiar el código de la app.
