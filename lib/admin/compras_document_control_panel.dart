import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../compras/compras_models.dart';
import '../services/task_service.dart';

const _primary = Color(0xFF0F172A);
const _border = Color(0xFFD7DFEA);

class ComprasAdminDocumentRecord {
  final String id;
  final String collection;
  final String documentId;
  final String container;
  final String key;
  final int? productIndex;
  final String origin;
  final String owner;
  final String label;
  final String fileName;
  final String status;
  final Timestamp? reviewedAt;

  const ComprasAdminDocumentRecord({
    required this.id,
    required this.collection,
    required this.documentId,
    required this.container,
    required this.key,
    this.productIndex,
    required this.origin,
    required this.owner,
    required this.label,
    required this.fileName,
    required this.status,
    this.reviewedAt,
  });
}

class ComprasAdminControlService {
  final FirebaseFirestore _db;

  ComprasAdminControlService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  Future<int> loadRejectedDays(String companyId) async {
    final snap = await _db
        .collection('TBL_COMPRAS_CONFIG')
        .doc(companyId)
        .get();
    final value = snap.data()?['diasPlazoRechazados'];
    if (value is num && value >= 1 && value <= 365) return value.toInt();
    return 30;
  }

  Future<int> saveRejectedDays({
    required String companyId,
    required String userId,
    required int days,
    required bool extendOpenTasks,
  }) async {
    if (days < 1 || days > 365) {
      throw StateError('El plazo debe estar entre 1 y 365 días.');
    }
    await _db.collection('TBL_COMPRAS_CONFIG').doc(companyId).set({
      'diasPlazoRechazados': days,
      'politicaRechazadosActualizadaPor': userId,
      'politicaRechazadosActualizadaAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!extendOpenTasks) return 0;
    final snap = await _db
        .collection(TaskService.tasksCol)
        .where('empresaId', isEqualTo: companyId)
        .get();
    final open = snap.docs.where((doc) {
      final data = doc.data();
      if ((data['origen'] ?? '').toString() != 'compras_correccion') {
        return false;
      }
      final status = (data['estado'] ?? data['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return status != 'finalizado' &&
          status != 'cerrado' &&
          status != 'completado';
    }).toList();

    for (var offset = 0; offset < open.length; offset += 400) {
      final batch = _db.batch();
      final end = (offset + 400).clamp(0, open.length);
      for (final task in open.sublist(offset, end)) {
        batch.update(task.reference, {
          'fecha_limite': Timestamp.fromDate(
            DateTime.now().add(Duration(days: days)),
          ),
          'fecha_actualizacion': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'plazoComprasActualizadoPor': userId,
          'plazoComprasDias': days,
        });
      }
      await batch.commit();
    }
    return open.length;
  }

  Future<List<ComprasAdminDocumentRecord>> loadDocuments(
    String companyId,
  ) async {
    final results = await Future.wait([
      _db
          .collection('TBL_COMPRAS_PROVEEDORES')
          .where('empresaId', isEqualTo: companyId)
          .get(),
      _db
          .collection('TBL_COMPRAS_MARCAS')
          .where('empresaId', isEqualTo: companyId)
          .get(),
      _db
          .collection('TBL_COMPRAS_PRODUCTOS')
          .where('empresaId', isEqualTo: companyId)
          .get(),
      _db
          .collection('TBL_COMPRAS_FICHAS_TECNICAS')
          .where('empresaId', isEqualTo: companyId)
          .get(),
      _db
          .collection('TBL_COMPRAS_RECEPCIONES')
          .where('empresaId', isEqualTo: companyId)
          .get(),
    ]);
    final records = <ComprasAdminDocumentRecord>[];

    for (final snap in results[0].docs) {
      final data = snap.data();
      _appendMap(
        records,
        collection: 'TBL_COMPRAS_PROVEEDORES',
        documentId: snap.id,
        container: 'documentos',
        values: data['documentos'],
        origin: 'Proveedor',
        owner: (data['razonSocial'] ?? data['nit'] ?? 'Proveedor').toString(),
        labels: kDocProveedorLabels,
      );
    }
    for (final snap in results[1].docs) {
      final data = snap.data();
      _appendMap(
        records,
        collection: 'TBL_COMPRAS_MARCAS',
        documentId: snap.id,
        container: 'documentosAsociados',
        values: data['documentosAsociados'],
        origin: 'Marca',
        owner: (data['descripcion'] ?? data['codigo'] ?? 'Marca').toString(),
        labels: const {},
      );
    }
    for (final snap in results[2].docs) {
      final data = snap.data();
      final owner = (data['nombre'] ?? data['codigo'] ?? 'Producto').toString();
      _appendSingle(
        records,
        collection: 'TBL_COMPRAS_PRODUCTOS',
        documentId: snap.id,
        container: 'fichaTecnica',
        key: 'fichaTecnica',
        value: data['fichaTecnica'],
        origin: 'Producto',
        owner: owner,
        label: 'Ficha técnica del producto',
      );
      _appendMap(
        records,
        collection: 'TBL_COMPRAS_PRODUCTOS',
        documentId: snap.id,
        container: 'fichasTecnicasPorMarca',
        values: data['fichasTecnicasPorMarca'],
        origin: 'Producto / marca',
        owner: owner,
        labels: const {},
        fallbackLabel: 'Ficha técnica por marca',
      );
      _appendMap(
        records,
        collection: 'TBL_COMPRAS_PRODUCTOS',
        documentId: snap.id,
        container: 'documentosAsociados',
        values: data['documentosAsociados'],
        origin: 'Producto',
        owner: owner,
        labels: const {},
      );
    }
    for (final snap in results[3].docs) {
      final data = snap.data();
      final provider = (data['proveedorNombre'] ?? '').toString();
      final product = (data['productoNombre'] ?? 'Ficha técnica').toString();
      final brand = (data['marcaNombre'] ?? '').toString();
      _appendSingle(
        records,
        collection: 'TBL_COMPRAS_FICHAS_TECNICAS',
        documentId: snap.id,
        container: 'documentoActual',
        key: 'documentoActual',
        value: data['documentoActual'],
        origin: 'Ficha por proveedor',
        owner: [
          product,
          brand,
          provider,
        ].where((value) => value.trim().isNotEmpty).join(' · '),
        label: 'Ficha técnica por proveedor',
      );
    }
    for (final snap in results[4].docs) {
      final data = snap.data();
      final products = data['productos'];
      if (products is! List) continue;
      for (var index = 0; index < products.length; index++) {
        final product = _asMap(products[index]);
        if (product == null) continue;
        _appendMap(
          records,
          collection: 'TBL_COMPRAS_RECEPCIONES',
          documentId: snap.id,
          container: 'recepcionProductos',
          values: product['documentos'],
          productIndex: index,
          origin: 'Recepción',
          owner:
              '${data['razonSocial'] ?? 'Proveedor'} · ${product['nombre'] ?? 'Producto'}',
          labels: kDocRecepcionLabels,
        );
      }
    }

    records.sort((a, b) {
      final byOrigin = a.origin.compareTo(b.origin);
      if (byOrigin != 0) return byOrigin;
      final byOwner = a.owner.compareTo(b.owner);
      return byOwner != 0 ? byOwner : a.label.compareTo(b.label);
    });
    return records;
  }

  Future<void> changeStatuses({
    required String companyId,
    required String userId,
    required List<ComprasAdminDocumentRecord> records,
    required String newStatus,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (records.isEmpty) throw StateError('Selecciona al menos un documento.');
    if (cleanReason.length < 5) {
      throw StateError('Indica un motivo de al menos 5 caracteres.');
    }
    if (!const {
      'pendiente_revision_calidad',
      'aprobado',
      'rechazado',
    }.contains(newStatus)) {
      throw StateError('El estado seleccionado no es válido.');
    }

    final grouped = <String, List<ComprasAdminDocumentRecord>>{};
    for (final record in records) {
      grouped
          .putIfAbsent('${record.collection}/${record.documentId}', () => [])
          .add(record);
    }
    for (final group in grouped.values) {
      await _changeDocumentGroup(
        companyId: companyId,
        userId: userId,
        records: group,
        newStatus: newStatus,
        reason: cleanReason,
      );
    }
  }

  Future<void> _changeDocumentGroup({
    required String companyId,
    required String userId,
    required List<ComprasAdminDocumentRecord> records,
    required String newStatus,
    required String reason,
  }) async {
    final first = records.first;
    final ref = _db.collection(first.collection).doc(first.documentId);
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      if (!snap.exists) return;
      final data = snap.data() ?? const <String, dynamic>{};
      if ((data['empresaId'] ?? '').toString() != companyId) {
        throw StateError('Un documento ya no pertenece a la empresa activa.');
      }
      final now = Timestamp.now();
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      List<dynamic>? receptionProducts;

      for (final record in records) {
        Map<String, dynamic>? current;
        if (record.container == 'recepcionProductos') {
          receptionProducts ??= List<dynamic>.from(
            data['productos'] as List? ?? const [],
          );
          final index = record.productIndex;
          if (index == null || index < 0 || index >= receptionProducts.length) {
            continue;
          }
          final product = _asMap(receptionProducts[index]);
          if (product == null) continue;
          final documents = Map<String, dynamic>.from(
            _asMap(product['documentos']) ?? const {},
          );
          current = _asMap(documents[record.key]);
          if (current == null || !_hasFile(current)) continue;
          documents[record.key] = _statusMap(
            current,
            newStatus,
            reason,
            userId,
            now,
          );
          receptionProducts[index] = {...product, 'documentos': documents};
        } else if (record.container == 'fichaTecnica' ||
            record.container == 'documentoActual') {
          current = _asMap(data[record.container]);
          if (current == null || !_hasFile(current)) continue;
          updates[record.container] = _statusMap(
            current,
            newStatus,
            reason,
            userId,
            now,
          );
        } else {
          final map = _asMap(data[record.container]);
          current = _asMap(map?[record.key]);
          if (current == null || !_hasFile(current)) continue;
          updates['${record.container}.${record.key}'] = _statusMap(
            current,
            newStatus,
            reason,
            userId,
            now,
          );
        }

        final audit = _db.collection('TBL_COMPRAS_AUDITORIA_DOCUMENTOS').doc();
        transaction.set(audit, {
          'empresaId': companyId,
          'actorId': userId,
          'accion': 'cambio_estado_admin',
          'estadoAnterior': (current['estadoCalidad'] ?? '').toString(),
          'estadoNuevo': newStatus,
          'motivo': reason,
          'coleccionOrigen': record.collection,
          'documentoOrigenId': record.documentId,
          'contenedor': record.container,
          'docKey': record.key,
          'origen': record.origin,
          'titular': record.owner,
          'documentoLabel': record.label,
          'archivoNombre': (current['nombre'] ?? record.fileName).toString(),
          'createdAt': now,
        });
      }
      if (receptionProducts != null) updates['productos'] = receptionProducts;
      transaction.update(ref, updates);
    });
  }

  static Map<String, dynamic> _statusMap(
    Map<String, dynamic> current,
    String newStatus,
    String reason,
    String userId,
    Timestamp now,
  ) {
    final previous = (current['estadoCalidad'] ?? '').toString();
    final result = Map<String, dynamic>.from(current)
      ..['estadoCalidad'] = newStatus
      ..['estadoAnteriorReversion'] = previous
      ..['revertidoPor'] = userId
      ..['fechaReversion'] = now
      ..['motivoReversion'] = reason;
    if (newStatus == 'pendiente_revision_calidad') {
      result['observacionCalidad'] = null;
      result['revisadoPor'] = null;
      result['fechaRevision'] = null;
    } else {
      result['observacionCalidad'] = newStatus == 'rechazado' ? reason : null;
      result['revisadoPor'] = userId;
      result['fechaRevision'] = now;
    }
    return result;
  }

  static void _appendMap(
    List<ComprasAdminDocumentRecord> target, {
    required String collection,
    required String documentId,
    required String container,
    required dynamic values,
    required String origin,
    required String owner,
    required Map<String, String> labels,
    int? productIndex,
    String? fallbackLabel,
  }) {
    final map = _asMap(values);
    if (map == null) return;
    for (final entry in map.entries) {
      _appendSingle(
        target,
        collection: collection,
        documentId: documentId,
        container: container,
        key: entry.key,
        value: entry.value,
        productIndex: productIndex,
        origin: origin,
        owner: owner,
        label: labels[entry.key] ?? fallbackLabel ?? _humanize(entry.key),
      );
    }
  }

  static void _appendSingle(
    List<ComprasAdminDocumentRecord> target, {
    required String collection,
    required String documentId,
    required String container,
    required String key,
    required dynamic value,
    required String origin,
    required String owner,
    required String label,
    int? productIndex,
  }) {
    final map = _asMap(value);
    if (map == null || !_hasFile(map)) return;
    final status = (map['estadoCalidad'] ?? '').toString().trim();
    target.add(
      ComprasAdminDocumentRecord(
        id: '$collection/$documentId/$container/${productIndex ?? ''}/$key',
        collection: collection,
        documentId: documentId,
        container: container,
        key: key,
        productIndex: productIndex,
        origin: origin,
        owner: owner,
        label: label,
        fileName: (map['nombre'] ?? 'Documento cargado').toString(),
        status: status.isEmpty ? 'sin_estado' : status,
        reviewedAt: map['fechaRevision'] as Timestamp?,
      ),
    );
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  static bool _hasFile(Map<String, dynamic> value) =>
      (value['url'] ?? '').toString().trim().isNotEmpty ||
      (value['path'] ?? '').toString().trim().isNotEmpty;

  static String _humanize(String value) {
    final spaced = value.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    );
    return spaced.isEmpty
        ? 'Documento'
        : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }
}

class AdminComprasDocumentControlPanel extends StatefulWidget {
  final String userId;
  final String companyId;

  const AdminComprasDocumentControlPanel({
    super.key,
    required this.userId,
    required this.companyId,
  });

  @override
  State<AdminComprasDocumentControlPanel> createState() =>
      _AdminComprasDocumentControlPanelState();
}

class _AdminComprasDocumentControlPanelState
    extends State<AdminComprasDocumentControlPanel> {
  final _service = ComprasAdminControlService();
  final _search = TextEditingController();
  final _reason = TextEditingController();
  final _days = TextEditingController(text: '30');
  List<ComprasAdminDocumentRecord> _documents = const [];
  final Set<String> _selected = {};
  String _origin = 'todos';
  String _status = 'todos';
  String _targetStatus = 'pendiente_revision_calidad';
  bool _loading = true;
  bool _saving = false;
  bool _extendOpenTasks = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminComprasDocumentControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _selected.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _reason.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.companyId.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _service.loadDocuments(widget.companyId),
        _service.loadRejectedDays(widget.companyId),
      ]);
      if (!mounted) return;
      setState(() {
        _documents = values[0] as List<ComprasAdminDocumentRecord>;
        _days.text = (values[1] as int).toString();
        _selected.removeWhere((id) => !_documents.any((doc) => doc.id == id));
      });
    } catch (error) {
      _message(
        'No fue posible cargar el control documental: $error',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ComprasAdminDocumentRecord> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _documents.where((doc) {
      if (_origin != 'todos' && doc.origin != _origin) return false;
      if (_status != 'todos' && doc.status != _status) return false;
      if (query.isEmpty) return true;
      return '${doc.owner} ${doc.label} ${doc.fileName} ${doc.key}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  Future<void> _savePolicy() async {
    final value = int.tryParse(_days.text.trim());
    if (value == null) {
      _message('Escribe un número de días válido.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await _service.saveRejectedDays(
        companyId: widget.companyId,
        userId: widget.userId,
        days: value,
        extendOpenTasks: _extendOpenTasks,
      );
      _message(
        updated == 0
            ? 'Política guardada: $value días.'
            : 'Política guardada y $updated tareas abiertas actualizadas.',
      );
    } catch (error) {
      _message('$error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyStatus() async {
    final records = _documents
        .where((doc) => _selected.contains(doc.id))
        .toList();
    if (records.isEmpty) {
      _message('Selecciona al menos un documento.', error: true);
      return;
    }
    if (_reason.text.trim().length < 5) {
      _message('Indica el motivo administrativo del cambio.', error: true);
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirmar cambio de estado'),
            content: Text(
              'Se cambiarán ${records.length} documento(s) a '
              '“${_statusLabel(_targetStatus)}”.\n\n'
              'La acción quedará registrada en la auditoría de Compras.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _saving = true);
    try {
      await _service.changeStatuses(
        companyId: widget.companyId,
        userId: widget.userId,
        records: records,
        newStatus: _targetStatus,
        reason: _reason.text,
      );
      _message('${records.length} documento(s) actualizados correctamente.');
      _selected.clear();
      _reason.clear();
      await _load();
    } catch (error) {
      _message('No se pudo completar el cambio: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _selectProviderType(String key) {
    setState(() {
      _origin = 'Proveedor';
      _status = 'todos';
      _search.text = key == kDocRut
          ? 'RUT del proveedor'
          : 'Cámara de comercio';
      _selected
        ..clear()
        ..addAll(
          _documents
              .where((doc) => doc.origin == 'Proveedor' && doc.key == key)
              .map((doc) => doc.id),
        );
    });
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error
            ? const Color(0xFFB91C1C)
            : const Color(0xFF047857),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final origins = _documents.map((doc) => doc.origin).toSet().toList()
      ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _policyCard(),
        const SizedBox(height: 12),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Control documental de Compras',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _primary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Consulta documentos cargados de la empresa y corrige su estado. Cada cambio exige motivo y genera un registro de auditoría.',
                  style: TextStyle(color: Color(0xFF64748B), height: 1.35),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _selectProviderType(kDocRut),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Seleccionar todos los RUT'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _selectProviderType(kDocCertExistencia),
                      icon: const Icon(Icons.store_outlined),
                      label: const Text('Seleccionar todas las cámaras'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 850;
                    final fields = [
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Buscar proveedor, producto o documento',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _origin,
                        decoration: const InputDecoration(
                          labelText: 'Origen',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos los orígenes'),
                          ),
                          ...origins.map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _origin = value ?? 'todos'),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Estado actual',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos los estados'),
                          ),
                          DropdownMenuItem(
                            value: 'pendiente_revision_calidad',
                            child: Text('Pendiente de revisión'),
                          ),
                          DropdownMenuItem(
                            value: 'aprobado',
                            child: Text('Aprobado'),
                          ),
                          DropdownMenuItem(
                            value: 'aprobado_con_requerimientos',
                            child: Text('Aprobado con requerimientos'),
                          ),
                          DropdownMenuItem(
                            value: 'rechazado',
                            child: Text('Rechazado'),
                          ),
                          DropdownMenuItem(
                            value: 'sin_estado',
                            child: Text('Sin estado'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _status = value ?? 'todos'),
                      ),
                    ];
                    if (compact) {
                      return Column(
                        children: fields
                            .map(
                              (field) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: field,
                              ),
                            )
                            .toList(),
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 2, child: fields[0]),
                        const SizedBox(width: 8),
                        Expanded(child: fields[1]),
                        const SizedBox(width: 8),
                        Expanded(child: fields[2]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Checkbox(
                      value:
                          filtered.isNotEmpty &&
                          filtered.every((doc) => _selected.contains(doc.id)),
                      tristate: true,
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selected.addAll(filtered.map((doc) => doc.id));
                        } else {
                          _selected.removeAll(filtered.map((doc) => doc.id));
                        }
                      }),
                    ),
                    Expanded(
                      child: Text(
                        '${filtered.length} documento(s) visibles · ${_selected.length} seleccionados',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _documentList(filtered),
                const SizedBox(height: 14),
                _actionArea(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _policyCard() {
    return Card(
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Plazo de documentos rechazados',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _primary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Este valor controla el vencimiento de nuevas tareas de corrección y la permanencia del documento rechazado en Calidad.',
              style: TextStyle(color: Color(0xFF64748B), height: 1.35),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final input = TextField(
                  controller: _days,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Días de plazo',
                    suffixText: 'días',
                    border: OutlineInputBorder(),
                  ),
                );
                final update = CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _extendOpenTasks,
                  onChanged: _saving
                      ? null
                      : (value) =>
                            setState(() => _extendOpenTasks = value ?? true),
                  title: const Text(
                    'Extender también las tareas de corrección que siguen abiertas',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                );
                if (constraints.maxWidth < 700) {
                  return Column(children: [input, update]);
                }
                return Row(
                  children: [
                    SizedBox(width: 180, child: input),
                    const SizedBox(width: 16),
                    Expanded(child: update),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _savePolicy,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar política'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _documentList(List<ComprasAdminDocumentRecord> records) {
    if (records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
          child: Text('No hay documentos que coincidan con los filtros.'),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 520),
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: records.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final record = records[index];
          final selected = _selected.contains(record.id);
          return CheckboxListTile(
            value: selected,
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      _selected.add(record.id);
                    } else {
                      _selected.remove(record.id);
                    }
                  }),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              record.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(record.owner, overflow: TextOverflow.ellipsis),
                  _statusChip(record.status),
                  Text(
                    record.origin,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _actionArea() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Aplicar cambio administrativo',
            style: TextStyle(fontWeight: FontWeight.w800, color: _primary),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final state = DropdownButtonFormField<String>(
                initialValue: _targetStatus,
                decoration: const InputDecoration(
                  labelText: 'Nuevo estado',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'pendiente_revision_calidad',
                    child: Text('Pendiente de revisión'),
                  ),
                  DropdownMenuItem(value: 'aprobado', child: Text('Aprobado')),
                  DropdownMenuItem(
                    value: 'rechazado',
                    child: Text('Rechazado'),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _targetStatus = value ?? 'pendiente_revision_calidad',
                ),
              );
              final reason = TextField(
                controller: _reason,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo obligatorio',
                  hintText:
                      'Ej.: Solicitud de Calidad para volver a revisar la vigencia',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [state, const SizedBox(height: 8), reason],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 260, child: state),
                  const SizedBox(width: 8),
                  Expanded(child: reason),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _primary),
            onPressed: _saving ? null : _applyStatus,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.rule_folder_outlined),
            label: Text('Cambiar estado de ${_selected.length} documento(s)'),
          ),
          const SizedBox(height: 6),
          const Text(
            'Este ajuste corrige el estado administrativo y no envía mensajes masivos. Los rechazos operativos con notificación deben hacerse desde Calidad.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String value) {
    final color = switch (value) {
      'aprobado' => const Color(0xFF047857),
      'aprobado_con_requerimientos' => const Color(0xFFB45309),
      'rechazado' => const Color(0xFFB91C1C),
      'pendiente_revision_calidad' || 'pendiente' => const Color(0xFF1D4ED8),
      _ => const Color(0xFF64748B),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(value),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  static String _statusLabel(String value) => switch (value) {
    'aprobado' => 'Aprobado',
    'aprobado_con_requerimientos' => 'Aprobado con requerimientos',
    'rechazado' => 'Rechazado',
    'pendiente_revision_calidad' || 'pendiente' => 'Pendiente de revisión',
    _ => 'Sin estado',
  };
}
