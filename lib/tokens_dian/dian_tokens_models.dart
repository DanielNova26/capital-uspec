class DianTokenRecord {
  final String id;
  final String empresaId;
  final String estado;
  final DateTime? recibidoAt;
  final DateTime? venceAt;
  final String remitente;
  final String asunto;
  final String buzon;
  final String proveedor;
  final String nitRelacionado;
  final String sourceMessageId;
  final int accessCount;
  final DateTime? firstOpenedAt;
  final String firstOpenedBy;
  final String firstOpenedByName;
  final DateTime? lastOpenedAt;
  final String lastOpenedBy;
  final String lastOpenedByName;

  const DianTokenRecord({
    required this.id,
    required this.empresaId,
    required this.estado,
    required this.recibidoAt,
    required this.venceAt,
    required this.remitente,
    required this.asunto,
    required this.buzon,
    required this.proveedor,
    required this.nitRelacionado,
    required this.sourceMessageId,
    required this.accessCount,
    required this.firstOpenedAt,
    required this.firstOpenedBy,
    required this.firstOpenedByName,
    required this.lastOpenedAt,
    required this.lastOpenedBy,
    required this.lastOpenedByName,
  });

  factory DianTokenRecord.fromMap(Map<String, dynamic> data) => DianTokenRecord(
    id: (data['id'] ?? '').toString(),
    empresaId: (data['empresaId'] ?? '').toString(),
    estado: (data['estado'] ?? 'nuevo').toString(),
    recibidoAt: dianDateFromMillis(data['recibidoAt']),
    venceAt: dianDateFromMillis(data['venceAt']),
    remitente: (data['remitente'] ?? '').toString(),
    asunto: (data['asunto'] ?? '').toString(),
    buzon: (data['buzon'] ?? '').toString(),
    proveedor: (data['proveedor'] ?? '').toString(),
    nitRelacionado: (data['nitRelacionado'] ?? '').toString(),
    sourceMessageId: (data['sourceMessageId'] ?? '').toString(),
    accessCount: int.tryParse('${data['accessCount'] ?? 0}') ?? 0,
    firstOpenedAt: dianDateFromMillis(data['firstOpenedAt']),
    firstOpenedBy: (data['firstOpenedBy'] ?? '').toString(),
    firstOpenedByName: (data['firstOpenedByName'] ?? '').toString(),
    lastOpenedAt: dianDateFromMillis(data['lastOpenedAt']),
    lastOpenedBy: (data['lastOpenedBy'] ?? '').toString(),
    lastOpenedByName: (data['lastOpenedByName'] ?? '').toString(),
  );

  bool get abierto => estado == 'abierto' || accessCount > 0;
  bool get disponible =>
      !const {'expirado', 'archivado', 'invalidado'}.contains(estado);
}

class DianTokenAccess {
  final String id;
  final String userId;
  final String userName;
  final String empresaId;
  final DateTime? openedAt;

  const DianTokenAccess({
    required this.id,
    required this.userId,
    required this.userName,
    required this.empresaId,
    required this.openedAt,
  });

  factory DianTokenAccess.fromMap(Map<String, dynamic> data) => DianTokenAccess(
    id: (data['id'] ?? '').toString(),
    userId: (data['userId'] ?? '').toString(),
    userName: (data['userName'] ?? '').toString(),
    empresaId: (data['empresaId'] ?? '').toString(),
    openedAt: dianDateFromMillis(data['openedAt']),
  );
}

/// Estado del buzón propio del módulo. El backend nunca devuelve la
/// contraseña de aplicación ni su ciphertext: solo lo que la app puede
/// mostrar.
class DianBuzonEstado {
  final bool conectado;
  final String proveedor;
  final String email;
  final String host;
  final String estado;
  final bool procesarHistoricos;
  final String ultimoError;
  final DateTime? ultimaRevisionAt;
  final DateTime? conectadoAt;
  final int totalRegistrados;
  final int totalDescartados;
  final String remitenteFiltrado;
  final String asuntoFiltrado;

  const DianBuzonEstado({
    required this.conectado,
    required this.proveedor,
    required this.email,
    required this.host,
    required this.estado,
    required this.procesarHistoricos,
    required this.ultimoError,
    required this.ultimaRevisionAt,
    required this.conectadoAt,
    required this.totalRegistrados,
    required this.totalDescartados,
    required this.remitenteFiltrado,
    required this.asuntoFiltrado,
  });

  factory DianBuzonEstado.fromMap(Map<String, dynamic> data) => DianBuzonEstado(
    conectado: data['conectado'] == true,
    proveedor: (data['proveedor'] ?? 'yahoo').toString(),
    email: (data['email'] ?? '').toString(),
    host: (data['host'] ?? '').toString(),
    estado: (data['estado'] ?? 'sin_conectar').toString(),
    procesarHistoricos: data['procesarHistoricos'] == true,
    ultimoError: (data['ultimoError'] ?? '').toString(),
    ultimaRevisionAt: dianDateFromMillis(data['ultimaRevisionAt']),
    conectadoAt: dianDateFromMillis(data['conectadoAt']),
    totalRegistrados: int.tryParse('${data['totalRegistrados'] ?? 0}') ?? 0,
    totalDescartados: int.tryParse('${data['totalDescartados'] ?? 0}') ?? 0,
    remitenteFiltrado: (data['remitenteFiltrado'] ?? '').toString(),
    asuntoFiltrado: (data['asuntoFiltrado'] ?? '').toString(),
  );

  static const DianBuzonEstado sinConectar = DianBuzonEstado(
    conectado: false,
    proveedor: 'yahoo',
    email: '',
    host: '',
    estado: 'sin_conectar',
    procesarHistoricos: false,
    ultimoError: '',
    ultimaRevisionAt: null,
    conectadoAt: null,
    totalRegistrados: 0,
    totalDescartados: 0,
    remitenteFiltrado: kDianRemitenteOficial,
    asuntoFiltrado: kDianAsuntoOficial,
  );

  bool get conError => estado == 'error' || estado == 'credenciales_invalidas';

  /// Texto que explica al usuario qué se lee del buzón y qué no.
  String get descripcionFiltro {
    final remitente = remitenteFiltrado.isEmpty
        ? kDianRemitenteOficial
        : remitenteFiltrado;
    final asunto = asuntoFiltrado.isEmpty ? kDianAsuntoOficial : asuntoFiltrado;
    return 'Solo se leen los correos de $remitente o con el asunto '
        '«$asunto». El resto del buzón no se descarga.';
  }
}

/// Resumen de una lectura del buzón.
class DianBuzonResumen {
  final int revisados;
  final int registrados;
  final int duplicados;
  final int descartados;
  final int sinEnlace;

  const DianBuzonResumen({
    required this.revisados,
    required this.registrados,
    required this.duplicados,
    required this.descartados,
    required this.sinEnlace,
  });

  factory DianBuzonResumen.fromMap(Map<String, dynamic> data) =>
      DianBuzonResumen(
        revisados: int.tryParse('${data['revisados'] ?? 0}') ?? 0,
        registrados: int.tryParse('${data['registrados'] ?? 0}') ?? 0,
        duplicados: int.tryParse('${data['duplicados'] ?? 0}') ?? 0,
        descartados: int.tryParse('${data['descartados'] ?? 0}') ?? 0,
        sinEnlace: int.tryParse('${data['sinEnlace'] ?? 0}') ?? 0,
      );

  String get mensaje {
    if (revisados == 0) return 'No llegaron tokens nuevos de la DIAN.';
    if (registrados == 0) {
      return 'Se revisaron $revisados correos DIAN; ninguno traía un token nuevo.';
    }
    return '$registrados token(s) nuevo(s) cifrado(s) y registrado(s).';
  }
}

const kDianRemitenteOficial = 'facturacionelectronica@dian.gov.co';
const kDianAsuntoOficial = 'Token Acceso DIAN';

DateTime? dianDateFromMillis(dynamic value) {
  final millis = value is num ? value.toInt() : int.tryParse('$value');
  if (millis == null || millis <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}
