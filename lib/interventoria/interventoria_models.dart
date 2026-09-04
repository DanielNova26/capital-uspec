import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/subcentros_costo.dart';
import 'interventoria_actas_catalogo.dart';
import 'interventoria_numerales_catalogo.dart';

const String kInterventoriaAppId = 'interventoriadashboard';

const String kRolInterventoriaAdmin = 'admin_interventoria';
const String kRolInterventoriaRegistrador = 'registrador_interventoria';
const String kRolInterventoriaRevisor = 'revisor_interventoria';
const String kRolInterventoriaGerente = 'gerente_interventoria';
const String kRolInterventoriaDirectivo = 'directivo_interventoria';
const String kRolInterventoriaConsulta = 'consulta_interventoria';

/// Roles activos asignables desde el panel de administración.
/// consulta_interventoria deshabilitado por ahora.
const List<String> kInterventoriaRoles = [
  kRolInterventoriaAdmin,
  kRolInterventoriaRegistrador,
  kRolInterventoriaRevisor,
  kRolInterventoriaGerente,
  kRolInterventoriaDirectivo,
];

const Map<String, String> kInterventoriaRoleLabels = {
  kRolInterventoriaAdmin: 'Administrador',
  kRolInterventoriaRegistrador: 'Registrador',
  kRolInterventoriaRevisor: 'Revisor',
  kRolInterventoriaGerente: 'Gerente',
  kRolInterventoriaDirectivo: 'Directivo',
  kRolInterventoriaConsulta: 'Consulta', // deshabilitado
};

/// Fase 1 — Admin y Registrador suben PDF + puntajes.
const Set<String> kInterventoriaRolesFase1 = {
  kRolInterventoriaAdmin,
  kRolInterventoriaRegistrador,
};

/// Fase 2 — pueden completar/revisar el acta con el visor de PDF.
const Set<String> kInterventoriaRolesFase2 = {
  kRolInterventoriaAdmin,
  kRolInterventoriaRevisor,
  kRolInterventoriaGerente,
  kRolInterventoriaDirectivo,
};

/// Unión de Fase 1 + Fase 2 — tienen permisos de escritura en el módulo.
const Set<String> kInterventoriaRolesEscritura = {
  kRolInterventoriaAdmin,
  kRolInterventoriaRegistrador,
  kRolInterventoriaRevisor,
  kRolInterventoriaGerente,
  kRolInterventoriaDirectivo,
};

const Set<String> kInterventoriaRolesDirectivos = {
  kRolInterventoriaAdmin,
  kRolInterventoriaGerente,
  kRolInterventoriaDirectivo,
};

const Set<String> kInterventoriaRolesAprobadoresEliminacion = {
  kRolInterventoriaAdmin,
  kRolInterventoriaRevisor,
  kRolInterventoriaGerente,
  kRolInterventoriaDirectivo,
};

bool puedeAprobarEliminacionInterventoria(String rol) =>
    kInterventoriaRolesAprobadoresEliminacion.contains(rol);

/// El maestro contiene la matriz completa de responsabilidades y se reserva
/// al administrador funcional del módulo.
bool puedeConsultarMaestroSubsanaciones(String rol) =>
    rol == kRolInterventoriaAdmin;

/// La aprobación pertenece a la persona resuelta por la regla del numeral,
/// no al rol genérico ni a quien creó la tarea.
bool puedeAprobarHallazgo(InterventoriaHallazgo hallazgo, String userId) =>
    hallazgo.aprobadorId.trim().isNotEmpty &&
    hallazgo.aprobadorId.trim() == userId.trim();

/// La bandeja de asignación es operativa: los cerrados siguen en histórico y
/// análisis, pero no deben mezclarse con el trabajo pendiente.
bool debeAparecerEnTableroAsignacion(InterventoriaHallazgo hallazgo) =>
    !hallazgo.isSubsanado;

const List<InterventoriaCategoria> kInterventoriaCategorias = [
  InterventoriaCategoria('conceptoSanitario', 'Concepto Sanitario'),
  InterventoriaCategoria('horario', '1. Horario'),
  InterventoriaCategoria('instalacionesFisicas', '2. Instalaciones fisicas'),
  InterventoriaCategoria('almacenamiento', '3. Almacenamiento'),
  InterventoriaCategoria('equipos', '4. Equipos'),
  InterventoriaCategoria(
    'condicionesProduccion',
    '5. Condiciones de produccion',
  ),
  InterventoriaCategoria(
    'caracteristicasAlimentos',
    '6. Caracteristicas de los alimentos',
  ),
  InterventoriaCategoria('personalManipulador', '7. Personal manipulador'),
  InterventoriaCategoria(
    'condicionesSaneamiento',
    '8. Condiciones de saneamiento',
  ),
  InterventoriaCategoria(
    'condicionesTransporte',
    '9. Condiciones de transporte',
  ),
  InterventoriaCategoria(
    'aseguramientoControlCalidad',
    '10. Aseguramiento y control de calidad',
  ),
  InterventoriaCategoria(
    'seguridadSaludTrabajo',
    '11. Seg. y Salud en el trabajo',
  ),
];

// Cada ítem va numerado igual que la columna "#" del acta original (PDF),
// con el texto COMPLETO del "ASPECTO A EVALUAR" — sin resumir — para que
// quien registre observaciones identifique exactamente a cuál corresponde
// y no haya confusión entre ítems. Los saltos de numeración (p. ej.
// almacenamiento empieza en 2, personalManipulador salta del 8 al 10)
// son fieles al acta original, no un error.
const Map<String, List<String>> kInterventoriaItemsActaPorCategoria = {
  // La sección 1 del acta ("CUMPLIMIENTO DE HORARIO Y CONCEPTO HIGIÉNICO
  // SANITARIO") se registra en dos tarjetas, porque el acta captura dos cosas
  // distintas: la hora de entrega del servicio y el concepto sanitario del
  // ente territorial. Por eso 1.1 vive en `horario` y 1.2/1.3 en
  // `conceptoSanitario`. Ambas son sección 1 (ver
  // kInterventoriaSeccionPorCategoria), así que los numerales salen correctos.
  'horario': [
    '1. Se cumple con los horarios de entrega acorde con lo establecido por la OTM o a los acuerdos establecidos con el Establecimiento los cuales son informados mediante correo electrónico a la USPEC para su revisión. Detallar las causas que generan las desviaciones en el horarios atribuibles al contratista (si aplica).',
  ],
  'conceptoSanitario': [
    '2. Se cuenta con concepto Sanitario Vigente o se presenta soportes de las acciones para la renovación ante el ente correspondiente, antes del término de la vigencia de un (1) año o cuanto la supervisión lo requiera, acorde con lo establecido en la OTM. En caso de observaciones del ETS, el contratista adelanta acciones que permitan corregir las desviaciones encontradas.',
    '3. El servicio se encuentra libre de cualquier medida sanitaria de cierre total o parcial. En caso de observaciones del ETS, el contratista adelanta acciones que permitan corregir las desviaciones encontradas y presenta soportes de solicitud de nueva visita.',
  ],
  'instalacionesFisicas': [
    '1. El contratista mantiene los accesos y alrededores limpios, libres de acumulación de basuras, de estancamiento de aguas o la presencia de otras fuentes de contaminación para el alimento. En caso de imposibilidad de acceso, gestiona con el director del establecimiento, la limpieza de los alrededores del servicio de alimentación.',
    '2. Las áreas con las que cuenta el servicio de alimentación, se encuentran señalizadas, operativas, y son usadas para la actividad prevista. Estas no generan riesgo de contaminación física, química y biológica en los alimentos. En caso no contar con la infraestructura para ubicar alguna de las áreas establecidas por la OTM, el contratista cuenta con soportes de radicación de informe manifestando las limitaciones de áreas.',
    '3. El contratista, gestiona los mantenimientos correctivos menores con respecto a mantenimiento de pisos, paredes, techos y media cañas; los cuales, se encuentran en buen estado libre de grietas, porosidad, entre otros.',
    '4. El contratista, gestiona los mantenimientos correctivos menores (pintura o resane) de ventanas, marcos, puertas, estanterias, se encuentran en buen estado. Las aberturas cuentan con su respectiva protección evitando el ingreso de plagas o cualquier otro contaminante.',
    '5. El contratista garantiza que cada una de las áreas con las que cuente el servicio de alimentación establecidas en la OTM cuenta con iluminación y las lámparas se encuentran funcionando y protegidas en caso de rotura.',
    '6. Las instalaciones eléctricas (cableado, tomacorrientes, cajas de instalación, entre otros), de cada una de las áreas del servicio de alimentación se encuentran en buen estado, funcionales y no generan riesgo de accidente laboral.',
    '7. Los sistemas de evacuación de aguas residuales se encuentran protegidos con tapas removibles (sifones o rejillas) para evitar la generación de malos olores y/o ingreso de plagas y estas se encuentran en buen estado.',
    '8. El contratista, gestiona los mantenimientos correctivos menores con respecto al estado de los mesones; estos, se encuentran en buen estado libre de grietas, porosidad, entre otros.',
    '9. Existen lavamanos de accionamiento no manual ubicados cerca al área de proceso.',
    '10. Las instalaciones sanitarias se encuentran en estado operativo y/o funcionales, se garantiza el uso previsto.',
    '11. Existen letreros alusivos a la correcta aplicación de BPM, entre estas el lavado de manos, visibles, ubicados en las instalaciones sanitarias y áreas de proceso.',
    '12. Existen mensajes "Espacio libre de humo, cigarrillo o tabaco" (Ley 1335 del 2009) en buen estado y ubicados en las instalaciones sanitarias y áreas de proceso.',
    '13. Existe un área exclusiva para el almacenamiento temporal de los alimentos o materias primas clasificadas como PRODUCTOS NO CONFORMES. Se encuentra señalizada de acuerdo a la OTM.',
    '14. El contratista garantiza un área exclusiva para ensamble de las raciones.',
    '15. Existe un espacio físico exclusivo para el depósito temporal de los residuos sólidos, protegido, ventilado, señalizado, alejado de las áreas de producción y distribución, en adecuadas condiciones físicas.',
    '16. Existe un área para la limpieza y desinfección de los utensilios y menaje.',
    '17. El contratista realizó la instalación de medidores calibrados y certificados que permitan verificar el consumo de los diferentes servicios públicos (captación de agua, energía, gas), en un término no mayor a treinta (30) días hábiles contados a partir del acta de inicio. Se realizaron las gestiones en conjunto con el INPEC ante las Empresas de Servicios Públicos - ESP - locales, para la respectiva instalación (Si aplica). Si los servicios no se encuentren independizados, existe acuerdo de pago con los procedimientos y proporciones establecidos con la administración de cada ERON correspondientes al consumo proporcional de los servicios públicos de acueducto, alcantarillado, energía eléctrica, gas, alumbrado público, aseo (disposición de residuos), con base en las facturas de cobro del servicio emitidas por las ESP respectivas.',
  ],
  'almacenamiento': [
    '2. Existen fichas técnicas de las materias primas acorde al listado de proveedores ofertados.',
    '3. Se evidencia cumplimiento en la proyección del plan de compras de acuerdo con el promedio del parte diario, las cantidades establecidas en la minuta patrón y los proveedores ofertados. Se lleva un control de entradas y salidas.',
    '4. Los alimentos almacenados presentan fechas de vencimiento vigentes.',
    '5. Los alimentos cuentan con el etiquetado y rotulo establecido para el empaque primario acorde a la normatividad vigente.',
    '6. Los alimentos almacenados como materia prima destinada para el suministro, estan libres de cualquier tipo de contaminación biológica, química o física.',
    '7. En el alimento enlatado NO se evidencian las siguientes características: a) Lata con golpe o abolladura; b) la tapa se mueve hacia arriba y hacia abajo (clic). c) Lata oxidada. d) lata hinchada. e) Fecha de vencimiento expirada al momento de la visita.',
    '8. Las materias primas se almacenan según sus características naturales por medio de separación física (evitando contaminación cruzada- temperatura óptimas de almacenamiento) y son conservadas en empaques de primer uso (Resolución 683 del 2012) recipientes y/o canastillas de material sanitario, sobre estibas en optimas condiciones físicas y de higiene.',
    '9. Se cumplen con las distancias perimetrales en el almacenamiento de los alimentos y/o el contratista gestiona acciones que permitan realizar la limpieza y la verificación del área.',
    '10. El método PEPS es aplicado por el operador y los productos se encuentran identificados por rotulo de colores de acuerdo a lo establecido en OTM.',
    '11. Las materias primas almacenadas que han sido re envasada y/o fraccionada de su empaque original a otro recipiente, se encuentran identificadas de acuerdo a lo estipulado en la OTM (Alimentos no perecederos: Producto, Proveedor, fecha de empaque y vencimiento- dia mes año).',
    '12. El producto evidenciado como no conforme se encuentra almacenado en el area dispuesta para tal fin. Se encuentra con registros actualizados y la disposición final no supera los dos (2) días calendario.',
    '13. En área de almacenamiento, no se evidencian alimentos contemplados en la OTM y en el Anexo 4. N-N010 Preparaciones Prohibidas, o no se observan aditivos alimentarios y saborizantes artificiales no permitidos.',
  ],
  'equipos': [
    '1. El servicio cuenta con los equipos mínimos requeridos según el Anexo No 5 para el proceso de producción acorde a las necesidades del servicio de alimentación, en capacidad, suficiencia, volumen y funcionalidad. En caso de faltantes por limitaciones el contratista realiza notificación a USPEC y/o Interventoria de las medidas y estrategias tomadas para el reemplazo del equipo con limitante, cuenta con oficio de aprobación de alternativas por parte de la Entidad.',
    '2. Los equipos son de materiales inertes, resistentes a la corrosión, no recubiertos con pinturas o materiales desprendibles, son fáciles de desarmar, limpiar y desinfectar. Se encuentran en buen estado, libres de deterioro.',
    '3. Los utensilios y menaje son de materiales inertes, resistentes a la corrosión, no recubiertos con pinturas o materiales desprendibles, son fáciles de desarmar, limpiar y desinfectar. Se encuentran en buen estado, libres de deterioro.',
    '4. El contratista cuenta con las tablas de corte de acuerdo al código de colores establecido en la OTM.',
    '5. Los equipos de refrigeración y congelación se encuentran funcionando, en cantidad suficiente, se usan según su propósito (acorde a la naturaleza del alimento) y se encuentran calibrados a escala.',
    '6. Se evidencia entrega de menaje para los PPL según lo estipulado en las especificaciones técnica descritas en la Oferta Técnica Mínima (OTM). Así mismo, se observa soporte de entrega del 8% o 10% adicional de menaje en el inicio del contrato y para la reposición (Si aplica).',
    '7. No existe algún tipo de menaje y/o equipos en desuso en el servicio de alimentación que genere algún tipo de contaminación. Se encuentra identificado FUERA DE USO - OBSOLETO. El contratista realiza la gestión para el traslado o retiro de los equipos ante INPEC.',
    '8. El contratista dispone de la cantidad de los carros transportadores de acuerdo con las particularidades y características de cada ERON (donde aplique) y estos se encuentran inventariados e identificados de manera visible para facilitar su ubicación. Además, cumplen con las características estipuladas en la OTM, con puertas o sistema de cierre, elaborados con materiales no porosos, recubiertos con pintura anticorrosiva, de arrastre, funcional y capacidad adecuada y se encuentran en buen estado.',
    '9. El servicio de alimentación cuenta con trampas de grasas y/o el contratista instala trampas de grasa portátil. Se encuentran en buen estado, funcionales, de acuerdo con la capacidad instalada para cada servicio.',
    '10. El contratista cumple con la totalidad de los equipos de medición básicos requeridos: cuatro (4) termómetros, balanzas, grameras o básculas, conforme a lo establecido en la Oferta Técnica Mínima (OTM). Además dispone del kit de equipos de medición el cual incluye termómetro para frío y calor y gramera. Está disponible para ser facilitado a las entidades que los requieran. Dichos equipos se encuentran en óptimas condiciones de funcionamiento.',
  ],
  'condicionesProduccion': [
    '1. El contratista cuenta con soportes de radicación de procedimiento en el cual se plasme las condiciones para la operación desde la recepción de los insumos y materias primas hasta el despacho del producto terminado. El cual incluya la forma en la que se eviten retrasos indebidos, contaminación biológica, física, química y contaminación cruzada, a través de la garantía de las condiciones sanitarias y como evitar el riesgo de la contaminación cruzada de los alimentos.',
    '2. Se evidencia la implementación del procedimiento anterior, en los procesos de pre-alistamiento y preparación de las materias primas, donde las labores se realizan bajo condiciones que evite el cruce de flujos de producción, evitando el riesgo de contaminación cruzada, garantizando el uso adecuado de elementos (guantes de manipulación, tablas de corte, entre otros), además de cualquier otro riesgo de contaminación. Se garantiza la limpieza y desinfección de alimentos (frutas y verduras).',
    '3. El producto terminado se sirve a temperatura mayor a 60°C y los alimentos refrigerados no mayor a 4°C +/-2°C.',
    '4. El prestador del servicio cuenta e implementa protocolo de control de temperatura, desde la recepción de materias primas hasta la distribución final, teniendo en cuenta las temperaturas establecidas dentro de la contratación para la elaboración de los alimentos, productos de consumo directo y peso servido.',
    '5. El contratista dispone e implementa el Plan de muestreo (control de gramaje) con base en la NTC ISO-2859-1, desde la recepción de materias primas hasta la distribución final, teniendo en cuenta los pesos establecidos dentro de la contratación para la elaboración de los alimentos, productos de consumo directo y peso servido.',
    '6. Se cuenta con utensilios estandarizados para garantizar el gramaje de cada uno de los componentes suministrados.',
    '7. Se garantiza que el hielo utilizado en el servicio de alimentación, se rotula y se almacena en adecuadas condiciones; éste debe ser fabricado con agua potable y manipulado en condiciones que garanticen su inocuidad, en caso, que el hielo empleado en el servicio de alimentación sea adquirido mediante proveedor se cumple con la Resolución 5109 de 2005.',
    '8. El contratista garantiza el servido del producto terminado y las dietas (si aplica) bajo condiciones que evite el cruce de flujos de producción, evitando el riesgo de contaminación cruzada según el método aplicado (Ensamble, por fondos o dietas). En caso de suministro en fondos, se hace uso de recipientes isotérmicos en condiciones que mantengan la inocuidad y temperatura del producto terminado.',
    '9. Para los casos en que se presente PPL con diagnósticos de inmunosupresión (VIH, Leucemia, Tratamientos oncológicos) así como eventos de enfermedades infectocontagiosas, la ración terapéutica se suministra en empaque de material desechable que cumpla con la normatividad vigente (Si aplica).',
    '10. Se cumple con el protocolo establecido en la OTM para la toma de las contra muestras: Custodiando tres (3) para menú ERON y/o EP de cada componente para cada tiempo de comida (desayuno, almuerzo, cena, refrigerio nocturno), (mínimo de 100g) y del agua (mínimo 200ml), utilizada en el servicio. Dietas (si aplica) y refrigerios adicionales de las gestantes y lactantes (si aplica). Asimismo, rotularla de manera legible e indeleble. Las muestras, deberán cumplir con las condiciones de: Gramaje, Temperatura, Rotulado, Registros, Disposición final (mín 72 h), entre otros.',
    '11. En caso de presentarse productos devueltos por la PPL al servicio de alimentación por rechazo y/o falencias presentadas por el contratista, que tengan incidencia sobre la inocuidad y calidad del alimento, no podrán someterse a procesos de reelaboración, reproceso, corrección o reensamble bajo ninguna justificación. Se reemplaza en su totalidad. (Si aplica).',
  ],
  'caracteristicasAlimentos': [
    '1. Existe cumplimiento del ciclo de menús en cuanto a la rotación del ciclo de menú aprobado. Se cuenta con soporte de información a la USPEC y/o Interventoría para el cambio evidenciado (según el procedimiento establecido). Desayuno: mínimo rotación de 3 frutas diferentes en la semana, sin repetir 3 días consecutivos la misma fruta. Almuerzo: rotación de mínimo 3 postres diferentes, sin repetir durante tres días seguidos el mismo postre. Almuerzo y cena: no repetir tubérculo, raíz y/o plátano en un mismo día. Almuerzo y cena: 2 sabores diarios de fruta para jugo, uno en almuerzo y otro en cena. Refrigerio: la bebida y el derivado cereal no se repiten durante tres (3) días seguidos.',
    '2. El contratista suministra la totalidad de los componentes del menú verificado (Faltantes - No entrega).',
    '3. El contratista cumple con el menú verificado según lo establecido al menú aprobado, a la minuta patrón y la OTM (Intercambios).',
    '4. En caso que el contratista suministre huevo y/o embutido, como intercambio del componente proteico, se cuenta con soporte de aprobación de la entidad y/o interventoría.',
    '5. Se realiza entrega de la salchicha de acuerdo con las características definidas en la OTM y corresponde a la ficha tecnica aprobada.',
    '6. Las características de las preparaciones de los alimentos cumplen con los ingredientes que componen la preparación para cada tiempo de comida. Se adicionan a la preparación las materias primas indicadas en el Anexo 4 y/o en la OTM.',
    '7. No se evidencia suministro de alimentos contemplados en la OTM y el Anexo 4. N-N010 Preparaciones Prohibidas, o no se observa el uso de aditivos alimentarios y saborizantes artificiales para preparaciones no permitidas.',
    '8. El contratista cumple con los gramajes de las preparaciones del menú verificado (Ver Anexo 12) del Eron.',
    '9. El contratista cumple con los gramajes de las preparaciones del menú verificado a suministrar en las EPs, UTs y URIs.',
    '10. El contratista cumple con la calidad organoléptica del menú verificado en el ERON de acuerdo a lo contemplado en la prueba hedonica (ANEXO 12).',
    '11. El contratista cumple con la calidad organoléptica del menú verificado a suministrar en las EPs - UTs - URIs cuando aplica.',
    '12. Se da cumplimiento al suministro de los refrigerios nocturnos, en rotación de los componentes y frecuencia, bajo las condiciones estipuladas en la oferta técnica mínima, garantizando que la bebida y el derivado cereal no se repitan durante tres (3) días seguidos.',
    '13. Se da cumplimiento a lo establecido en la Oferta Técnica Mínima (OTM) relacionado con el suministro de alimentación diferencial a grupo poblacional étnico (Comunidades Indígenas) y convicción religiosa según la aprobación establecida (Si aplica).',
    '14. El contratista suministra el Menú Especial - Ración para días festivos - concertado con la PPL como lo estipula la OTM. En caso de no entregarse en la fecha establecida, el suministro se realiza en los treinta (30) días calendarios siguientes.',
    '15. El contratista suministra el Menú Especial Adicional en las fechas notificadas al inicio de la operación y corresponde a la propuesta de menú aprobado.',
    '16. Se entregan los refrigerios para la PPL que salen de remisión de acuerdo con las características y gramaje establecido en la Oferta Técnica Mínima, dicha entrega se soporta mediante el formato establecido en el anexo 4 N-N011 FORMATO DIARIO DE ENTREGA DE REFRIGERIOS DE REMISIÓN.',
    '17. Se cumple con el programa de tamizaje nutricional y se desarrolla de acuerdo a lo estipulado en la OTM (primeros treinta (30) días hábiles posteriores al inicio de la contratación).',
    '18. Se realiza la entrega de dietas terapéuticas para la PPL que lo requiera y cumplen con las condiciones definidas en el Oferta Técnica Mínima (derivación dietaría, gramaje, etc.) y Manual de Dietas Terapéuticas (Anexo No.3). Formato de verificación de entrega de Dietas Terapéuticas (si aplica).',
    '19. Para el caso de la RACIÓN TERAPÉUTICA cada recipiente se encuentra rotulado de acuerdo con lo estipulado en la OTM (marcado de manera legible e indeleble, con el nombre del interno, patio y tipo de dieta). Está prohibido el uso de fondos para la entrega de dietas.',
    '20. Se lleva registro y control diario de entrega de dietas terapéuticas y este se encuentra soportado diariamente mediante la firma de recibo de cada PPL posterior al recibo (recolección de firma y huella en la semana). En caso tal que la PPL no firme esta entrega diaria de dietas, el cumplimiento será respaldado mediante acta firmada por el representante de DDHH, testigos de la PPL y funcionario del INPEC asignado para el seguimiento COSAL.',
    '21. El contratista cuenta con soportes de revaloración para seguimiento, ajuste o retiro de dietas de la PPL afiliada al régimen contributivo, excepción o especial (seguimiento semestral para enfermedades crónicas HTA-DM-CT y cada 3 meses para patologias agudas o especiales).',
    '22. El contratista ha realizado la valoración nutricional inicial (prescripción dietaria), así como el seguimiento, ajuste y/o retiro de dietas de la PPL con cobertura en salud a través del Fondo Nacional de Salud PPL -régimen subsidiado- por solicitud del área de sanidad y/o salud del establecimiento y de acuerdo con las particularidades descritas en la OTM.',
    '23. Se da cumplimiento a lo establecido en la Oferta Técnica Mínima (OTM) relacionada con el suministro de las raciones para gestantes y lactantes (refrigerios y bebidas adicionales), en caso de presentarse.',
    '24. Se da cumplimiento a lo establecido en la Oferta Técnica Mínima (OTM) para las gestantes y lactantes, de tal forma que se brinde educación para la práctica de la lactancia materna exclusiva, el inicio de la alimentación complementaria y los cuidados del menor.',
    '25. El Contratista garantiza la valoración y el seguimiento nutricional del 100% de las gestantes y lactantes afiliadas al régimen contributivo, excepción o especial y aquellas remitidas por el médico tratante en establecimientos a cargo del INPEC (5 valoraciones-seguimientos durante gestación y lactancia).',
    '26. Se llevan registros de las renuncias a la alimentación y/o dietas (si aplica), firmados por el PPL, nutricionista del contratista y profesional de sanidad del establecimiento. En los casos donde la PPL indígena renuncie o no concertó un menú diferenciado, se cuenta con acta firmada del PPL, representantes COSAL y dirección del establecimiento.',
    '27. El ciclo de menús y sus actualizaciones, se encuentran socializados de acuerdo a la OTM con representantes de DDHH de PPL, representantes de la COSAL y director del establecimiento. El acta de presentación de ciclos de menú cuenta con fecha de inicio de la prestación del servicio y los horarios de entrega en cada tiempo de consumo.',
  ],
  'personalManipulador': [
    '1. El contratista cumple con el personal minimo requerido y oferta técnica adicional - Anexo 9 y Estudios Previos - Licitación pública (si aplica), gestiona el personal necesario con antelación ante el INPEC. Adicionalmente, cumple con el perfil y la frecuencia de visitas, según lo estipulado en el Anexo 9, Anexo 10 y la Oferta Técnica Mínima (OTM). Se cuenta con soportes de asistencia y/o justificación de ausencia.',
    '2. El contratista da cumplimiento a lo establecido en el código sustantivo del trabajo y la OTM en relación a la entrega de dotación completa al personal profesional y operativo (2 dotaciones). Se cuenta con soportes de entrega correspondiente a la renovación de la dotación a los 6 meses, a partir del inicio del contrato.',
    '3. El contratista entrega la dotación a los visitantes (bata, gorro y tapabocas) y no se permite el ingreso a personal sin la debida dotación.',
    '4. Los manipuladores utilizan la dotación completa (zapatos, gorro, tapabocas, delantal-peto, guantes) y se encuentra limpia, en buen estado, de color claro y cumple con las especificaciones de la norma legal vigente.',
    '5. Los manipuladores cumplen con los hábitos de higiene personal y las practicas higiénicas (uñas cortas, limpias y sin esmalte, cabello recogido, sin uso de joyas u otros accesorios, no uso de perfume ni maquillaje, utilización de tapabocas).',
    '6. Se observa a los manipuladores realizando lavado de manos con agua y jabón desinfectante antes de comenzar y en cada cambio de actividades, cada vez que salga y regrese al área de producción, y después de manipular materiales u objetos que puedan representar riesgo de contaminación para los alimentos.',
    '7. El personal manipulador no presenta infecciones dérmicas, lesiones, infecciones gastrointestinales, respiratorias que puedan contaminar los alimentos. En caso de presentarse, se cuenta con registros que describan el seguimiento al control de salud a los manipuladores de alimentos (fecha, razón clínica, descripción de acciones preventivas y correctivas y concepto).',
    '8. Los manipuladores de alimentos cuentan con el certificado médico anual vigente en el contrato (apto para manipular alimentos) y exámenes clínicos (frotis de garganta con cultivo, KOH de uñas, coprocultivo). En caso de no contar con el resultado, se evidencia gestión del operador (acta de toma de muestras, resultados de laboratorios pendientes por emisión).',
    '10. La PPL desarrolla las actividades de manipulación de alimentos, cumpliendo con las horas máximas de trabajo diario y de descanso establecido en el convenio de trabajo.',
    '11. Se cuenta con personal capacitado para la limpieza de la campana extractora donde aplique y que cumpla lo contemplado en la resolución 1409 de 2012 referente a la protección contra caídas en trabajo en alturas.',
  ],
  'condicionesSaneamiento': [
    '1. Se cuenta con procedimiento definido e implementado para garantizar las condiciones sanitarias, evitando la contaminación cruzada, de forma tal que se desarrollen las actividades de manera secuencial, desde la recepción de materias primas hasta la entrega del producto terminado. Las areas se encuentran señalizadas.',
    '2. Las paredes, medias cañas, pisos, mesones, ventanas, puertas y barreras de protección (angeos, burletes, entre otros) se encuentran limpios. Se evita el estancamiento de agua. Se llevan registros y estos se encuentran actualizados.',
    '3. Los techos se encuentran limpios, sin presencia de hongos, el contratista gestiona la limpieza de acuerdo a lo establecido por la OTM. Se llevan registros y estos se encuentran actualizados.',
    '4. El contratista garantiza la limpieza y desinfección de los equipos, utensilios y carros transportadores con que cuenta el servicio de alimentación.',
    '5. Las instalaciones sanitarias se encuentran alejadas del área de producción, limpias y dotadas con elementos de higiene personal: papel higiénico, jabón líquido inoloro y desinfectante, gel antibacterial mayor al 65% de concentración, implementos desechables o equipos automáticos para el secado de manos y papeleras con tapa, bolsa y pedal (si aplica).',
    '6. Los productos químicos para realizar las operaciones de limpieza y desinfección cuentan con fichas técnicas, se especifican concentraciones, modo de preparación, empleo y rotación; así mismo, se almacenan en un espacio ventilado, identificado y protegido. Los productos químicos se encuentran rotulados de acuerdo a lo establecido en la OTM con nombre, fecha de envase, nivel de toxicidad y forma de uso.',
    '7. El contratista suministra los elementos de aseo y los insumos utilizados para realizar las operaciones de limpieza y desinfección. Para los utensilios de aseo se aplica código de colores y están debidamente rotulados y organizados como lo establece la OTM. El lavado y desinfección de los elementos de aseo, se realiza de tal manera que se evite el riesgo de contaminación.',
    '8. El contratista garantiza la limpieza y desinfección del menaje para la PPL (fiambrera, vasos y cuchara) antes de cada tiempo de comida y/o proporciona mensualmente a la PPL el kit de limpieza y desinfección (detergente, desinfectante y esponja) mediante acta de entrega, generada en los primeros 10 días calendarios del mes.',
    '10. El contratista garantiza el suministro de agua potable en el servicio de alimentación y/o cuenta con un plan de acción que garantice el suministro con registro de procedimientos, de acuerdo a lo establecido en la OTM.',
    '11. El tanque de almacenamiento de agua tiene capacidad para garantizar como mínimo un día de suministro. Se encuentra construido en material sanitario, protegido, identificado e indica su capacidad. El contratista garantiza o gestiona la limpieza y desinfección mínimo cada 6 meses. Se cuentan con registros.',
    '12. Se realiza diariamente los análisis de pH y Cloro Residual en diferentes puntos de agua dentro del servicio de alimentación. Existen registros actualizados.',
    '13. Se cuenta con recipientes para la disposición de residuos sólidos en número suficiente, identificados, de material sanitario, en buen estado, con tapa y bolsa plástica.',
    '14. Los residuos solidos generados en el servicio de alimentación se retiran mínimo tres veces al día del área de proceso, y cuenta con registros que lo soporten. Se encuentra publicado el plano de rutas de recolección y evacuación de residuos solidos.',
    '15. Se realizan procesos de limpieza y desinfección a las trampas de grasas. Se encuentran registros actualizados. Mencione la frecuencia (Si aplica). En caso de trampas de grasas compartidas con el establecimiento (subterraneas), el contratista gestiona el mantenimiento y limpieza con el establecimiento.',
    '16. Existe un correcto manejo (recolección, clasificación y disposición final) de los residuos sólidos aprovechables (reciclaje), líquidos y peligrosos (Lavazas, lámparas fluorescentes, baterías etc.); y se encuentra articulado con el PIGA del establecimiento.',
    '17. Existe un correcto manejo (almacenamiento, recolección, tratamiento y disposición final) del aceite vegetal usado (AVU) según resolución 3957 de 2009 y resolución 316 de 2018, asi como la recolección local establecida.',
    '18. El control de plagas se realiza de acuerdo con la ficha técnica del producto empleado en los servicios de alimentación, con la periodicidad del control de acuerdo a la normatividad sanitaria legal vigente. Se cuenta con plano de ubicación de cebos y este se encuentra ubicado en un lugar visible (Si aplica). Se evidencian los soportes en relación al control de plagas (cronograma, formatos de inspección interno y externo, documentación de empresa fumigadora, fichas técnicas de productos empleados). Además, el servicio de alimentación se encuentra libre de huella, presencia o daño causado por plagas.',
  ],
  'condicionesTransporte': [
    '1. El recibo de las materias primas, insumos, alimentos entre otros, se realiza conforme a los lineamientos y/o los horarios establecidos por el Establecimiento.',
    '2. Los vehículos transportadores de alimentos se encuentran en adecuadas condiciones físicas y de higiene, cuenta con la documentación requerida en la OTM (SOAT, Revisión técnico-mecánica si aplica, CHS, tarjeta de propiedad, entre otros).',
    '3. Los alimentos se reciben, transportan y distribuyen de acuerdo con su naturaleza, en recipientes, canastillas o implementos de material adecuado que eviten disponerlos sobre el piso del medio de transporte, bajo condiciones que aseguran el mantenimiento de sus propiedades hasta su destino final. Para distribución en motocicleta (EP: parte 20 PPL), se garantizan las condiciones de inocuidad. El contratista cuenta con registro actualizado del monitoreo de la temperatura del vehículo durante el transporte del alimento, el cargue y descargue (Transporte interno y externo).',
    '4. Los vehículos transportadores de alimentos llevan en su exterior en forma claramente visible la leyenda: TRANSPORTE DE ALIMENTOS (Transporte interno y externo). *Excluye motocicleta.',
    '5. El personal transportador (Transporte interno y externo) cuenta con certificado de manipulación de alimentos y vestimenta adecuada de acuerdo a la normatividad vigente. El conductor cuenta con Licencia de conducción vigente.',
  ],
  'aseguramientoControlCalidad': [
    '1. La totalidad de los planes y programas requeridos en la Oferta Técnica Mínima (OTM), remitidos documentalmente a la interventoría, se encuentran ajustados a las características del establecimiento y se evidencia la socialización ante el Director del establecimiento. *En caso de evidenciar que lo presentado documentalmente no se ajuste al servicio de alimentación se deberá realizar la actualización del plan y/o programa respectivo.',
    '2. El contratista realiza recibo de materias primas aplicando los criterios de aceptación y rechazo (cantidades, temperatura, fechas de vencimiento, números de lote, estado del empaque, etc.) y diligencia los formatos establecidos en el Anexo 2.',
    '3. Se cuentan con formatos básicos estandarizados para el registro de producción (Té, menú preparado, control de gramaje, sensorial, ración estándar, entre otros).',
    '4. El operador implementa el programa de mantenimiento preventivo y correctivo de equipos acordes al listado maestro, hoja de vida y cronograma (Mantenimiento preventivo y/o correctivo menores). Se mantiene los registros actualizados.',
    '5. Los equipos de medición utilizados para el control de temperatura y de gramaje son calibrados anualmente y verificados de forma semanal, conforme a la frecuencia establecida en la Oferta Técnica Mínima (OTM). Se lleva un registro detallado de dichas actividades, el cual incluye los rangos de tolerancia. Para el caso de los termómetros, se garantiza que la desviación no exceda los ±1°C.',
    '6. Los muestreos microbiológicos por ERON cumplen con la frecuencia establecida en el Anexo 6 y los parámetros establecidos en el Anexo 7. En caso de que se presenten resultados por fuera de los parámetros, el contratista realiza un análisis de causas, define e implementa un plan de acción (correctivo y de mejora) con su respectivo seguimiento.',
    '7. El laboratorio que realiza la toma de muestras pertenece a la RED de Laboratorios de salud pública del ministerio de salud y adicionalmente cumple con lo establecido en la resolución 1619 de 2015, a través del concepto y/o visitas de IVC realizadas por el ente territorial de salud pública, en donde la sumatoria obtenida para los seis criterios evaluados de los Estándares de Calidad con la herramienta del INVIMA presenta un rango esperado de mínimo 170 puntos y máximo 187 puntos.',
    '8. Se observa resultados microbiológicos CONFORMES de acuerdo a lo establecido en la normatividad vigente (Ausencia de microorganismos patógenos como Escherichia coli, Listeria monocytogenes, Salmonella sp, Bacillus cereus etc.) de materias primas, agua potable, manipuladores, superficies, ambiente y producto terminado según la OTM.',
    '9. Se observa resultados microbiológicos CONFORMES, para los indicadores de calidad, limpieza y desinfección, de acuerdo a lo establecido en la normatividad vigente (mesófilos aerobios, coliformes totales, mohos y levaduras, entre otros), en materias primas, agua potable, manipuladores, superficies, ambiente y producto terminado según la OTM.',
    '10. El contratista realiza los análisis fisicoquímicos del agua, de acuerdo a la frecuencia establecida en la OTM (Frecuencia: Cada 6 meses independiente del número de PPL. Primer análisis dentro de los primeros quince (15) días hábiles del contrato, de conformidad con lo establecido en el Decreto 1575 de 2007, Artículo 10, numeral 3).',
    '11. No se ha presentado algún brote de Enfermedad Trasmitida por Alimentos (Declarada por Secretaria Distrital de Salud, Asociación Epidemiológica, Agente Etiológico) en los ERON, CRM, EP y UT.',
    '12. En caso de presentarse una posible ETA, el contratista cumple con el protocolo establecido para las acciones y responsabilidades para el manejo de ETAS dentro de los ERON, EP, CRM y UT. Suministra las contra muestras disponibles para la autoridad sanitaria local (Secretaria de Salud, Alcaldía, Gobernación) y/o el supervisor del contrato por parte de la entidad y/o interventoría, en caso de requerirse y/o ante una eventual investigación.',
    '13. En los equipos de frío se lleva control y registro de temperatura en un lugar visible. Se cumple con la frecuencia establecida en la OTM (mínimo dos veces, uno antes de iniciar actividades y el otro al finalizar la jornada).',
    '14. Los carros transportadores cuentan con la respectiva hoja de vida y se les realiza mantenimiento preventivo trimestral que evite la presencia de óxido, daños mecánicos, falta de ruedas, entre otros.',
    '15. Se articula y sensibiliza a los representantes de cada patio para llevar a cabo un adecuado proceso de higienización del menaje, dejando registros sobre la actividad mediante actas de capacitación.',
    '16. El contratista cumple con capacitación establecida en la OTM continua y permanente, minimo de 4 horas mensuales, según la Resolución 2674 de 2013. Además la capacitación adicional (Estudios Previos), al menos 20 horas durante la ejecución del contrato, en Buenas prácticas y hábitos en la cadena de producción de alimentos, prestación del servicio y generación de vida saludable. El personal profesional cuenta con plan de inducción sobre documentos técnicos y contractuales, dirigido por un talento humano idóneo. Dichas capacitaciones cumplen número de horas de acuerdo a lo pactado y se cuentan con registros.',
    '17. Se cuenta con el programa de trazabilidad definido e implementado, en donde se observa el análisis de trazabilidad de cada una de las etapas productivas. En el momento de la visita se observan los registros actualizados.',
    '18. En caso de contar con un plan de contingencia específico para el establecimiento, este se encuentra ajustado a las condiciones del mismo, esta diseñado bajo la estructura documental estipulada en la OTM y las actividades realizadas corresponden con lo aprobado por la supervisión y/o interventoría.',
    '19. Los planes de emergencia se encuentran diseñados bajo la estructura documental estipulada en la OTM y se encuentra ajustado a las características del establecimiento. En el momento de la visita, se evidencia registros actualizados y socialización al establecimiento.',
    '20. El contratista adquiere los productos alimenticios elaborados por proyectos productivos que cumplan con la normatividad legal vigente (Si aplica). Realiza mensualmente los pagos al establecimiento correspondientes al consumo proporcional de los servicios públicos de acueducto, alcantarillado, energía eléctrica, gas, alumbrado público, aseo (disposición de residuos). Además realiza mensualmente los pagos de bonificación de la PPL y ARL de la PPL. Se evidencian soportes.',
    '21. No se observa el ingreso y/o retiro de elementos prohibidos en el establecimiento.',
  ],
  'seguridadSaludTrabajo': [
    '1. Se evidencian registros actualizados de capacitaciones en SST (actas de capacitación y evaluación), a trabajadores y PPL.',
    '2. El botiquín se encuentra dotado de conformidad con su clasificación Tipo A, Tipo B, verificar formato de inspección mensual.',
    '3. Los extintores se encuentran debidamente señalizados, visibles y aptos para atender emergencias, verificar formato de inspección. Se cuenta con los tres tipos de extintores establecidos para el servicio de suministro de alimentación (CO2, acetato de potasio y multipropósito).',
    '4. Se cuenta con manta anti fuego cerca a los equipos de cocción.',
    '5. La política SST se encuentra publicada y firmada. Se cuenta con la ruta de evacuación debidamente señalizada y visible.',
    '6. El personal externo empleado por el contratista, cuenta con exámenes médicos ocupacionales de ingreso.',
    '7. Se cuenta con el registro de entrega de los elementos de protección personal.',
    '8. Existen equipos campanas y/o extractores de aire, instalaciones con barandas, si aplica, en funcionamiento, en buen estado, bien ubicados, en cantidad suficiente. La ventilación es adecuada para prevenir la condensación.',
  ],
};

/// Fila de la biblioteca maestra de subsanaciones.
///
/// Une el texto completo del numeral con la matriz oficial que determina a
/// qué cargo se asigna y quién debe aprobar el cierre. No representa un
/// hallazgo concreto: es la regla reusable que aplica a todas las visitas.
class InterventoriaMaestroSubsanacion {
  final String numeral;
  final int seccion;
  final String seccionNombre;
  final String descripcion;

  /// Cargos que pueden responder por el numeral, en orden de preferencia.
  ///
  /// Son alternativas, no destinatarios: el hallazgo pertenece a un
  /// establecimiento y se asigna a quien tenga alguno de estos cargos en esa
  /// sede. Poner "Administrador tipo 1" y "tipo 2" en la misma regla cubre a
  /// las sedes que usan uno u otro sin repetir la regla por sede.
  final List<String> responsables;

  /// Cargos que pueden aprobar el cierre. Cualquiera de ellos basta.
  final List<String> aprobadores;

  const InterventoriaMaestroSubsanacion({
    required this.numeral,
    required this.seccion,
    required this.seccionNombre,
    required this.descripcion,
    required this.responsables,
    required this.aprobadores,
  });

  /// Primer cargo de cada rol, para lo que solo tiene espacio para uno.
  String get responsable => responsables.isEmpty ? '' : responsables.first;
  String get aprobador => aprobadores.isEmpty ? '' : aprobadores.first;

  String get responsablesTexto => responsables.join(' · ');
  String get aprobadoresTexto => aprobadores.join(' · ');

  bool get incompleta => responsables.isEmpty || aprobadores.isEmpty;

  InterventoriaMaestroSubsanacion copyWith({
    List<String>? responsables,
    List<String>? aprobadores,
  }) => InterventoriaMaestroSubsanacion(
    numeral: numeral,
    seccion: seccion,
    seccionNombre: seccionNombre,
    descripcion: descripcion,
    responsables: responsables ?? this.responsables,
    aprobadores: aprobadores ?? this.aprobadores,
  );
}

/// Superpone la configuración editable de la empresa sobre el catálogo base.
/// Un valor vacío es intencional: permite marcar una regla como incompleta y
/// evita que la aplicación invente un responsable o aprobador.
List<InterventoriaMaestroSubsanacion> aplicarReglasSubsanacion(
  List<InterventoriaMaestroSubsanacion> base,
  Map<String, dynamic> reglas, {
  String tipoActa = kActaRegular,
}) => List.unmodifiable(
  base.map((fila) {
    final raw = reglaGuardada(reglas, tipoActa, fila.numeral);
    if (raw == null) return fila;
    return fila.copyWith(
      responsables: cargosDeRegla(raw['responsables'], raw['responsable']),
      aprobadores: cargosDeRegla(raw['aprobadores'], raw['aprobador']),
    );
  }),
);

/// Clave de la categoría que representa una sección de las actas con catálogo
/// propio. La pantalla de registro pinta una tarjeta por categoría, así que
/// cada sección necesita una.
String claveCategoriaSeccion(int seccion) => 'seccion$seccion';

/// Categorías por acta, construidas una vez.
final Map<String, List<InterventoriaCategoria>> _categoriasPorActa = {
  for (final entrada in kSeccionesPorTipoActa.entries)
    entrada.key: List.unmodifiable([
      for (final seccion in entrada.value)
        InterventoriaCategoria(
          claveCategoriaSeccion(seccion.numero),
          '${seccion.numero}. ${seccion.nombre}',
        ),
    ]),
};

/// Categorías que se evalúan en un acta.
///
/// El acta regular conserva su lista de siempre, con sus tarjetas especiales
/// de concepto sanitario y horario. Las actas propias sintetizan una categoría
/// por sección.
List<InterventoriaCategoria> categoriasDeActa(String? tipoActa) =>
    _categoriasPorActa[(tipoActa ?? '').trim().toUpperCase()] ??
    kInterventoriaCategorias;

/// Aspectos del acta para una categoría.
List<String> aspectosDeActa(String? tipoActa, String categoriaKey) {
  final propio = kSeccionesPorTipoActa[(tipoActa ?? '').trim().toUpperCase()];
  if (propio == null) {
    return kInterventoriaItemsActaPorCategoria[categoriaKey] ?? const [];
  }
  for (final seccion in propio) {
    if (claveCategoriaSeccion(seccion.numero) == categoriaKey) {
      return seccion.aspectos;
    }
  }
  return const [];
}

/// Número de sección real de una categoría, para la numeración del acta.
///
/// No se usa la posición en la lista: en el acta regular horario y concepto
/// sanitario son ambos sección 1, así que numerar 1..12 correría todas las
/// demás un lugar.
int? seccionDeActa(String? tipoActa, String categoriaKey) {
  final propio = kSeccionesPorTipoActa[(tipoActa ?? '').trim().toUpperCase()];
  if (propio == null) return kInterventoriaSeccionPorCategoria[categoriaKey];
  for (final seccion in propio) {
    if (claveCategoriaSeccion(seccion.numero) == categoriaKey) {
      return seccion.numero;
    }
  }
  return null;
}

/// Numeral del acta para un aspecto elegido del catálogo.
///
/// Sin esto el hallazgo llega al tablero como "no se pudo identificar el
/// numeral" y ninguna regla del maestro se le aplica.
///
/// En el acta regular el numeral sale del texto del aspecto, como siempre. En
/// las actas propias es la posición del aspecto dentro de su sección, que es
/// exactamente como están numeradas en el papel.
String numeralDeAspectoEnActa(
  String? tipoActa,
  String categoriaKey,
  String aspecto,
) {
  final propio = kSeccionesPorTipoActa[(tipoActa ?? '').trim().toUpperCase()];
  if (propio == null) return numeralActaDesdeAspecto(categoriaKey, aspecto);
  for (final seccion in propio) {
    if (claveCategoriaSeccion(seccion.numero) != categoriaKey) continue;
    final i = seccion.aspectos.indexOf(aspecto);
    return i < 0 ? '' : numeralDeAspecto(seccion.numero, i);
  }
  return '';
}

/// ¿El numeral existe en el acta indicada?
///
/// Se valida antes de guardar una regla: sin esto, un numeral mal escrito
/// crea una regla que no aplica a nada y que nadie vuelve a mirar.
bool numeralPerteneceAActa(String tipoActa, String numeral) {
  final clave = normalizarNumeralActa(numeral);
  final propio = kSeccionesPorTipoActa[tipoActa.trim().toUpperCase()];
  if (propio != null) {
    for (final seccion in propio) {
      for (var i = 0; i < seccion.aspectos.length; i++) {
        if (numeralDeAspecto(seccion.numero, i) == clave) return true;
      }
    }
    return false;
  }
  return kInterventoriaResponsabilidadPorNumeral.containsKey(clave);
}

/// Clave con la que se guarda la regla de un numeral dentro de
/// `TBL_INTERVENTORIA_CONFIG/{empresa}.reglasSubsanacion`.
///
/// Lleva la familia del acta por delante porque el mismo numeral existe en
/// varias actas y significa cosas distintas: el 1.4 del acta de policía no
/// tiene nada que ver con el 1.4 de la regular.
String claveRegla(String tipoActa, String numeral) =>
    '${familiaReglasActa(tipoActa)}::${normalizarNumeralActa(numeral)}';

/// Busca la regla guardada de un numeral.
///
/// Las reglas anteriores se guardaron con el numeral suelto como clave, cuando
/// el acta regular era la única que existía. Esas claves siguen valiendo, pero
/// SOLO para la familia regular: si valieran para todas, un acta nueva
/// heredaría responsables que nadie le asignó y el hallazgo se iría a quien no
/// es, sin que nada lo advierta. Por eso no hace falta migrar nada.
Map<String, dynamic>? reglaGuardada(
  Map<String, dynamic> reglas,
  String tipoActa,
  String numeral,
) {
  final directa = reglas[claveRegla(tipoActa, numeral)];
  if (directa is Map) return Map<String, dynamic>.from(directa);
  if (familiaReglasActa(tipoActa) == kActaRegular) {
    final legado = reglas[normalizarNumeralActa(numeral)];
    if (legado is Map) return Map<String, dynamic>.from(legado);
  }
  return null;
}

/// Lee los cargos de un rol dentro de una regla guardada.
///
/// La lista manda; si no existe se cae al campo en singular, que es como
/// quedaron guardadas las reglas anteriores. Ignorarlo dejaria esas reglas sin
/// responsable de un dia para otro y sin ningun aviso.
List<String> cargosDeRegla(Object? lista, Object? unico) {
  if (lista is Iterable) {
    final cargos = lista
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (cargos.isNotEmpty) return cargos;
  }
  final unicoLimpio = (unico ?? '').toString().trim();
  return unicoLimpio.isEmpty ? const <String>[] : <String>[unicoLimpio];
}

/// Construye las 141 reglas de la biblioteca a partir de las dos fuentes
/// oficiales del módulo: los aspectos del acta y su matriz de responsabilidad.
///
/// Mantener esta unión en lógica de negocio evita que Web y Móvil terminen
/// mostrando catálogos distintos aunque cada plataforma use una presentación
/// adecuada a su espacio disponible.
List<InterventoriaMaestroSubsanacion> construirMaestroSubsanaciones({
  String tipoActa = kActaRegular,
}) {
  // Las actas que llegaron después traen su catálogo declarado tal como está
  // impreso: secciones numeradas y el numeral es `sección.posición`. No tienen
  // matriz de responsabilidad incluida a propósito — se llena desde el maestro.
  // Un responsable equivocado por defecto no se nota; una regla sin responsable
  // queda marcada "sin asignar" y se ve.
  final propio = kSeccionesPorTipoActa[(tipoActa).trim().toUpperCase()];
  if (propio != null) {
    return List.unmodifiable([
      for (final seccion in propio)
        for (var i = 0; i < seccion.aspectos.length; i++)
          InterventoriaMaestroSubsanacion(
            numeral: numeralDeAspecto(seccion.numero, i),
            seccion: seccion.numero,
            seccionNombre: seccion.nombre,
            descripcion: seccion.aspectos[i],
            responsables: const [],
            aprobadores: const [],
          ),
    ]);
  }

  final filas = <InterventoriaMaestroSubsanacion>[];
  for (final categoria in kInterventoriaCategorias) {
    final aspectos =
        kInterventoriaItemsActaPorCategoria[categoria.key] ?? const <String>[];
    for (final aspecto in aspectos) {
      final numeral = numeralActaDesdeAspecto(categoria.key, aspecto);
      final responsabilidad = kInterventoriaResponsabilidadPorNumeral[numeral];
      final seccion = kInterventoriaSeccionPorCategoria[categoria.key];
      if (numeral.isEmpty || responsabilidad == null || seccion == null) {
        continue;
      }
      filas.add(
        InterventoriaMaestroSubsanacion(
          numeral: numeral,
          seccion: seccion,
          seccionNombre:
              kInterventoriaSeccionNombres[seccion] ?? categoria.label,
          descripcion: aspecto.replaceFirst(RegExp(r'^\s*\d{1,2}\s*\.\s*'), ''),
          responsables: cargosDeRegla(null, responsabilidad.responsable),
          aprobadores: cargosDeRegla(null, responsabilidad.aprobador),
        ),
      );
    }
  }
  filas.sort((a, b) {
    final porSeccion = a.seccion.compareTo(b.seccion);
    if (porSeccion != 0) return porSeccion;
    final itemA = int.tryParse(a.numeral.split('.').last) ?? 0;
    final itemB = int.tryParse(b.numeral.split('.').last) ?? 0;
    return itemA.compareTo(itemB);
  });
  return List.unmodifiable(filas);
}

class InterventoriaCategoria {
  final String key;
  final String label;

  const InterventoriaCategoria(this.key, this.label);
}

class CentroCostoRef {
  final String centroId;
  final String empresaId;
  final String codigo;
  final String nombre;
  final String grupo;

  /// Divisiones internas del establecimiento: Cómbita Alta y Media, Picota
  /// ERE 1 y ERE 2. Vacío en la mayoría, que no están divididos.
  final List<SubcentroCosto> subcentros;

  const CentroCostoRef({
    required this.centroId,
    required this.empresaId,
    required this.codigo,
    required this.nombre,
    this.grupo = '',
    this.subcentros = const [],
  });

  /// Subcentros que se pueden elegir hoy. Uno apagado no desaparece del
  /// histórico, solo deja de ofrecerse.
  List<SubcentroCosto> get subcentrosActivos =>
      subcentros.where((s) => s.enabled).toList();

  factory CentroCostoRef.fromMap(String id, Map<String, dynamic> data) {
    final centroId = (data['centroId'] ?? id).toString().trim();
    final codigo = (data['codigo'] ?? '').toString().trim();
    return CentroCostoRef(
      centroId: centroId.isEmpty ? id : centroId,
      empresaId: (data['empresaId'] ?? '').toString().trim(),
      codigo: codigo,
      nombre: (data['nombre'] ?? centroId).toString().trim(),
      grupo: grupoCentroCostoDesdeData(data, codigo: codigo),
      subcentros: subcentrosDesdeData(data['subcentros']),
    );
  }
}

/// Establecimiento como debe leerse: el centro y, si lo hay, el subcentro.
extension EstablecimientoDelHallazgo on InterventoriaHallazgo {
  String get establecimiento =>
      nombreEstablecimiento(centroCostoNombre, subcentroNombre);
}

extension EstablecimientoDeLaVisita on InterventoriaVisita {
  String get establecimiento =>
      nombreEstablecimiento(centroCostoNombre, subcentroNombre);
}

/// Normaliza la clasificación contractual de un establecimiento.
///
/// Se aceptan las variantes habituales de la fuente de datos (G1, Grupo 1,
/// 01, etc.). No se deduce el grupo desde el nombre del establecimiento.
String normalizarGrupoCentroCosto(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  final compact = value.toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '');
  if (compact == '1' ||
      compact == '01' ||
      compact == 'G1' ||
      compact == 'G01' ||
      compact == 'GRUPO1' ||
      compact == 'GRUPO01') {
    return 'G1';
  }
  if (compact == '9' ||
      compact == '09' ||
      compact == 'G9' ||
      compact == 'G09' ||
      compact == 'GRUPO9' ||
      compact == 'GRUPO09') {
    return 'G9';
  }
  return value;
}

/// Lee el grupo real del catálogo. Como compatibilidad, también reconoce G1
/// o G9 cuando forman parte del código técnico del centro, nunca del nombre.
String grupoCentroCostoDesdeData(
  Map<String, dynamic> data, {
  String codigo = '',
}) {
  for (final key in const [
    'grupo',
    'grupoId',
    'grupoNombre',
    'grupoContrato',
    'lote',
  ]) {
    final normalized = normalizarGrupoCentroCosto(data[key]);
    if (normalized.isNotEmpty) return normalized;
  }
  final match = RegExp(
    r'(?:^|[^A-Z0-9])G(?:RUPO)?[\s_-]*0?([19])(?:$|[^0-9])',
    caseSensitive: false,
  ).firstMatch(codigo);
  return match == null ? '' : 'G${match.group(1)}';
}

class GrupoCentrosCosto {
  final String grupo;
  final List<CentroCostoRef> centros;

  const GrupoCentrosCosto({required this.grupo, required this.centros});

  String get label => grupo.isEmpty ? 'Sin grupo' : 'Grupo $grupo';
}

/// Agrupa primero G1 y G9 y ordena alfabéticamente dentro de cada grupo.
/// Las demás clasificaciones se conservan y los centros sin dato quedan
/// explícitamente separados para evitar asignaciones arbitrarias.
List<GrupoCentrosCosto> agruparCentrosCosto(Iterable<CentroCostoRef> centros) {
  final porGrupo = <String, List<CentroCostoRef>>{};
  for (final centro in centros) {
    final grupo = normalizarGrupoCentroCosto(centro.grupo);
    porGrupo.putIfAbsent(grupo, () => <CentroCostoRef>[]).add(centro);
  }
  for (final list in porGrupo.values) {
    list.sort((a, b) {
      final byName = a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      return byName != 0
          ? byName
          : a.codigo.toLowerCase().compareTo(b.codigo.toLowerCase());
    });
  }
  int rank(String group) => switch (group) {
    'G1' => 0,
    'G9' => 1,
    '' => 3,
    _ => 2,
  };
  final groups = porGrupo.entries.toList()
    ..sort((a, b) {
      final byRank = rank(a.key).compareTo(rank(b.key));
      return byRank != 0
          ? byRank
          : a.key.toLowerCase().compareTo(b.key.toLowerCase());
    });
  return groups
      .map((entry) => GrupoCentrosCosto(grupo: entry.key, centros: entry.value))
      .toList(growable: false);
}

/// Una o varias imágenes son una fuente válida porque el registro las
/// convierte a un PDF general antes de persistir la visita.
bool puedeGenerarActaPdf(Iterable<String> contentTypes) => contentTypes.any(
  (type) =>
      type.toLowerCase() == 'application/pdf' ||
      type.toLowerCase().startsWith('image/'),
);

class InterventoriaItem {
  final String key;
  final String label;
  final double? valor;
  final bool noEvaluado;
  final String fuente;
  final double? confianzaOcr;
  final String observacion;
  final List<InterventoriaNota> observaciones;
  final Map<String, dynamic> meta;

  const InterventoriaItem({
    required this.key,
    required this.label,
    this.valor,
    this.noEvaluado = false,
    this.fuente = 'manual',
    this.confianzaOcr,
    this.observacion = '',
    this.observaciones = const [],
    this.meta = const {},
  });

  factory InterventoriaItem.empty(InterventoriaCategoria categoria) =>
      InterventoriaItem(key: categoria.key, label: categoria.label);

  factory InterventoriaItem.fromMap(String key, Map<String, dynamic> data) {
    final rawValor = data['valor'];
    final rawObservaciones =
        (data['observacionesDetalle'] as List?) ?? const [];
    final legacyObservacion = (data['observacion'] ?? '').toString();
    final observaciones = rawObservaciones
        .whereType<Map>()
        .map((m) => InterventoriaNota.fromMap(m.cast<String, dynamic>()))
        .where((n) => n.texto.trim().isNotEmpty)
        .toList();
    return InterventoriaItem(
      key: (data['key'] ?? key).toString(),
      label: (data['label'] ?? key).toString(),
      valor: rawValor is num
          ? rawValor.toDouble()
          : double.tryParse((rawValor ?? '').toString()),
      noEvaluado: data['noEvaluado'] == true || data['estado'] == 'no_evaluado',
      fuente: (data['fuente'] ?? 'manual').toString(),
      confianzaOcr: data['confianzaOcr'] is num
          ? (data['confianzaOcr'] as num).toDouble()
          : null,
      observacion: legacyObservacion,
      observaciones: observaciones.isNotEmpty
          ? observaciones
          : legacyObservacion.trim().isEmpty
          ? const []
          : [
              InterventoriaNota(
                texto: legacyObservacion.trim(),
                fuente: (data['fuente'] ?? 'manual').toString(),
              ),
            ],
      meta: ((data['meta'] as Map?) ?? const {}).cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toMap() => {
    'key': key,
    'label': label,
    'valor': valor,
    'noEvaluado': noEvaluado,
    'estado': noEvaluado ? 'no_evaluado' : 'evaluado',
    'fuente': fuente,
    'confianzaOcr': confianzaOcr,
    'observacion': observaciones.isNotEmpty
        ? observaciones.map((n) => n.texto.trim()).join('\n')
        : observacion,
    'observacionesDetalle': observaciones.map((n) => n.toMap()).toList(),
    'meta': meta,
  };

  InterventoriaItem copyWith({
    double? valor,
    bool? noEvaluado,
    String? fuente,
    double? confianzaOcr,
    String? observacion,
    List<InterventoriaNota>? observaciones,
    Map<String, dynamic>? meta,
    bool clearValor = false,
  }) => InterventoriaItem(
    key: key,
    label: label,
    valor: clearValor ? null : (valor ?? this.valor),
    noEvaluado: noEvaluado ?? this.noEvaluado,
    fuente: fuente ?? this.fuente,
    confianzaOcr: confianzaOcr ?? this.confianzaOcr,
    observacion: observacion ?? this.observacion,
    observaciones: observaciones ?? this.observaciones,
    meta: meta ?? this.meta,
  );
}

class InterventoriaNota {
  final String aspecto;
  final String texto;
  final String fuente;
  final Timestamp? createdAt;

  const InterventoriaNota({
    this.aspecto = '',
    required this.texto,
    this.fuente = 'manual',
    this.createdAt,
  });

  factory InterventoriaNota.fromMap(Map<String, dynamic> data) =>
      InterventoriaNota(
        aspecto: (data['aspecto'] ?? '').toString(),
        texto: (data['texto'] ?? '').toString(),
        fuente: (data['fuente'] ?? 'manual').toString(),
        createdAt: data['createdAt'] as Timestamp?,
      );

  Map<String, dynamic> toMap() => {
    'aspecto': aspecto,
    'texto': texto,
    'fuente': fuente,
    'createdAt': createdAt ?? Timestamp.now(),
  };

  InterventoriaNota copyWith({
    String? aspecto,
    String? texto,
    String? fuente,
  }) => InterventoriaNota(
    aspecto: aspecto ?? this.aspecto,
    texto: texto ?? this.texto,
    fuente: fuente ?? this.fuente,
    createdAt: createdAt,
  );
}

class InterventoriaAdjunto {
  final String url;
  final String nombre;
  final String path;
  final String contentType;
  final String origen;
  final Timestamp fechaSubida;

  const InterventoriaAdjunto({
    required this.url,
    required this.nombre,
    required this.path,
    required this.contentType,
    required this.origen,
    required this.fechaSubida,
  });

  factory InterventoriaAdjunto.fromMap(Map<String, dynamic> data) =>
      InterventoriaAdjunto(
        url: (data['url'] ?? '').toString(),
        nombre: (data['nombre'] ?? '').toString(),
        path: (data['path'] ?? '').toString(),
        contentType: (data['contentType'] ?? '').toString(),
        origen: (data['origen'] ?? 'web').toString(),
        fechaSubida: data['fechaSubida'] as Timestamp? ?? Timestamp.now(),
      );

  Map<String, dynamic> toMap() => {
    'url': url,
    'nombre': nombre,
    'path': path,
    'contentType': contentType,
    'origen': origen,
    'fechaSubida': fechaSubida,
  };
}

bool contieneActaPdf(Iterable<InterventoriaAdjunto> adjuntos) => adjuntos.any(
  (adjunto) => adjunto.contentType.toLowerCase() == 'application/pdf',
);

class InterventoriaVisita {
  final String id;
  final String empresaId;
  final String centroCostoId;
  final String centroCostoCodigo;
  final String centroCostoNombre;

  /// División interna del establecimiento, cuando la tiene. El responsable se
  /// sigue resolviendo por el centro: la gente está adscrita a Cómbita, no a
  /// "Cómbita Alta".
  final String subcentroId;
  final String subcentroNombre;

  final Timestamp fechaVisita;
  final Timestamp fechaRegistro;
  final String creadoPor;
  final String estado;
  final String? tipoActa;
  final String? tiempoComida;
  final double porcentajeGeneral;
  final Map<String, InterventoriaItem> items;
  final List<InterventoriaAdjunto> adjuntos;
  final String actaOriginalUrl;
  final String ocrTextoExtraido;
  final Map<String, dynamic> ocrDatosDetectados;
  final bool ocrRevisado;
  final String observaciones;

  /// 'puntajes' = Fase 1 completa (admin registró puntajes, pendiente de revisión)
  /// 'completa'  = Fase 2 completa (revisor completó observaciones y conclusiones)
  /// ''          = actas antiguas → se tratan como 'completa' por retrocompatibilidad
  final String faseActa;
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  const InterventoriaVisita({
    this.id = '',
    required this.empresaId,
    required this.centroCostoId,
    required this.centroCostoCodigo,
    required this.centroCostoNombre,
    this.subcentroId = '',
    this.subcentroNombre = '',
    required this.fechaVisita,
    required this.fechaRegistro,
    required this.creadoPor,
    this.estado = 'registrada',
    this.tipoActa,
    this.tiempoComida,
    required this.porcentajeGeneral,
    required this.items,
    this.adjuntos = const [],
    this.actaOriginalUrl = '',
    this.ocrTextoExtraido = '',
    this.ocrDatosDetectados = const {},
    this.ocrRevisado = false,
    this.observaciones = '',
    this.faseActa = 'completa',
    required this.createdAt,
    this.updatedAt,
  });

  factory InterventoriaVisita.fromMap(String id, Map<String, dynamic> data) {
    final rawItems = (data['itemsEvaluacion'] as Map?) ?? const {};
    final items = <String, InterventoriaItem>{};
    for (final categoria in kInterventoriaCategorias) {
      final raw = rawItems[categoria.key];
      if (raw is Map) {
        items[categoria.key] = InterventoriaItem.fromMap(
          categoria.key,
          raw.cast<String, dynamic>(),
        );
      } else {
        items[categoria.key] = InterventoriaItem.empty(categoria);
      }
    }
    return InterventoriaVisita(
      id: id,
      empresaId: (data['empresaId'] ?? '').toString(),
      centroCostoId: (data['centroCostoId'] ?? '').toString(),
      centroCostoCodigo: (data['centroCostoCodigo'] ?? '').toString(),
      centroCostoNombre: (data['centroCostoNombre'] ?? '').toString(),
      subcentroId: (data['subcentroId'] ?? '').toString(),
      subcentroNombre: (data['subcentroNombre'] ?? '').toString(),
      fechaVisita: data['fechaVisita'] as Timestamp? ?? Timestamp.now(),
      fechaRegistro: data['fechaRegistro'] as Timestamp? ?? Timestamp.now(),
      creadoPor: (data['creadoPor'] ?? '').toString(),
      estado: (data['estado'] ?? 'registrada').toString(),
      tipoActa: data['tipoActa']?.toString(),
      tiempoComida: data['tiempoComida']?.toString(),
      porcentajeGeneral: data['porcentajeGeneral'] is num
          ? (data['porcentajeGeneral'] as num).toDouble()
          : 0,
      items: items,
      adjuntos: ((data['imagenesActa'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => InterventoriaAdjunto.fromMap(m.cast<String, dynamic>()))
          .toList(),
      actaOriginalUrl: (data['actaOriginalUrl'] ?? '').toString(),
      ocrTextoExtraido: (data['ocrTextoExtraido'] ?? '').toString(),
      ocrDatosDetectados: ((data['ocrDatosDetectados'] as Map?) ?? const {})
          .cast<String, dynamic>(),
      ocrRevisado: data['ocrRevisado'] == true,
      observaciones: (data['observaciones'] ?? '').toString(),
      // Actas antiguas sin faseActa se tratan como completadas
      faseActa: (data['faseActa'] ?? 'completa').toString(),
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'centroCostoId': centroCostoId,
    'centroCostoCodigo': centroCostoCodigo,
    'centroCostoNombre': centroCostoNombre,
    'subcentroId': subcentroId,
    'subcentroNombre': subcentroNombre,
    'fechaVisita': fechaVisita,
    'fechaRegistro': fechaRegistro,
    'creadoPor': creadoPor,
    'estado': estado,
    'tipoActa': tipoActa,
    'tiempoComida': tiempoComida,
    'porcentajeGeneral': porcentajeGeneral,
    'itemsEvaluacion': items.map((key, value) => MapEntry(key, value.toMap())),
    'totalCondicionesServicio': porcentajeGeneral,
    'imagenesActa': adjuntos.map((a) => a.toMap()).toList(),
    'actaOriginalUrl': actaOriginalUrl,
    'ocrTextoExtraido': ocrTextoExtraido,
    'ocrDatosDetectados': ocrDatosDetectados,
    'ocrRevisado': ocrRevisado,
    'observaciones': observaciones,
    'faseActa': faseActa,
    'createdAt': createdAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Punto del comparativo directivo: representa exclusivamente la acta más
/// reciente de un establecimiento dentro del rango filtrado.
class InterventoriaComparativoActa {
  final String visitaId;
  final String centroCostoId;
  final String centroCostoCodigo;
  final String centroCostoNombre;
  final DateTime fecha;
  final double? valor;

  const InterventoriaComparativoActa({
    required this.visitaId,
    required this.centroCostoId,
    required this.centroCostoCodigo,
    required this.centroCostoNombre,
    required this.fecha,
    required this.valor,
  });
}

/// Construye el comparativo solicitado para la vista "Todos".
///
/// Primero conserva la última acta de cada establecimiento y solo después
/// calcula el valor de la categoría. De esta forma una categoría sin evaluar
/// en la última acta se muestra como "Sin dato" y nunca se reemplaza, de forma
/// engañosa, por el resultado de una visita anterior.
List<InterventoriaComparativoActa> compararUltimaActaPorEstablecimiento(
  List<InterventoriaVisita> visitas, {
  String categoriaKey = '',
}) {
  final ultimas = <String, InterventoriaVisita>{};
  for (final visita in visitas) {
    final id = visita.centroCostoId.trim();
    final fallback = visita.centroCostoNombre.trim().toLowerCase();
    final key = id.isNotEmpty ? id : fallback;
    if (key.isEmpty) continue;
    final actual = ultimas[key];
    if (actual == null ||
        visita.fechaVisita.toDate().isAfter(actual.fechaVisita.toDate())) {
      ultimas[key] = visita;
    }
  }

  final puntos = ultimas.values.map((visita) {
    double? valor;
    if (categoriaKey.isEmpty) {
      valor = visita.porcentajeGeneral.clamp(0, 100).toDouble();
    } else {
      final item = visita.items[categoriaKey];
      if (item != null && !item.noEvaluado && item.valor != null) {
        valor = item.valor!.clamp(0, 100).toDouble();
      }
    }
    return InterventoriaComparativoActa(
      visitaId: visita.id,
      centroCostoId: visita.centroCostoId,
      centroCostoCodigo: visita.centroCostoCodigo,
      centroCostoNombre: visita.centroCostoNombre,
      fecha: visita.fechaVisita.toDate(),
      valor: valor,
    );
  }).toList();

  puntos.sort(
    (a, b) => a.centroCostoNombre.toLowerCase().compareTo(
      b.centroCostoNombre.toLowerCase(),
    ),
  );
  return puntos;
}

class InterventoriaRolDoc {
  final String id;
  final String empresaId;
  final String userId;
  final String cedula;
  final String nombre;
  final String rol;
  final Timestamp createdAt;

  const InterventoriaRolDoc({
    this.id = '',
    required this.empresaId,
    required this.userId,
    required this.cedula,
    required this.nombre,
    required this.rol,
    required this.createdAt,
  });

  factory InterventoriaRolDoc.fromMap(String id, Map<String, dynamic> data) =>
      InterventoriaRolDoc(
        id: id,
        empresaId: (data['empresaId'] ?? '').toString(),
        userId: (data['userId'] ?? '').toString(),
        cedula: (data['cedula'] ?? '').toString(),
        nombre: (data['nombre'] ?? '').toString(),
        rol: (data['rol'] ?? '').toString(),
        createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'userId': userId,
    'cedula': cedula,
    'nombre': nombre,
    'rol': rol,
    'createdAt': createdAt,
  };
}

Map<String, InterventoriaItem> defaultInterventoriaItems() => {
  for (final categoria in kInterventoriaCategorias)
    categoria.key: InterventoriaItem.empty(categoria),
};

double calcularPorcentajeGeneral(Map<String, InterventoriaItem> items) {
  final evaluados = items.values
      .where((item) => !item.noEvaluado && item.valor != null)
      .map((item) => item.valor!.clamp(0, 100).toDouble())
      .toList();
  if (evaluados.isEmpty) return 0;
  final total = evaluados.fold<double>(
    0,
    (accumulated, value) => accumulated + value,
  );
  return double.parse((total / evaluados.length).toStringAsFixed(2));
}

String interventoriaSemaforo(double porcentaje) {
  if (porcentaje >= 90) return 'verde';
  if (porcentaje >= 70) return 'amarillo';
  return 'rojo';
}

// ─────────────────────────────────────────────────────────────────────────────
// Hallazgos
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kDptosInterventoria = [
  'ADMINISTRADOR',
  'BODEGA',
  'CALIDAD',
  'COMPRAS',
  'DIRECTIVA',
  'EQUIPO Y MENAJE',
  'INGENIERO DE PRODUCCIÓN',
  'MANTENIMIENTO',
  'NUTRICIONISTA',
  'PLANEACIÓN',
  'TALENTO HUMANO',
];

/// Tipos de acta.
///
/// REGULAR y SEGUIMIENTO evalúan todas las categorías; se distinguen solo por
/// el propósito de la visita, y por eso SEGUIMIENTO no necesita ningún trato
/// especial en `_onTipoActaChanged`: cae en la rama por defecto y hereda el
/// comportamiento completo.
///
/// INFRAESTRUCTURA y ESTACION_POLICIA son formularios propios: traen su
/// catálogo de aspectos en `interventoria_actas_catalogo.dart` y no evalúan las
/// categorías del acta regular.
const List<String> kTiposActaInterventoria = [
  kActaRegular,
  kActaSeguimiento,
  kActaInfraestructura,
  kActaEstacionPolicia,
];

const List<String> kTiemposComidaInterventoria = [
  'DESAYUNO',
  'ALMUERZO',
  'CENA',
];

class InterventoriaHallazgo {
  final String id;
  final String empresaId;
  final String visitaId;
  final String centroCostoId;
  final String centroCostoNombre;

  /// División interna del establecimiento. Solo informativa: el responsable se
  /// resuelve por `centroCostoId`, que es donde está adscrita la gente.
  final String subcentroId;
  final String subcentroNombre;

  final String grupoId;
  final String estado; // 'activo' | 'pendiente_aprobacion' | 'subsanado'
  final String? tipoActa;
  final String numeroHallazgo; // e.g. "1.1", "10.20"
  /// Numeral REAL del acta ("2.14"), cuando se pudo determinar con certeza.
  ///
  /// No siempre coincide con [numeroHallazgo]: en los hallazgos generados desde
  /// el formulario del acta ese campo es un ordinal (categoría.observación), no
  /// el numeral. Este campo es el único válido para consultar la matriz de
  /// responsabilidad; vacío = numeral desconocido → asignación manual.
  final String numeralActa;
  final String descripcion;
  final Timestamp fechaHallazgo;
  final bool persiste;
  final String dptoEncargado; // nombre del área para mostrar
  final String areaId; // doc ID en TBL_AREAS (para buscar director)
  final String observaciones;
  final String planMejora;
  final double? valorCorreccion;
  final Timestamp? fechaSubsanacion;
  final String seguimiento;
  final List<InterventoriaAdjunto> adjuntosSubsanacion;
  final String fuente; // 'manual' | 'ocr'
  /// Puntaje de la sección al momento de crear el hallazgo (0-100). Null = no registrado.
  final double? puntajeSeccion;

  /// Nota adicional del Registrador: contexto, causa, justificación.
  final String notaRegistrador;

  /// ID de la tarea creada en TBL_TAREAS cuando se asigna el hallazgo a un dpto.
  final String tareaId;

  /// Persona que debe subsanar, resuelta desde la matriz de numerales del acta.
  final String responsableId;
  final String responsableNombre;

  /// Cargo que la matriz asigna al numeral (p. ej. "Administrador").
  final String cargoResponsable;

  /// Persona que aprueba la subsanación (jefe de la tarea).
  final String aprobadorId;
  final String aprobadorNombre;
  final String cargoAprobador;

  /// Fecha límite pactada para subsanar; es la misma de la tarea.
  final Timestamp? fechaLimite;
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  const InterventoriaHallazgo({
    this.id = '',
    required this.empresaId,
    this.visitaId = '',
    required this.centroCostoId,
    required this.centroCostoNombre,
    this.subcentroId = '',
    this.subcentroNombre = '',
    this.grupoId = '',
    this.estado = 'activo',
    this.tipoActa,
    this.numeroHallazgo = '',
    this.numeralActa = '',
    required this.descripcion,
    required this.fechaHallazgo,
    this.persiste = false,
    this.dptoEncargado = '',
    this.areaId = '',
    this.observaciones = '',
    this.planMejora = '',
    this.valorCorreccion,
    this.fechaSubsanacion,
    this.seguimiento = '',
    this.adjuntosSubsanacion = const [],
    this.fuente = 'manual',
    this.puntajeSeccion,
    this.notaRegistrador = '',
    this.tareaId = '',
    this.responsableId = '',
    this.responsableNombre = '',
    this.cargoResponsable = '',
    this.aprobadorId = '',
    this.aprobadorNombre = '',
    this.cargoAprobador = '',
    this.fechaLimite,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isSubsanado => estado == 'subsanado';
  bool get isPendienteAprobacion => estado == 'pendiente_aprobacion';

  int get seccion {
    final parts = numeroHallazgo.split('.');
    return int.tryParse(parts.first) ?? 0;
  }

  /// Numeral con el que se consulta la matriz de responsabilidad.
  ///
  /// Vacío cuando no se puede saber a qué numeral corresponde el hallazgo; en
  /// ese caso la asignación sigue siendo manual. En los hallazgos generados
  /// desde el formulario del acta NUNCA se usa [numeroHallazgo], porque ahí es
  /// un ordinal (categoría.observación) y apuntaría a otro numeral.
  String get numeralParaMatriz {
    final explicito = numeralActa.trim();
    if (explicito.isNotEmpty) return normalizarNumeralActa(explicito);
    if (fuente == 'acta') return '';
    return normalizarNumeralActa(numeroHallazgo);
  }

  factory InterventoriaHallazgo.fromMap(String id, Map<String, dynamic> data) =>
      InterventoriaHallazgo(
        id: id,
        empresaId: (data['empresaId'] ?? '').toString(),
        visitaId: (data['visitaId'] ?? '').toString(),
        centroCostoId: (data['centroCostoId'] ?? '').toString(),
        centroCostoNombre: (data['centroCostoNombre'] ?? '').toString(),
        subcentroId: (data['subcentroId'] ?? '').toString(),
        subcentroNombre: (data['subcentroNombre'] ?? '').toString(),
        grupoId: (data['grupoId'] ?? '').toString(),
        estado: (data['estado'] ?? 'activo').toString(),
        tipoActa: data['tipoActa']?.toString(),
        numeroHallazgo: (data['numeroHallazgo'] ?? '').toString(),
        numeralActa: (data['numeralActa'] ?? '').toString(),
        descripcion: (data['descripcion'] ?? '').toString(),
        fechaHallazgo: data['fechaHallazgo'] as Timestamp? ?? Timestamp.now(),
        persiste: data['persiste'] == true,
        dptoEncargado: (data['dptoEncargado'] ?? '').toString(),
        areaId: (data['areaId'] ?? '').toString(),
        observaciones: (data['observaciones'] ?? '').toString(),
        planMejora: (data['planMejora'] ?? '').toString(),
        valorCorreccion: data['valorCorreccion'] is num
            ? (data['valorCorreccion'] as num).toDouble()
            : null,
        fechaSubsanacion: data['fechaSubsanacion'] as Timestamp?,
        seguimiento: (data['seguimiento'] ?? '').toString(),
        adjuntosSubsanacion: (data['adjuntosSubsanacion'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (raw) =>
                  InterventoriaAdjunto.fromMap(Map<String, dynamic>.from(raw)),
            )
            .toList(),
        fuente: (data['fuente'] ?? 'manual').toString(),
        puntajeSeccion: data['puntajeSeccion'] is num
            ? (data['puntajeSeccion'] as num).toDouble()
            : null,
        notaRegistrador: (data['notaRegistrador'] ?? '').toString(),
        tareaId: (data['tareaId'] ?? '').toString(),
        responsableId: (data['responsableId'] ?? '').toString(),
        responsableNombre: (data['responsableNombre'] ?? '').toString(),
        cargoResponsable: (data['cargoResponsable'] ?? '').toString(),
        aprobadorId: (data['aprobadorId'] ?? '').toString(),
        aprobadorNombre: (data['aprobadorNombre'] ?? '').toString(),
        cargoAprobador: (data['cargoAprobador'] ?? '').toString(),
        fechaLimite: data['fechaLimite'] as Timestamp?,
        createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
        updatedAt: data['updatedAt'] as Timestamp?,
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'visitaId': visitaId,
    'centroCostoId': centroCostoId,
    'centroCostoNombre': centroCostoNombre,
    'subcentroId': subcentroId,
    'subcentroNombre': subcentroNombre,
    'grupoId': grupoId,
    'estado': estado,
    'tipoActa': tipoActa,
    'numeroHallazgo': numeroHallazgo,
    'numeralActa': numeralActa,
    'descripcion': descripcion,
    'fechaHallazgo': fechaHallazgo,
    'persiste': persiste,
    'dptoEncargado': dptoEncargado,
    'areaId': areaId,
    'observaciones': observaciones,
    'planMejora': planMejora,
    'valorCorreccion': valorCorreccion,
    'fechaSubsanacion': fechaSubsanacion,
    'seguimiento': seguimiento,
    'adjuntosSubsanacion': adjuntosSubsanacion.map((a) => a.toMap()).toList(),
    'fuente': fuente,
    'puntajeSeccion': puntajeSeccion,
    'notaRegistrador': notaRegistrador,
    'tareaId': tareaId,
    'responsableId': responsableId,
    'responsableNombre': responsableNombre,
    'cargoResponsable': cargoResponsable,
    'aprobadorId': aprobadorId,
    'aprobadorNombre': aprobadorNombre,
    'cargoAprobador': cargoAprobador,
    'fechaLimite': fechaLimite,
    'createdAt': createdAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Mismo hallazgo, ya con el id que le asignó Firestore. Se usa cuando un
  /// hallazgo derivado de un acta se persiste por primera vez.
  InterventoriaHallazgo copyWithId(String nuevoId) => InterventoriaHallazgo(
    id: nuevoId,
    empresaId: empresaId,
    visitaId: visitaId,
    centroCostoId: centroCostoId,
    centroCostoNombre: centroCostoNombre,
    subcentroId: subcentroId,
    subcentroNombre: subcentroNombre,
    grupoId: grupoId,
    estado: estado,
    tipoActa: tipoActa,
    numeroHallazgo: numeroHallazgo,
    numeralActa: numeralActa,
    descripcion: descripcion,
    fechaHallazgo: fechaHallazgo,
    persiste: persiste,
    dptoEncargado: dptoEncargado,
    areaId: areaId,
    observaciones: observaciones,
    planMejora: planMejora,
    valorCorreccion: valorCorreccion,
    fechaSubsanacion: fechaSubsanacion,
    seguimiento: seguimiento,
    adjuntosSubsanacion: adjuntosSubsanacion,
    fuente: fuente,
    puntajeSeccion: puntajeSeccion,
    notaRegistrador: notaRegistrador,
    tareaId: tareaId,
    responsableId: responsableId,
    responsableNombre: responsableNombre,
    cargoResponsable: cargoResponsable,
    aprobadorId: aprobadorId,
    aprobadorNombre: aprobadorNombre,
    cargoAprobador: cargoAprobador,
    fechaLimite: fechaLimite,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  InterventoriaHallazgo copyWith({
    String? estado,
    String? numeroHallazgo,
    String? numeralActa,
    String? descripcion,
    String? dptoEncargado,
    String? areaId,
    String? observaciones,
    String? planMejora,
    double? valorCorreccion,
    bool clearValorCorreccion = false,
    Timestamp? fechaSubsanacion,
    bool clearFechaSubsanacion = false,
    String? seguimiento,
    List<InterventoriaAdjunto>? adjuntosSubsanacion,
    bool? persiste,
    double? puntajeSeccion,
    String? notaRegistrador,
    String? tareaId,
    String? responsableId,
    String? responsableNombre,
    String? cargoResponsable,
    String? aprobadorId,
    String? aprobadorNombre,
    String? cargoAprobador,
    Timestamp? fechaLimite,
  }) => InterventoriaHallazgo(
    id: id,
    empresaId: empresaId,
    visitaId: visitaId,
    centroCostoId: centroCostoId,
    centroCostoNombre: centroCostoNombre,
    subcentroId: subcentroId,
    subcentroNombre: subcentroNombre,
    grupoId: grupoId,
    estado: estado ?? this.estado,
    tipoActa: tipoActa,
    numeroHallazgo: numeroHallazgo ?? this.numeroHallazgo,
    numeralActa: numeralActa ?? this.numeralActa,
    descripcion: descripcion ?? this.descripcion,
    fechaHallazgo: fechaHallazgo,
    persiste: persiste ?? this.persiste,
    dptoEncargado: dptoEncargado ?? this.dptoEncargado,
    areaId: areaId ?? this.areaId,
    observaciones: observaciones ?? this.observaciones,
    planMejora: planMejora ?? this.planMejora,
    valorCorreccion: clearValorCorreccion
        ? null
        : (valorCorreccion ?? this.valorCorreccion),
    fechaSubsanacion: clearFechaSubsanacion
        ? null
        : (fechaSubsanacion ?? this.fechaSubsanacion),
    seguimiento: seguimiento ?? this.seguimiento,
    adjuntosSubsanacion: adjuntosSubsanacion ?? this.adjuntosSubsanacion,
    fuente: fuente,
    puntajeSeccion: puntajeSeccion ?? this.puntajeSeccion,
    notaRegistrador: notaRegistrador ?? this.notaRegistrador,
    tareaId: tareaId ?? this.tareaId,
    responsableId: responsableId ?? this.responsableId,
    responsableNombre: responsableNombre ?? this.responsableNombre,
    cargoResponsable: cargoResponsable ?? this.cargoResponsable,
    aprobadorId: aprobadorId ?? this.aprobadorId,
    aprobadorNombre: aprobadorNombre ?? this.aprobadorNombre,
    cargoAprobador: cargoAprobador ?? this.cargoAprobador,
    fechaLimite: fechaLimite ?? this.fechaLimite,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

double calcularScoreHallazgos(List<InterventoriaHallazgo> hallazgos) {
  if (hallazgos.isEmpty) return 0;
  final subsanados = hallazgos.where((h) => h.isSubsanado).length;
  return double.parse((subsanados / hallazgos.length * 100).toStringAsFixed(2));
}
