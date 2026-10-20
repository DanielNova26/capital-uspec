# Instructivo: cobertura del personal y avisos de Interventoría

Para Talento Humano y Administración. Explica qué hay que revisar en el
personal para que cada subsanación de Interventoría le llegue a la persona
de **su** establecimiento, y cómo hacerlo en bloque, sin ir uno por uno.

## 1. Qué decide a quién le llega un aviso

Cuando Interventoría registra un hallazgo, el sistema busca a la persona con
el cargo que pide la regla del numeral **y que cubra el establecimiento**.
La cobertura de una persona sale de:

1. **Centros de operación y de trabajo** (Talento Humano › Editar colaborador
   › Grupos y cobertura). Es la cobertura propia.
2. **Grupos** (Grupo 1, Grupo 7…): suman **todas** las sedes del grupo, pero
   **solo si el cargo usa grupos** (ver sección 2).
3. **Centro de costos** de la persona, únicamente si no tiene centros de
   operación ni de trabajo ni grupos.

Si en el establecimiento no hay nadie con el cargo, el hallazgo queda
**"Sin asignar"** y se decide a mano en el tablero de Interventoría. Ya no se
manda a una persona de otra sede.

## 2. Qué cargos usan grupos

| Tipo de cargo | Ejemplo | ¿Usa grupos? |
|---|---|---|
| Cargos que atienden varias sedes | Coordinador de calidad, Director de operaciones, Supervisor HSE, Nutricionista | **Sí** |
| Cargos de una sola sede | Administrador Tipo 1, Administrador Tipo 2 | **No** |
| Cargos que atienden toda la operación | Tesorero, director de operaciones, abogado, auxiliar de talento humano | Se marcan **TODAS LAS SEDES** por persona (ver 3.1) |

Cada cargo tiene una marca **"Cobertura por grupo"**:

- Talento Humano › Cargos › editar el cargo › interruptor **Cobertura por
  grupo**.
- Si el cargo no tiene la marca escrita, el sistema la deduce por el nombre:
  los que contienen "administrador" no usan grupos; los demás sí.

> **Caso real que originó esto.** Annie Velazco (Administrador Tipo 1) tenía
> centro de operación y de trabajo en Moniquirá, pero también el **Grupo 7**.
> El grupo le sumaba 11 sedes más y por eso recibía las subsanaciones de
> Guateque, Modelo, Ponal y Ubaté. Con la marca apagada en su cargo, solo
> cubre Moniquirá.

## 3. Paso a paso, en bloque

Ruta: **Admin › Maestros por módulo › Tareas y notificaciones › Cobertura**.

### Paso 1. Revisar las marcas de los cargos (una vez)
1. Talento Humano › Cargos.
2. Abrir cada cargo de sede (Administrador Tipo 1, Tipo 2…) y dejar
   **Cobertura por grupo apagada**.
3. Abrir los cargos de coordinación, dirección y supervisión y dejarla
   **encendida**.

### Paso 2. Los grupos de los administradores se quedan

El grupo de una persona (por ejemplo el Grupo 7 de un administrador) **no se
borra**: sirve para llevar el orden. Lo único que cambia es que, si su cargo no
usa grupos, el grupo **no le suma sedes**: su cobertura sale de sus sedes de
operación y de trabajo. En Cobertura esas personas aparecen como **"Grupo solo
de orden (no suma sedes)"** y no es un error.

El botón "Quitar grupos" existe, pero **no hace falta usarlo**: solo si algún
día una persona ya no necesita el grupo para llevar el orden.

### Paso 3. Dejar explícita la sede de quien solo tiene centro de costos
1. Filtro **"Solo centro de costos"**.
2. **"Seleccionar los N de la lista"**.
3. **"Fijar su centro de costos (N)"** y confirmar. Su centro de costos pasa a
   ser su centro de operación.

### Paso 4. Resolver a mano a quien queda sin sede
1. Filtro **"Sin ninguna sede"**: personas sin centro de operación, de
   trabajo, grupo ni centro de costos.
2. Son pocas: abrir a cada una en Talento Humano › Editar colaborador ›
   **Grupos y cobertura** y cargarle su sede (administradores) o su grupo
   (coordinadores).

### Paso 5. Revisar a los coordinadores
Filtro **"Correcta"** y cargo, por ejemplo "Coordinador De Calidad": comprobar
que cada uno tiene el grupo o las sedes que realmente atiende. Quien cubre
una sede de otro coordinador aparece en el monitor como alerta (sección 4).

## 3.1 Cambios masivos con Excel (recomendado para muchos cambios)

Para cargar la cobertura de mucha gente a la vez, sin editar persona por
persona:

1. **Admin › Maestros por módulo › Tareas y notificaciones › Cobertura** y
   pulsar **"Descargar modelo Excel"**. Trae a todo el personal activo con lo
   que tiene hoy.
2. En la hoja **Cobertura** editar solo tres columnas: **SEDES DE OPERACION**,
   **SEDES DE TRABAJO** y **GRUPOS**. Las demás son de consulta.
   - Varias sedes o grupos se separan con punto y coma: `Picota; La Mesa`.
   - Los grupos de los administradores se dejan como están: no suman sedes.
   - Los nombres de sede se copian de la hoja **Sedes**; los grupos son
     `G1`, `G7`… (hoja **Grupos**).
   - Una celda vacía significa "ninguna".
   - **Personas que atienden toda la operación** (tesorero, director de
     operaciones, abogado, auxiliar de talento humano…): en **TODAS LAS SEDES**
     escribe `SI`. Reciben los hallazgos de cualquier sede, pero **solo cuando
     esa sede no tiene un titular propio de su cargo**: si en La Mesa hay un
     tesorero que cubre La Mesa, el hallazgo va a él y no al global. `NO` quita
     la marca; vacío no cambia nada. No hace falta llenar sedes ni grupos para
     ellos. Hazlo con todos los que correspondan, aunque no estés seguro de que
     el cargo reciba hallazgos: no estorba.
   - **Llenar sedes de un grupo de un tirón:** en **AGREGAR GRUPO** escribe el
     grupo (por ejemplo `G6`) y en **COMO** elige `TRABAJO`, `OPERACION` o
     `AMBAS` (vacío = trabajo). Al importar, la aplicación copia todas las sedes
     de ese grupo a la columna elegida. Esto **no** cambia los grupos de la
     persona (para eso está la columna GRUPOS); solo ahorra escribir las sedes
     una a una. Después de importar, las sedes quedan escritas en su fila.
   - Se puede filtrar por cargo en Excel para trabajar por bloques (por
     ejemplo, todos los "Administrador Tipo 1": su sede en operación y en
     trabajo; su grupo se deja como está).
   - No cambiar la CEDULA ni los títulos; no hace falta borrar las filas que no
     se cambian.
3. Guardar como `.xlsx` y pulsar **"Importar Excel"**.
4. La aplicación muestra **antes de aplicar**: filas leídas, personas con
   cambios (con el "antes → después" de cada una), filas sin cambios y filas
   **rechazadas** con el motivo (sede que no existe, grupo inválido, cédula
   que no es de la empresa). Las rechazadas no se aplican: se corrigen en el
   Excel y se vuelve a subir el archivo; lo ya aplicado no se duplica.
5. Pulsar **"Aplicar N cambios"**.

Solo se cambia lo que difiere de lo guardado, y solo las columnas editadas.

## 4. Comprobar que quedó bien

Ruta: **Admin › Maestros por módulo › Tareas y notificaciones › Monitor**.

- **Alertas** debe quedar en 0. Una alerta es un aviso de "te toca subsanar"
  que llegó a alguien que no cubre la sede.
- Escribir el nombre de la persona en el buscador: la ficha muestra su
  **cobertura propia**, cuántas sedes suma por grupo y de qué sedes recibió
  avisos.
- Cada alerta dice **por qué le llegó** (qué cargo pedía la regla, quién lo
  cubre en esa sede y si la asignó el sistema o una persona).

### Corregir lo que ya se asignó mal
En **Monitor › Alertas**:

- **Reasignar a quien cubre la sede**: ofrece solo a quien cumple el cargo de
  la regla y cubre la sede. Solo si no hay nadie muestra todo el personal,
  con filtro por área y búsqueda.
- **Quitar asignación**: devuelve el hallazgo a "Sin asignar".

Ambas retiran los avisos que tenía quien perdió la tarea. Solo actúan sobre
tareas que aún no se han iniciado.

## 5. Para que no vuelva a pasar

Al **vincular personal nuevo**:

- **Administrador:** centro de operación y de trabajo = su sede. Puede tener
  su grupo para llevar el orden: no le suma sedes.
- **Coordinador, director, supervisor:** el grupo que atiende (o las sedes una
  a una si no cubre todo el grupo).
- Si se cambia a alguien de sede, cambiar su centro de operación y de trabajo
  (no solo el centro de costos).
- Una vez al mes, mirar los filtros **"Solo centro de costos"** y
  **"Sin ninguna sede"**: deben estar en 0.

## 6. Cómo repartir el trabajo para que no sea pesado

1. **Una persona** hace el paso 1 (marcas de los cargos): son pocos cargos.
2. Los pasos 2 y 3 son **masivos y toman minutos**: se ejecutan por filtro,
   con la lista a la vista antes de confirmar.
3. Solo el paso 4 y la revisión de coordinadores son manuales; se pueden
   repartir por grupo (Grupo 1, Grupo 2…) entre el equipo.
4. Al terminar, Administración revisa **Monitor › Alertas** y reasigna lo que
   quedó pendiente.

## 7. Preguntas frecuentes

**¿Quitar un grupo borra a la persona o sus tareas?** No. Solo deja de sumarle
sedes. Sus tareas y accesos siguen igual.

**¿Puedo deshacerlo?** Sí: se vuelve a marcar el grupo en Editar colaborador, o
se enciende la marca del cargo.

**Una administradora sí atiende dos sedes.** Cárgale las dos en centros de
operación y de trabajo; no necesita grupo.

**Un coordinador solo atiende algunas sedes del grupo.** Quítale el grupo y
cárgale esas sedes una a una.
