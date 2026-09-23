// lib/interventoria/interventoria_actas_catalogo.dart
//
// Catálogo de aspectos por TIPO DE ACTA.
//
// El acta regular tiene su propia maquinaria en `interventoria_models.dart` +
// `interventoria_numerales_catalogo.dart`: categorías con clave, matriz de
// responsabilidad incluida y numerales derivados del texto del aspecto. Ese
// camino se conserva intacto.
//
// Las actas que llegaron después —Infraestructura y Estaciones de Policía— son
// formularios distintos, no variantes del regular: otras secciones, otros
// aspectos y otra numeración. Se declaran aquí con la forma más simple que
// admite el formato impreso: secciones numeradas, aspectos en orden, y el
// numeral es literalmente `sección.posición`, igual que en el papel.
//
// Deliberadamente NO se modelan:
//  - La columna FRQ/AD/CD (frecuencia y causal de descuento) del acta de
//    policía. La interventoría entrega el acta ya diligenciada; aquí solo se
//    registra para hacerle gestión, y el PDF queda enlazado al hallazgo.
//  - Los bloques propios del acta de policía (horarios de entrega, personal de
//    reparto, inspección del vehículo). Lo que se necesita son los puntajes.
//
// Si algún día hacen falta, el sitio es este.

/// Identificadores de tipo de acta. Se guardan en `TBL_INTERVENTORIA_HALLAZGOS
/// .tipoActa`, así que son valores estables: cambiarlos rompe el histórico.
const String kActaRegular = 'REGULAR';
const String kActaSeguimiento = 'SEGUIMIENTO';
const String kActaInfraestructura = 'INFRAESTRUCTURA';
const String kActaEstacionPolicia = 'ESTACION_POLICIA';
const String kActaAlcaldiaPlanta = 'ALCALDIA_PLANTA';
const String kActaAlcaldiaEstacionPolicia = 'ALCALDIA_ESTACION_POLICIA';

const List<String> kTodosTiposActaInterventoria = [
  kActaRegular,
  kActaSeguimiento,
  kActaInfraestructura,
  kActaEstacionPolicia,
  kActaAlcaldiaPlanta,
  kActaAlcaldiaEstacionPolicia,
];

/// Nombre legible del tipo de acta.
///
/// El identificador se guarda; la etiqueta se muestra. Antes el desplegable
/// pintaba el identificador crudo, que es la misma falta que en las áreas.
String etiquetaTipoActa(String? tipo) {
  switch (tipo) {
    case kActaRegular:
      return 'Regular';
    case kActaSeguimiento:
      return 'Seguimiento';
    case kActaInfraestructura:
      return 'Infraestructura';
    case kActaEstacionPolicia:
      return 'Estación de policía';
    case kActaAlcaldiaPlanta:
      return 'Alcaldía · Planta de preparación y ensamble';
    case kActaAlcaldiaEstacionPolicia:
      return 'Alcaldía · Estación de policía';
    default:
      return tipo == null || tipo.trim().isEmpty ? 'Sin tipo' : tipo;
  }
}

/// Familia de reglas de subsanación a la que pertenece un tipo de acta.
///
/// REGULAR y SEGUIMIENTO evalúan el MISMO catálogo —se distinguen solo por el
/// propósito de la visita—, así que comparten reglas. Mantener dos copias
/// obligaría a editar cada numeral dos veces, y bastaría olvidar una para que
/// el mismo hallazgo se asignara distinto según el tipo de visita.
///
/// Las demás actas son formularios propios y responden por sus propias reglas.
String familiaReglasActa(String? tipoActa) {
  final tipo = (tipoActa ?? '').trim().toUpperCase();
  switch (tipo) {
    case kActaInfraestructura:
      return kActaInfraestructura;
    case kActaEstacionPolicia:
      return kActaEstacionPolicia;
    case kActaAlcaldiaPlanta:
      return kActaAlcaldiaPlanta;
    case kActaAlcaldiaEstacionPolicia:
      return kActaAlcaldiaEstacionPolicia;
    default:
      // REGULAR, SEGUIMIENTO, vacío o desconocido caen en la familia regular,
      // que es la única que existía cuando se guardaron las reglas actuales.
      return kActaRegular;
  }
}

/// Actas cuyas reglas se editan en el Maestro.
///
/// SEGUIMIENTO no aparece: comparte reglas con REGULAR por ser el mismo
/// catálogo, y ofrecerlo aparte haría creer que se está editando otra cosa.
const List<String> kActasConMaestro = [
  kActaRegular,
  kActaInfraestructura,
  kActaEstacionPolicia,
  kActaAlcaldiaPlanta,
  kActaAlcaldiaEstacionPolicia,
];

/// Una sección del acta, con sus aspectos en el orden impreso.
class SeccionActa {
  final int numero;
  final String nombre;
  final List<String> aspectos;

  const SeccionActa({
    required this.numero,
    required this.nombre,
    required this.aspectos,
  });
}

/// Numeral de un aspecto: `sección.posición`, empezando en 1, igual que el
/// papel.
String numeralDeAspecto(int seccion, int indiceCeroBasado) =>
    '$seccion.${indiceCeroBasado + 1}';

/// Actas cuyo catálogo vive aquí. El acta regular NO está: la suya se arma
/// desde `kInterventoriaItemsActaPorCategoria`.
const Map<String, List<SeccionActa>> kSeccionesPorTipoActa = {
  kActaInfraestructura: kSeccionesActaInfraestructura,
  kActaEstacionPolicia: kSeccionesActaEstacionPolicia,
  kActaAlcaldiaPlanta: kSeccionesActaAlcaldiaPlanta,
  kActaAlcaldiaEstacionPolicia: kSeccionesActaAlcaldiaEstacionPolicia,
};

/// ¿El tipo de acta trae su catálogo propio en este archivo?
bool tieneCatalogoPropio(String? tipoActa) =>
    kSeccionesPorTipoActa.containsKey((tipoActa ?? '').trim().toUpperCase());

// ───────────────────────────────────────────────────────────────────────────
// INSTALACIONES FÍSICAS Y SANITARIAS - INFRAESTRUCTURA
//
// Una sola sección, 28 aspectos. Transcrito del formato versión 2025-05-30.
//
// OJO: no es la sección de instalaciones físicas del acta regular, que tiene
// 17 aspectos y otra redacción. Antes el tipo INFRAESTRUCTURA reutilizaba esa,
// de modo que quien registraba un acta de infraestructura calificaba una lista
// que no era la suya.
// ───────────────────────────────────────────────────────────────────────────
const List<SeccionActa> kSeccionesActaInfraestructura = [
  SeccionActa(
    numero: 1,
    nombre: 'Instalaciones físicas y sanitarias - Infraestructura',
    aspectos: [
      'El servicio de alimentación está ubicado en un lugar alejado de focos '
          'de insalubridad, malezas y aguas estancada que representen riesgos '
          'potenciales para la contaminación del alimento, la salud y el '
          'bienestar de la PPL.',
      'Se realizan acciones para controlar focos de insalubridad, malezas y '
          'aguas estancadas en las áreas que son compartidas y comunes con el '
          'INPEC, que podrían afectar el servicio de alimentación.',
      'El área de producción de alimentos debe poseer una adecuada separación '
          'física de aquellas áreas donde se realizan operaciones de producción '
          'susceptibles de ser contaminadas por otras operaciones o medios de '
          'contaminación presentes en las zonas cercanas.',
      'Existe clara separación física entre las áreas de recepción de materia '
          'prima, almacenamiento, producción, pre alistamiento, ensamble y '
          'distribución (si aplica). Estas tienen dimensiones proporcionales al '
          'volumen de producción.',
      'Existe una secuencia lógica y/o flujo de proceso de las áreas desde la '
          'recepción de materias primas e insumos hasta el servicio y entrega '
          'del producto terminado, evitando retrasos. Se aplica existiendo una '
          'entrada y una salida.',
      'Los puntos de instalación de equipos se encuentran ubicados a una '
          'distancia que garantiza el acceso para la inspección, mantenimiento, '
          'limpieza y desinfección.',
      'La edificación e instalaciones están construidos de manera que se evita '
          'el estancamiento de agua y facilita la operación de limpieza, '
          'desinfección y desinsectación.',
      'Existe en el servicio de alimentación el espacio adecuado para la '
          'instalación de los equipos ofertados. Si se presentan limitaciones y '
          'novedades relacionadas con el espacio deberán estar certificadas por '
          'el INPEC en el acta de empalme a los 15 días calendario sobre las '
          'limitaciones encontradas, respaldado por las medidas y estrategias '
          'tomadas por el contratista.',
      'Las bodegas y/o cuartos de almacenamiento son proporcionales al volumen '
          'de insumos manejados por el servicio de alimentación (tener en '
          'cuenta parte diario y capacidad de almacenamiento para mínimo 2 días '
          'mínimo de producción), disponiendo además de espacios libres para la '
          'circulación de personas, traslado de materiales, realizar limpieza '
          'adecuada y el mantenimiento de las áreas respectivas.',
      'Los techos están diseñados y construidos en material sanitario y '
          'permite la aplicación de procedimientos de limpieza y desinfección.',
      'Las ventanas y otras aberturas están construidas de manera que evitan '
          'acumulación de polvo, suciedad y facilitan la limpieza y '
          'desinfección. Sus marcos son de material sanitario y se encuentran '
          'protegidas con mallas anti insecto o angeos que impiden el ingreso '
          'de plagas, de material no corrosivo. Los vidrios de las ventanas '
          'cuentan con protección para evitar contaminación en caso de ruptura '
          '(si aplica).',
      'Los pisos están construidos en material resistente, no poroso, '
          'impermeable, con acabados libres de grietas, no deslizantes y/o '
          'defectos que dificulten su limpieza, desinfección y mantenimiento '
          'sanitario.',
      'Los pisos en áreas de trabajo cuentan con pendiente y drenajes para '
          'facilitar la evacuación de agua producto de actividades de limpieza '
          'y desinfección.',
      'Las paredes deben ser lisas y estar construidas en material resistente, '
          'impermeable, no absorbente, de fácil limpieza, desinfección.',
      'Las uniones entre pared-piso y pared-pared son de forma redondeada para '
          'impedir acumulación de suciedad y facilita su limpieza y '
          'desinfección (media-caña).',
      'Las puertas del servicio de alimentación son de material sanitario, de '
          'superficie lisa, no absorbente, de fácil limpieza y desinfección y '
          'de preferencia con apertura hacia afuera, ajuste hermético.',
      'Se cuenta con vestidores con lockers para el personal manipulador y '
          'administrativo, en cantidad suficiente de acuerdo con el número del '
          'personal y esta se encuentra alejada del área de producción.',
      'El establecimiento cuenta con iluminación, ventilación y se encuentran '
          'protegidas y funcionando para las actividades propias del servicio '
          'de alimentación.',
      'El sistema eléctrico se encuentra en funcionamiento, adecuado estado y '
          'no generan focos de contaminación.',
      'Existe suficiente abastecimiento de agua con calidad potable para '
          'garantizar las actividades propias del servicio de alimentación.',
      'Existen suficientes sistemas de evacuación de aguas residuales y se '
          'encuentran protegidos (sifones o rejillas).',
      'Se cuenta con trampa de grasa o con espacio para instalación de trampa '
          'de grasa que garantice la disposición de residuos líquidos (si '
          'aplica).',
      'Se cuenta con un tanque de almacenamiento de agua potable, protegido y '
          'exclusivo para el servicio de alimentación, con la capacidad para '
          'atender como mínimo las necesidades correspondientes a un día de '
          'producción.',
      'El servicio de alimentación cuenta con servicios sanitarios, lavamanos '
          'en lo posible accionados mecánicamente, separados por sexo, en buen '
          'estado y funcionamiento y estos se encuentran alejados del área de '
          'producción de alimentos.',
      'El área de proceso y/o de producción del servicio de alimentación '
          'cuenta con lavamanos de accionamiento no manual.',
      'Existe un espacio físico exclusivo para el depósito temporal de los '
          'residuos sólidos, protegido, ventilado, señalizado, alejado de las '
          'áreas de producción y distribución, en adecuadas condiciones físicas '
          'que faciliten su limpieza y desinfección.',
      'El servicio de alimentación se encuentra separado del área de proyectos '
          'productivos (si aplica).',
      'El Servicio de alimentación cuenta con el mínimo de áreas físicas según '
          'lo establecido en Oferta Técnica Mínima (OTM), de acuerdo al número '
          'de PPL. En caso de que se cuente con la limitación de espacio para '
          'ubicar alguna de las áreas el contratista presenta el informe '
          'soportado manifestando las limitaciones para validación de la USPEC '
          'y/o Interventoría.',
    ],
  ),
];

// ───────────────────────────────────────────────────────────────────────────
// ESTACIONES DE POLICÍA (EP) - UNIDADES TÁCTICAS (UT) - URI
//
// Cinco secciones, 25 aspectos. Transcrito del formato versión 2025-05-30.
// ───────────────────────────────────────────────────────────────────────────
const List<SeccionActa> kSeccionesActaEstacionPolicia = [
  SeccionActa(
    numero: 1,
    nombre: 'Instalaciones físicas',
    aspectos: [
      'Durante el almacenamiento temporal se garantizan las condiciones '
          'higiénicas del producto terminado (alejados de focos de '
          'contaminación, superficies limpias y sin contacto directo con el '
          'piso).',
      'Las canastillas y/o estibas usados durante el almacenamiento temporal '
          'se encuentran limpias y en buen estado (si aplica).',
    ],
  ),
  SeccionActa(
    numero: 2,
    nombre: 'Personal manipulador de alimentos',
    aspectos: [
      'Los manipuladores de alimentos utilizan la dotación limpia, en buen '
          'estado, de color claro y cumple con las especificaciones de la norma '
          'legal vigente. Los manipuladores de alimentos conocen y aplican las '
          'BPM.',
      'Los manipuladores de alimentos cuentan con certificado médico (apto '
          'para manipular alimentos) y certificado de manipulación en BPM '
          'vigente.',
      'Se evidencia durante la visita, el recurso humano adicional ofertado - '
          'Supervisor de Calidad y Estaciones de Policía y/o Unidades Tácticas '
          'y/o CRM. (Si aplica) (CUMPLE - NO OBSERVADO).',
    ],
  ),
  SeccionActa(
    numero: 3,
    nombre: 'Condiciones de transporte de producto terminado',
    aspectos: [
      'El vehículo transportador cumple con la siguiente documentación: '
          'Concepto sanitario favorable de la Dirección Territorial de Salud '
          'con fecha de expedición no mayor a un año, tarjeta de Propiedad del '
          'Vehículo, SOAT, certificado de Revisión tecnomecánica y de gases (si '
          'aplica). En el caso de uso de motocicleta, el parte es igual o menor '
          'a 20 raciones por tiempo de comida, y esta cumple con las '
          'condiciones mínimas de inocuidad de alimentos, cuenta con '
          'certificado por la autoridad sanitaria territorial competente. (En '
          'caso de que la entidad territorial de salud o ente departamental no '
          'certifique, se informa a la entidad y/o interventoría).',
      'Los vehículos transportadores de alimentos llevan en su exterior en '
          'forma claramente visible: TRANSPORTE DE ALIMENTOS.',
      'Los vehículos transportadores de alimentos se encuentran en adecuadas '
          'condiciones físicas y de higiene, cuenta con recipientes, '
          'canastillas o implementos de material adecuado que eviten '
          'disponerlos sobre el piso del vehículo. Las medidas de '
          'almacenamiento durante el transporte evitan el daño mecánico del '
          'empaque y la alteración en la calidad e inocuidad del alimento, de '
          'acuerdo a lo establecido en la OTM.',
      'Durante el transporte de los alimentos se diligencian las planillas de '
          'registro de la temperatura de los mismos, de modo que garantice la '
          'naturaleza de los alimentos (refrigerados y/o calientes). Nota: en '
          'aquellos casos en los que la unidad de transporte no cuente con un '
          'sistema de monitoreo interno de temperatura, se recurre al uso de un '
          'termómetro de punzón debidamente calibrado, con el fin de garantizar '
          'el control adecuado de las condiciones térmicas durante el '
          'transporte.',
      'Se cuenta con un plan de rutas con placa del vehículo y rangos de '
          'horarios para el seguimiento en los puntos de entrega.',
    ],
  ),
  SeccionActa(
    numero: 4,
    nombre: 'Recepción del producto terminado',
    aspectos: [
      'El contratista cumple con el horario establecido para la entrega del '
          'producto terminado de acuerdo a lo estipulado en la OTM. Nota: para '
          'la entrega de alimentación extramural a la PPL recluida, los '
          'horarios de entrega de cada tiempo de comida no deben excederse de '
          'una hora posterior a los horarios de entrega del lugar de suministro '
          '(Eron - Planta externa). Detallar las causas que generan las '
          'desviaciones en los horarios atribuibles al contratista (si aplica).',
      'El ciclo de menús o sus actualizaciones se encuentra socializado y/o '
          'informado a los responsables de la UT o a quien se delegue en sus '
          'funciones para tal fin (fecha de inicio del suministro, horarios de '
          'entrega para cada tiempo de comida).',
      'El contratista suministra la totalidad de los componentes del menú '
          'verificado (faltantes - no entrega).',
      'El contratista cumple con el menú verificado según lo establecido en la '
          'minuta patrón y la OTM (intercambios). Nota 2: se permitirán '
          'intercambios previa información por correo electrónico al supervisor '
          'y/o interventor (según el procedimiento establecido), sin requerir '
          'aprobación de la USPEC y/o interventor, así: hasta cuatro '
          'intercambios de fruta en la semana, entre fruta entera y fruta de '
          'jugo; hasta cuatro intercambios de verduras a la semana; hasta '
          'cuatro intercambios de proteico a la semana (no se podrá reemplazar '
          'por proteínas de origen vegetal); hasta cuatro intercambios de '
          'tubérculo a la semana. Nota 5: se permitirá el intercambio en el '
          'tipo de preparación de algunos componentes del ciclo de menú diario, '
          'máximo cuatro veces por semana, para proteína, verdura o tubérculo, '
          'siempre y cuando corresponda únicamente a la forma de preparación y '
          'no al intercambio de su variedad, para lo cual se remite un correo '
          'electrónico a la USPEC y/o interventoría informando tal situación.',
      'El contratista cumple con los gramajes de las preparaciones del menú '
          'verificado, de acuerdo a lo estipulado en la OTM (verificar rotulado '
          'contenido neto alimentos pre-empacados).',
      'El contratista cumple con las especificaciones técnicas de cada uno de '
          'los componentes del menú, de acuerdo a lo estipulado en la OTM y '
          'aprobado por la USPEC.',
      'Los alimentos suministrados se encuentran libres de algún tipo de '
          'contaminación (cuantificar y describir) y aquellos que cuentan con '
          'empaque primario, cumplen con la normatividad sanitaria en relación '
          'al rotulado.',
      'La bebida cumple con las características y rotación estipuladas en la '
          'OTM. Especifique la bebida suministrada.',
      'Cumple con la calidad organoléptica del menú verificado. En caso de '
          'evidenciar incumplimiento, especificar temperatura de recibo si es '
          'menor a 60 °C y/o mayor a 4 +/- 2 °C.',
      'Se han presentado renuncias a la alimentación y/o a las dietas; existe '
          'registro o documento escrito en el que conste que el mismo PPL '
          'exonera de cualquier responsabilidad a la USPEC, al contratista y al '
          'INPEC. El documento debe estar firmado por el PPL, un profesional '
          'del área de sanidad del establecimiento y, para el caso de renuncia '
          'a dietas, por el nutricionista del contratista.',
      'El contratista entrega los alimentos directamente al responsable del '
          'CPAMSE, UT o Estación de policía o a quien se delegue en sus '
          'funciones para tal fin.',
    ],
  ),
  SeccionActa(
    numero: 5,
    nombre: 'Distribución del producto terminado',
    aspectos: [
      'Los alimentos son entregados en empaques individuales previamente '
          'ensamblados y sellados. Nota 1: en caso de que el contratista '
          'utilice fiambreras para la entrega de la alimentación en estaciones '
          'de policía deberá garantizar el adecuado proceso de limpieza y '
          'desinfección, mediante la presentación de un protocolo para '
          'aprobación previa de la USPEC. Nota 2: el contratista podrá '
          'presentar para revisión y aprobación estrategias de distribución de '
          'acuerdo con las condiciones propias de la operación, que permitan '
          'una entrega en cumplimiento de los horarios y condiciones de las '
          'estaciones de policía, teniendo en cuenta la normativa aplicable y '
          'garantizando la calidad e inocuidad de los alimentos, además de su '
          'presentación y entrega individual a cada PPL. Nota 3: teniendo en '
          'cuenta la logística de distribución de los ERONES y Estaciones de '
          'Policía, URIS y UT donde se requiera trasladar la alimentación desde '
          'el servicio de alimentación o planta externa, los componentes '
          'líquidos (jugos) podrán embalarse en FONDOS para la respectiva '
          'distribución y suministro a la PPL en cada lugar, a fin de '
          'garantizar las condiciones de seguridad y calidad de la alimentación '
          'durante el transporte. Se cuenta con autorización.',
      'El contratista hace entrega de los utensilios básicos para el consumo '
          'de los alimentos del PPL y son de material apto para tal fin.',
      'El contratista garantiza la entrega de dietas a la PPL en las '
          'Estaciones de Policía, previa al procedimiento de la prescripción '
          'dietaria, a través del nutricionista del contratista mediante la '
          'remisión del médico tratante. Los recipientes de dietas están '
          'marcados con el nombre de la PPL y tipo de dieta conforme a lo '
          'establecido en la OTM.',
      'En caso de presentarse algún PPL con diagnóstico de inmunosupresión o '
          'enfermedades infectocontagiosas, en la entrega de la alimentación se '
          'usa empaque en material desechable que cumpla con lo establecido en '
          'la Resolución 683 de 2012 (si aplica).',
    ],
  ),
];

// ───────────────────────────────────────────────────────────────────────────
// ALCALDÍA MAYOR DE BOGOTÁ - PLANTA DE PREPARACIÓN Y ENSAMBLE
//
// Formato de verificación diaria para CDT, versión 202508. El documento
// recibido el 18 sep 2026 contiene 8 secciones y 63 aspectos. No se reutiliza
// REGULAR: aunque comparte temas, la numeración y los aspectos son distintos.
// ───────────────────────────────────────────────────────────────────────────
const List<SeccionActa> kSeccionesActaAlcaldiaPlanta = [
  SeccionActa(
    numero: 1,
    nombre: 'Localización, instalaciones físicas y sanitarias',
    aspectos: [
      'El contratista mantiene los accesos y alrededores limpios, libres de acumulación de basuras, estancamiento de aguas u otras fuentes de contaminación para el alimento.',
      'Se cuenta con las áreas establecidas en los documentos contractuales, señalizadas, operativas y usadas para la actividad prevista.',
      'Las áreas se encuentran en adecuado estado de orden, limpieza, desinfección e iluminación, y las lámparas están protegidas en caso de rotura.',
      'Cuenta con área debidamente señalizada para el almacenamiento de alimentos o materias primas clasificadas como productos no conformes.',
      'El contratista garantiza un área exclusiva para ensamble de las raciones.',
      'Las instalaciones sanitarias están alejadas del área de producción, limpias y dotadas con elementos de higiene personal y equipos para el secado de manos.',
    ],
  ),
  SeccionActa(
    numero: 2,
    nombre: 'Almacenamiento de materias primas e insumos',
    aspectos: [
      'Se cuenta con proyección del plan de compras de acuerdo con el promedio del parte diario y las cantidades establecidas en la minuta patrón, análisis nutricional y proveedores ofertados.',
      'Existen fichas técnicas de las materias primas acorde con el listado de proveedores ofertados.',
      'Las materias primas e insumos se reciben y almacenan en adecuadas condiciones de higiene y temperatura, con rotación PEPS y registros actualizados.',
      'El contratista recibe materias primas aplicando criterios de aceptación y rechazo y diligencia los formatos establecidos.',
      'No se evidencian alimentos o preparaciones prohibidas ni aditivos o saborizantes artificiales no permitidos.',
      'Los alimentos presentan adecuadas condiciones de higiene, fechas de vencimiento vigentes y ausencia de contaminación biológica, química o física.',
      'Las materias primas se almacenan separadas físicamente, en empaques de primer uso y con adecuadas condiciones de mantenimiento, limpieza y desinfección.',
      'Las materias primas que requieren cadena de frío se almacenan de acuerdo con su naturaleza, en refrigeración o congelación.',
      'Se cumplen las distancias perimetrales en el almacenamiento de alimentos y la organización permite limpiar y verificar el área.',
      'Se aplica el método PEPS y los productos se encuentran debidamente identificados.',
      'Los alimentos cumplen con etiquetado y rotulado conforme con la normativa vigente y sus empaques están en adecuadas condiciones.',
      'Se mantienen actualizados los registros de recepción, entradas y salidas, producto no conforme y control de temperatura de equipos.',
    ],
  ),
  SeccionActa(
    numero: 3,
    nombre: 'Equipos, utensilios y menaje',
    aspectos: [
      'Se cuenta con los equipos mínimos requeridos y con capacidad, suficiencia, volumen y funcionalidad acordes con las necesidades del servicio.',
      'Los equipos son de materiales inertes y resistentes, fáciles de desarmar, limpiar y desinfectar, y se encuentran en buen estado y adecuadas condiciones de higiene.',
      'Los equipos se encuentran en adecuadas condiciones de mantenimiento y funcionamiento, con soportes de mantenimientos preventivos o correctivos.',
      'Los utensilios y menaje son de materiales inertes y resistentes, fáciles de desarmar, limpiar y desinfectar, y se encuentran en buen estado.',
      'Cuenta con equipos de medición básicos requeridos, documentados y en adecuadas condiciones de limpieza, desinfección y funcionamiento.',
    ],
  ),
  SeccionActa(
    numero: 4,
    nombre: 'Condiciones de producción y producto terminado',
    aspectos: [
      'Se cumplen las temperaturas de seguridad de acuerdo con la naturaleza de la preparación: alimentos calientes mayores a 60 °C y fríos no mayores a 4 °C +/- 2 °C.',
      'Se garantizan temperaturas de seguridad durante alistamiento, producción, ensamble, distribución y reparto, evitando proliferación de microorganismos.',
      'Se cuenta con utensilios estandarizados para garantizar el gramaje de cada componente suministrado.',
      'Se garantiza el servido del producto terminado y las dietas bajo condiciones que evitan cruce de flujos y contaminación cruzada.',
      'Las raciones terapéuticas para PPL con inmunosupresión o enfermedades infectocontagiosas se suministran en empaque marcado y rotulado.',
      'Diariamente se toman y conservan durante 72 horas tres muestras de las preparaciones de todos los tiempos de comida.',
      'Se reemplazan en su totalidad los alimentos devueltos por la PPL, sin reelaboración, reproceso, corrección o reensamble.',
    ],
  ),
  SeccionActa(
    numero: 5,
    nombre: 'Características de los alimentos, menús, gramajes y dietas',
    aspectos: [
      'Existe cumplimiento de la rotación del ciclo de menú y se verifica mediante registros de producción y contramuestras.',
      'El contratista suministra la totalidad de los componentes del menú verificado.',
      'El profesional nutricionista solicita y justifica los intercambios con mínimo 12 horas de anticipación y dentro del mismo grupo de alimentos.',
      'Las preparaciones cumplen con los ingredientes indicados en los documentos nutricionales que componen la preparación de cada tiempo de comida.',
      'No se suministran alimentos o preparaciones prohibidas ni aditivos o saborizantes artificiales no permitidos.',
      'El contratista cumple con los gramajes de las preparaciones del menú y de las dietas terapéuticas entregadas.',
      'El contratista cumple con la calidad organoléptica del menú verificado.',
      'Se suministran los refrigerios nocturnos según las condiciones contractuales y el ciclo de menús.',
      'Se suministra alimentación diferencial por convicción religiosa según la aprobación establecida, cuando aplica.',
      'Se suministra el menú especial para días festivos en las fechas establecidas y con acta de aprobación de la interventoría.',
      'Se entregan refrigerios a la PPL que sale de remisión conforme con las características y gramaje establecidos.',
      'Se entregan dietas terapéuticas a la PPL que las requiere, con las condiciones definidas y el formato firmado correspondiente.',
      'Cada ración terapéutica se encuentra rotulada de manera legible e indeleble con PPL, centro de detención y tipo de dieta.',
      'El nutricionista dietista prescribe la dieta de cada PPL a partir de la interconsulta médica y deja constancia en los documentos correspondientes.',
    ],
  ),
  SeccionActa(
    numero: 6,
    nombre: 'Personal manipulador de alimentos',
    aspectos: [
      'El contratista cumple con el personal mínimo requerido y cuenta con soportes de asistencia o justificación de ausencia.',
      'El contratista suministra cada cuatro meses, o antes por deterioro, la dotación completa al personal asignado.',
      'No se permite el ingreso de personal o visitantes sin la debida dotación.',
      'Los manipuladores utilizan la dotación completa, limpia, en buen estado y de acuerdo con la normativa legal vigente.',
      'Los manipuladores cumplen hábitos de higiene personal y prácticas higiénicas durante la operación.',
      'Se observa lavado de manos con agua y jabón desinfectante antes de comenzar y en cada cambio de actividad.',
      'El personal manipulador no presenta infecciones que puedan contaminar los alimentos y, si se presentan, existen registros de seguimiento.',
      'Los manipuladores cuentan con certificado médico vigente que acredita su aptitud para manipular alimentos.',
      'Se implementa y soporta un plan de capacitación continua de mínimo diez horas.',
    ],
  ),
  SeccionActa(
    numero: 7,
    nombre: 'Condiciones de saneamiento',
    aspectos: [
      'Las actividades se desarrollan de manera secuencial desde la recepción de materias primas hasta la entrega del producto terminado y las áreas están señalizadas.',
      'Paredes, techos, pisos, mesones, ventanas, puertas y barreras se encuentran limpios, sin contaminación y sin estancamiento de agua.',
      'El contratista garantiza la limpieza y desinfección de equipos y utensilios del servicio de alimentación.',
      'Los productos químicos de limpieza y desinfección tienen fichas técnicas, están rotulados y se almacenan en un espacio ventilado, identificado y protegido.',
      'Los elementos e insumos de aseo están rotulados, organizados y se usan de forma que evita contaminación.',
      'El contratista garantiza la potabilidad del agua empleada en los procesos del servicio de alimentos.',
      'Se realizan diariamente análisis de pH y cloro residual y existen registros actualizados.',
      'Se cuenta con recipientes identificados, en buen estado, con tapa y bolsa para la disposición de residuos sólidos.',
    ],
  ),
  SeccionActa(
    numero: 8,
    nombre: 'Aseguramiento y control de la calidad',
    aspectos: [
      'Para los equipos de frío se lleva control y registro de temperatura en un lugar visible.',
      'Se cuenta con un programa de trazabilidad definido e implementado que permite analizar cada etapa productiva.',
    ],
  ),
];

// ───────────────────────────────────────────────────────────────────────────
// ALCALDÍA MAYOR DE BOGOTÁ - ESTACIONES DE POLICÍA / CDT
//
// Formato de transporte y entrega, versión 202508. Es distinto del acta PEC
// ESTACION_POLICIA ya existente: tiene 7 secciones y 36 aspectos.
// ───────────────────────────────────────────────────────────────────────────
const List<SeccionActa> kSeccionesActaAlcaldiaEstacionPolicia = [
  SeccionActa(
    numero: 1,
    nombre: 'Cumplimiento de horario de entrega',
    aspectos: [
      'El contratista cumple con el horario establecido para la entrega de las raciones alimentarias según las especificaciones técnicas.',
    ],
  ),
  SeccionActa(
    numero: 2,
    nombre: 'Condiciones del vehículo transportador',
    aspectos: [
      'Se cuenta con tarjeta de propiedad, SOAT y certificado de revisión técnico-mecánica y de gases vigente, cuando aplica.',
      'El vehículo cuenta con concepto sanitario favorable o favorable con requerimientos y, cuando corresponde, presenta plan de mejoramiento.',
      'El conductor del vehículo cuenta con licencia de conducción vigente.',
      'El vehículo está identificado para transporte de alimentos y cumple las condiciones de higiene de la normativa sanitaria vigente.',
      'Cuenta con recipientes, canastillas o estibas limpias y en adecuado estado, evitando disponer alimentos directamente sobre el piso.',
      'Cuenta con kit de limpieza y desinfección de áreas y utensilios y con los elementos de protección personal requeridos.',
      'Durante el transporte se evita el daño mecánico del empaque y la alteración de la calidad e inocuidad de los alimentos.',
      'Cuenta con elementos adecuados para el transporte y entrega higiénico-sanitaria de los alimentos.',
    ],
  ),
  SeccionActa(
    numero: 3,
    nombre: 'Condiciones de almacenamiento',
    aspectos: [
      'El almacenamiento temporal garantiza condiciones higiénicas del producto terminado.',
      'Cuenta con termómetro certificado y gramera calibrada, transportados preservando su funcionamiento e inocuidad.',
      'Se realiza seguimiento y registro actualizado de temperatura de los alimentos.',
    ],
  ),
  SeccionActa(
    numero: 4,
    nombre: 'Cantidades',
    aspectos: [
      'Cumple con las cantidades de raciones programadas y entregadas para el establecimiento verificado.',
      'Cumple con la cantidad de dietas terapéuticas programadas para el establecimiento.',
      'Las raciones se entregan con la totalidad de componentes conforme con el menú establecido.',
    ],
  ),
  SeccionActa(
    numero: 5,
    nombre: 'Condiciones de entrega',
    aspectos: [
      'Durante el descargue y entrega se implementan buenas prácticas de manufactura por parte del personal manipulador.',
      'Las canastillas, estibas o mesas para almacenamiento temporal y distribución se encuentran limpias y en buen estado.',
      'Las raciones se empacan o envasan en empaques adecuados y se entregan los utensilios básicos de material apto.',
      'Las raciones entregadas están libres de contaminación y, ante devoluciones, se reponen en un tiempo no mayor a dos horas.',
      'Cumple con minuta patrón, ciclo de menús, análisis nutricional e intercambios conforme con los documentos contractuales.',
      'Las dietas se entregan en recipientes identificados y existe soporte para renuncias o no entrega.',
      'El ciclo de menús y los horarios de entrega están socializados con los responsables del CDT.',
      'Las temperaturas de los alimentos se encuentran dentro de los rangos establecidos por la normativa vigente.',
      'Se cumple con la calidad organoléptica del menú verificado.',
      'Se cumple con los gramajes establecidos de las preparaciones del menú verificado.',
      'El plan de rutas corresponde al aprobado por la supervisión o interventoría.',
      'Los alimentos empacados y envasados cumplen la normativa vigente y están rotulados cuando aplica.',
    ],
  ),
  SeccionActa(
    numero: 6,
    nombre: 'Personal manipulador',
    aspectos: [
      'El personal manipulador cuenta con exámenes de reconocimiento médico vigentes que acreditan aptitud para manipular alimentos.',
      'Se cuenta con soporte de capacitación anual de diez horas en buenas prácticas de manufactura.',
      'Los manipuladores cuentan con dotación completa, limpia, en buen estado y conforme con la normativa vigente.',
      'Durante la visita se evidencia el recurso humano mínimo requerido contractualmente.',
    ],
  ),
  SeccionActa(
    numero: 7,
    nombre: 'Otras condiciones de la contratación',
    aspectos: [
      'El contratista entrega los alimentos directamente a la PPL, al responsable del CDT o a quien se delegue.',
      'El formato de entrega de raciones CDT Bogotá es diligenciado y firmado en cada tiempo de alimentación.',
      'El contratista garantiza el manejo adecuado de residuos sólidos y líquidos generados por el suministro.',
      'El almacenamiento temporal de residuos se realiza en canecas grandes, rotuladas, con tapa y en buen estado.',
      'La recolección y disposición final de residuos está a cargo de una empresa autorizada y evita acumulación o fuentes de contaminación.',
    ],
  ),
];
