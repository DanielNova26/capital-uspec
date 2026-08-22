import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? correoDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

List<String> correoStringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .where((item) => item != null)
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

class CorreoCuenta {
  final String id;
  final String empresaId;
  final String nombre;
  final String email;
  final bool activa;
  final String estadoIntegracion;
  final String ultimoEstado;
  final String? ultimoError;
  final DateTime? ultimaRevisionAt;
  final String gmailQuery;
  final bool procesarHistoricos;
  final String proveedor;

  const CorreoCuenta({
    required this.id,
    required this.empresaId,
    required this.nombre,
    required this.email,
    this.activa = true,
    this.estadoIntegracion = 'sin_conectar',
    this.ultimoEstado = '',
    this.ultimoError,
    this.ultimaRevisionAt,
    this.gmailQuery = 'label:inbox',
    this.procesarHistoricos = false,
    this.proveedor = 'gmail',
  });

  factory CorreoCuenta.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return CorreoCuenta(
      id: doc.id,
      empresaId: (data['empresaId'] ?? '').toString(),
      nombre: (data['nombre'] ?? data['email'] ?? 'Buzón Gmail').toString(),
      email: (data['email'] ?? '').toString(),
      activa: data['activa'] != false,
      estadoIntegracion: (data['estadoIntegracion'] ?? 'sin_conectar')
          .toString(),
      ultimoEstado: (data['ultimoEstado'] ?? '').toString(),
      ultimoError: data['ultimoError']?.toString(),
      ultimaRevisionAt: correoDate(data['ultimaRevisionAt']),
      gmailQuery: (data['gmailQuery'] ?? 'label:inbox').toString(),
      procesarHistoricos: data['procesarHistoricos'] == true,
      proveedor: (data['proveedor'] ?? 'gmail').toString().toLowerCase(),
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'nombre': nombre.trim(),
    'email': email.trim().toLowerCase(),
    'activa': activa,
    'gmailQuery': gmailQuery.trim().isEmpty ? 'label:inbox' : gmailQuery.trim(),
    'procesarHistoricos': procesarHistoricos,
    'proveedor': proveedor == 'microsoft' ? 'microsoft' : 'gmail',
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class CorreoRegla {
  final String id;
  final String empresaId;
  final String nombre;
  final bool activa;
  final int prioridad;
  final String categoria;
  final List<String> palabrasClave;
  final String modoCoincidencia;
  final String listadoId;
  final List<String> buscarEn;
  final List<String> remitentes;
  final List<String> asuntoContiene;
  final String tipoFiltro;
  final String icono;
  final bool crearCorrespondencia;
  final String tipoDocumental;

  const CorreoRegla({
    required this.id,
    required this.empresaId,
    required this.nombre,
    this.activa = true,
    this.prioridad = 50,
    this.categoria = 'General',
    this.palabrasClave = const [],
    this.modoCoincidencia = 'alguna',
    this.listadoId = '',
    this.buscarEn = const ['asunto'],
    this.remitentes = const [],
    this.asuntoContiene = const [],
    this.tipoFiltro = 'palabra',
    this.icono = '📩',
    this.crearCorrespondencia = false,
    this.tipoDocumental = 'General',
  });

  factory CorreoRegla.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final palabrasClave = correoStringList(data['palabrasClave']);
    final remitentes = correoStringList(data['remitentes']);
    final rawType = (data['tipoFiltro'] ?? '').toString().toLowerCase();
    final tipoFiltro = rawType == 'remitente' || rawType == 'combinado'
        ? rawType
        : remitentes.isNotEmpty && palabrasClave.isNotEmpty
        ? 'combinado'
        : remitentes.isNotEmpty
        ? 'remitente'
        : 'palabra';
    final categoria = (data['categoria'] ?? 'General').toString();
    return CorreoRegla(
      id: doc.id,
      empresaId: (data['empresaId'] ?? '').toString(),
      nombre: (data['nombre'] ?? 'Regla sin nombre').toString(),
      activa: data['activa'] != false,
      prioridad: (data['prioridad'] as num?)?.toInt() ?? 50,
      categoria: categoria,
      palabrasClave: palabrasClave,
      modoCoincidencia: (data['modoCoincidencia'] ?? 'alguna').toString(),
      listadoId: (data['listadoId'] ?? '').toString(),
      buscarEn: const ['asunto'],
      remitentes: remitentes,
      asuntoContiene: correoStringList(data['asuntoContiene']),
      tipoFiltro: tipoFiltro,
      icono: _correoFilterIcon(data['icono'] ?? data['emoji'], categoria),
      crearCorrespondencia:
          data['crearCorrespondencia'] == true ||
          data['accionCoincidencia']?.toString() == 'correspondencia',
      tipoDocumental: (data['tipoDocumental'] ?? categoria).toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'nombre': nombre.trim(),
    'activa': activa,
    'prioridad': prioridad,
    'categoria': categoria.trim(),
    'palabrasClave': palabrasClave
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(),
    'modoCoincidencia': modoCoincidencia == 'todas' ? 'todas' : 'alguna',
    'listadoId': listadoId,
    'buscarEn': const ['asunto'],
    'remitentes': remitentes,
    'asuntoContiene': asuntoContiene,
    'tipoFiltro': switch (tipoFiltro) {
      'remitente' => 'remitente',
      'combinado' => 'combinado',
      _ => 'palabra',
    },
    'icono': icono.trim().isEmpty ? '📩' : icono.trim(),
    'crearCorrespondencia': crearCorrespondencia,
    'accionCoincidencia': crearCorrespondencia ? 'correspondencia' : 'alerta',
    'tipoDocumental': tipoDocumental.trim().isEmpty
        ? categoria.trim()
        : tipoDocumental.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

String _correoFilterIcon(dynamic value, String category) {
  final configured = (value ?? '').toString().trim();
  if (configured.isNotEmpty) return configured;
  final normalized = category.toLowerCase();
  if (normalized.contains('tutela') ||
      normalized.contains('derecho') ||
      normalized.contains('juríd')) {
    return '⚖️';
  }
  if (normalized.contains('requerimiento')) return '📌';
  if (normalized.contains('mejora')) return '📝';
  if (normalized.contains('pqr')) return '📬';
  if (normalized.contains('factura')) return '🧾';
  if (normalized.contains('urgente') || normalized.contains('alerta')) {
    return '🚨';
  }
  return '📩';
}

class CorreoMensaje {
  final String id;
  final String cuentaId;
  final String correoCuenta;
  final String proveedor;
  final String remitente;
  final String asunto;
  final String estado;
  final String categoria;
  final List<String> palabrasClave;
  final DateTime? fecha;
  final String expedienteId;
  final String radicado;
  final String tareaId;

  const CorreoMensaje({
    required this.id,
    required this.cuentaId,
    required this.correoCuenta,
    required this.proveedor,
    required this.remitente,
    required this.asunto,
    required this.estado,
    required this.categoria,
    required this.palabrasClave,
    this.fecha,
    required this.expedienteId,
    required this.radicado,
    required this.tareaId,
  });

  factory CorreoMensaje.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return CorreoMensaje(
      id: doc.id,
      cuentaId: (data['cuentaId'] ?? '').toString(),
      correoCuenta: (data['correoCuenta'] ?? '').toString(),
      proveedor: (data['proveedor'] ?? 'gmail').toString().toLowerCase(),
      remitente: (data['remitente'] ?? '').toString(),
      asunto: (data['asunto'] ?? '(Sin asunto)').toString(),
      estado: (data['estado'] ?? '').toString(),
      categoria: (data['categoria'] ?? '').toString(),
      palabrasClave: correoStringList(data['palabrasClave']),
      fecha: correoDate(data['fechaCorreo'] ?? data['createdAt']),
      expedienteId: (data['expedienteId'] ?? '').toString(),
      radicado: (data['radicado'] ?? '').toString(),
      tareaId: (data['tareaId'] ?? '').toString(),
    );
  }
}

class CorreoAlerta {
  final String id;
  final String categoria;
  final String destinatario;
  final String destinatarioNombre;
  final String estado;
  final String reglaNombre;
  final String correoCuenta;
  final String proveedorCorreo;
  final String? error;
  final DateTime? fecha;

  const CorreoAlerta({
    required this.id,
    required this.categoria,
    required this.destinatario,
    required this.destinatarioNombre,
    required this.estado,
    required this.reglaNombre,
    this.correoCuenta = '',
    this.proveedorCorreo = 'gmail',
    this.error,
    this.fecha,
  });

  factory CorreoAlerta.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return CorreoAlerta(
      id: doc.id,
      categoria: (data['categoria'] ?? 'General').toString(),
      destinatario: (data['destinatario'] ?? '').toString(),
      destinatarioNombre: (data['destinatarioNombre'] ?? '').toString(),
      estado: (data['estado'] ?? '').toString(),
      reglaNombre: (data['reglaNombre'] ?? '').toString(),
      correoCuenta: (data['correoCuenta'] ?? '').toString(),
      proveedorCorreo: (data['proveedorCorreo'] ?? 'gmail')
          .toString()
          .toLowerCase(),
      error: data['error']?.toString(),
      fecha: correoDate(data['sentAt'] ?? data['createdAt']),
    );
  }
}

List<String> separarValores(String raw) => raw
    .split(RegExp(r'[,\n;]'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();
