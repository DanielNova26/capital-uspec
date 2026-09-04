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
