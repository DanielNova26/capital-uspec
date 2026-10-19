import 'package:cloud_functions/cloud_functions.dart';

import '../interventoria/interventoria_service.dart';

/// Estado de entrega de un aviso, tal como lo deja `onNotificationCreated`
/// en `pushDelivery.state`.
enum EntregaAviso {
  entregado,
  pendiente,
  fallido,

  /// La persona no tiene dispositivo registrado, o el push de ese tipo está
  /// apagado: el aviso solo vive en la campana.
  soloApp,

  /// Persona inhabilitada: no se le manda nada.
  omitido,
  sinEstado;

  static EntregaAviso desde(String crudo) => switch (crudo) {
    'delivered' => entregado,
    'pending' => pendiente,
    'failed' => fallido,
    'in_app_only' => soloApp,
    'omitido_inhabilitado' => omitido,
    _ => sinEstado,
  };

  String get etiqueta => switch (this) {
    entregado => 'Entregado',
    pendiente => 'Reintentando',
    fallido => 'Falló',
    soloApp => 'Solo en la app',
    omitido => 'Inhabilitado',
    sinEstado => 'Sin registro',
  };

  /// Entregas que merecen revisión.
  bool get requiereAtencion =>
      this == fallido || this == pendiente || this == sinEstado;
}

/// Una fila del monitor: un aviso que llegó (o debió llegar) a una persona.
class AvisoMonitor {
  const AvisoMonitor({
    required this.id,
    required this.userId,
    required this.titulo,
    required this.descripcion,
    required this.tipo,
    required this.modulo,
    required this.taskId,
    required this.taskNumero,
    required this.creada,
    required this.leida,
    required this.silenciosa,
    required this.entrega,
    required this.intentos,
    required this.error,
    required this.sedeId,
    required this.sedeNombre,
    required this.deNombre,
  });

  final String id;
  final String userId;
  final String titulo;
  final String descripcion;
  final String tipo;
  final String modulo;
  final String taskId;
  final int? taskNumero;
  final DateTime creada;
  final bool leida;
  final bool silenciosa;
  final EntregaAviso entrega;
  final int intentos;
  final String error;
  final String sedeId;
  final String sedeNombre;
  final String deNombre;

  factory AvisoMonitor.fromMap(Map<dynamic, dynamic> m) {
    String t(String k) => (m[k] ?? '').toString().trim();
    return AvisoMonitor(
      id: t('id'),
      userId: t('userId'),
      titulo: t('titulo'),
      descripcion: t('descripcion'),
      tipo: t('tipo'),
      modulo: t('modulo'),
      taskId: t('taskId'),
      taskNumero: m['taskNumero'] is num ? (m['taskNumero'] as num).toInt() : null,
      creada: DateTime.fromMillisecondsSinceEpoch(
        m['creadaMs'] is num ? (m['creadaMs'] as num).toInt() : 0,
      ),
      leida: m['leida'] == true,
      silenciosa: m['silenciosa'] == true,
      entrega: EntregaAviso.desde(t('entrega')),
      intentos: m['intentos'] is num ? (m['intentos'] as num).toInt() : 0,
      error: t('error'),
      sedeId: t('sedeId'),
      sedeNombre: t('sedeNombre'),
      deNombre: t('deNombre'),
    );
  }

  /// Aviso de "te toca subsanar" de Interventoría: el que debe llegar a quien
  /// trabaja en la sede del hallazgo. El del aprobador va en silencio y el de
  /// seguimiento es otro tipo, así que no cuentan para esta alerta.
  bool get esAsignacionDeInterventoria =>
      modulo == 'interventoria' && tipo == 'task_assigned' && !silenciosa;
}

/// ¿El aviso llegó a alguien que no cubre la sede del hallazgo? Usa la misma
/// cobertura con la que Interventoría asigna (centros de operación y de
/// trabajo, y los de sus grupos). Si no se conoce a la persona no se acusa.
bool llegoFueraDeSede(AvisoMonitor aviso, InterventoriaUsuario? persona) =>
    aviso.esAsignacionDeInterventoria &&
    aviso.sedeId.isNotEmpty &&
    persona != null &&
    !persona.cubreCentro(aviso.sedeId);

class ResumenPersonaMonitor {
  ResumenPersonaMonitor(this.userId, this.nombre, this.cargo);

  final String userId;
  final String nombre;
  final String cargo;
  int total = 0;
  int sinLeer = 0;
  int conProblema = 0;
  int fueraDeSede = 0;
  final Set<String> sedesRecibidas = {};
}

class ResumenSedeMonitor {
  ResumenSedeMonitor(this.sedeId, this.nombre);

  final String sedeId;
  final String nombre;
  int total = 0;
  int sinLeer = 0;
  int fueraDeSede = 0;

  /// Persona → avisos recibidos de esta sede.
  final Map<String, int> personas = {};

  /// Personas que reciben la sede sin cubrirla.
  final Set<String> personasFuera = {};
}

class AnalisisMonitor {
  AnalisisMonitor({
    required this.total,
    required this.sinLeer,
    required this.entregados,
    required this.soloApp,
    required this.conProblema,
    required this.omitidos,
    required this.fueraDeSede,
    required this.personas,
    required this.sedes,
    required this.alertas,
  });

  final int total;
  final int sinLeer;
  final int entregados;
  final int soloApp;
  final int conProblema;
  final int omitidos;
  final int fueraDeSede;
  final List<ResumenPersonaMonitor> personas;
  final List<ResumenSedeMonitor> sedes;

  /// Avisos que llegaron a alguien que no cubre la sede, del más nuevo al más
  /// viejo.
  final List<AvisoMonitor> alertas;
}

const String kSinSedeMonitor = '_sin_sede';

/// Resume los avisos por persona y por establecimiento. Pura: recibe la
/// cobertura ya cargada y no toca Firestore.
AnalisisMonitor analizarMonitor(
  Iterable<AvisoMonitor> avisos,
  Map<String, InterventoriaUsuario> usuarios,
) {
  final personas = <String, ResumenPersonaMonitor>{};
  final sedes = <String, ResumenSedeMonitor>{};
  final alertas = <AvisoMonitor>[];
  var total = 0;
  var sinLeer = 0;
  var entregados = 0;
  var soloApp = 0;
  var conProblema = 0;
  var omitidos = 0;

  for (final a in avisos) {
    total++;
    if (!a.leida) sinLeer++;
    switch (a.entrega) {
      case EntregaAviso.entregado:
        entregados++;
      case EntregaAviso.soloApp:
        soloApp++;
      case EntregaAviso.omitido:
        omitidos++;
      case EntregaAviso.fallido:
      case EntregaAviso.pendiente:
      case EntregaAviso.sinEstado:
        conProblema++;
    }
    final u = usuarios[a.userId];
    final fuera = llegoFueraDeSede(a, u);
    if (fuera) alertas.add(a);

    final p = personas.putIfAbsent(
      a.userId,
      () => ResumenPersonaMonitor(
        a.userId,
        u?.nombre ?? a.userId,
        u?.cargo ?? '',
      ),
    );
    p.total++;
    if (!a.leida) p.sinLeer++;
    if (a.entrega.requiereAtencion) p.conProblema++;
    if (fuera) p.fueraDeSede++;
    if (a.sedeNombre.isNotEmpty) p.sedesRecibidas.add(a.sedeNombre);

    final clave = a.sedeId.isEmpty ? kSinSedeMonitor : a.sedeId;
    final s = sedes.putIfAbsent(
      clave,
      () => ResumenSedeMonitor(
        clave,
        a.sedeId.isEmpty
            ? 'Sin establecimiento'
            : (a.sedeNombre.isEmpty ? a.sedeId : a.sedeNombre),
      ),
    );
    s.total++;
    if (!a.leida) s.sinLeer++;
    s.personas[a.userId] = (s.personas[a.userId] ?? 0) + 1;
    if (fuera) {
      s.fueraDeSede++;
      s.personasFuera.add(a.userId);
    }
  }

  alertas.sort((x, y) => y.creada.compareTo(x.creada));
  final listaPersonas = personas.values.toList()
    ..sort((a, b) {
      final porAlerta = b.fueraDeSede.compareTo(a.fueraDeSede);
      if (porAlerta != 0) return porAlerta;
      return b.total.compareTo(a.total);
    });
  final listaSedes = sedes.values.toList()
    ..sort((a, b) {
      final porAlerta = b.fueraDeSede.compareTo(a.fueraDeSede);
      if (porAlerta != 0) return porAlerta;
      return b.total.compareTo(a.total);
    });
  return AnalisisMonitor(
    total: total,
    sinLeer: sinLeer,
    entregados: entregados,
    soloApp: soloApp,
    conProblema: conProblema,
    omitidos: omitidos,
    fueraDeSede: alertas.length,
    personas: listaPersonas,
    sedes: listaSedes,
    alertas: alertas,
  );
}

class DatosMonitor {
  const DatosMonitor({
    required this.avisos,
    required this.usuarios,
    required this.truncado,
    required this.dias,
  });

  final List<AvisoMonitor> avisos;
  final Map<String, InterventoriaUsuario> usuarios;

  /// Llegó al tope de lectura: hay más avisos de los que se ven.
  final bool truncado;
  final int dias;
}

/// Lee el monitor: los avisos los trae la función de servidor (las reglas no
/// dejan al cliente leer las bandejas de otras personas) y la cobertura de
/// cada persona sale del mismo servicio con que Interventoría asigna.
class NotificationMonitorService {
  NotificationMonitorService({
    FirebaseFunctions? functions,
    InterventoriaService? interventoria,
  }) : _functions = functions ?? FirebaseFunctions.instance,
       _interventoria = interventoria;

  final FirebaseFunctions _functions;
  final InterventoriaService? _interventoria;

  Future<DatosMonitor> cargar({
    required String empresaId,
    int dias = 7,
  }) async {
    final svc = _interventoria ?? InterventoriaService();
    final resultados = await Future.wait<Object>([
      _functions
          .httpsCallable(
            'adminMonitorNotificaciones',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
          )
          .call({'empresaId': empresaId, 'dias': dias})
          .then((r) => Map<String, dynamic>.from(r.data as Map)),
      svc.listarUsuariosActivos(empresaId),
    ]);
    final datos = resultados[0] as Map<String, dynamic>;
    final usuarios = resultados[1] as List<InterventoriaUsuario>;
    return DatosMonitor(
      avisos: [
        for (final f in (datos['filas'] as List? ?? const []))
          AvisoMonitor.fromMap(f as Map),
      ],
      usuarios: {for (final u in usuarios) u.id: u},
      truncado: datos['truncado'] == true,
      dias: (datos['dias'] as num?)?.toInt() ?? dias,
    );
  }
}
