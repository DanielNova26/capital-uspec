// lib/talento_humano/hoja_de_vida_management_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'hoja_de_vida_service.dart';
import 'carnet_qr.dart';
import 'hoja_de_vida_pdf.dart';
import '../services/task_service.dart';
import '../utils/doc_preview.dart';
import '../utils/user_company.dart';
import '../widgets/user_avatar.dart';

const Color _thPrimary = Color(0xFFC28942);

String _formatHvTimestamp(dynamic value) {
  DateTime? dt;
  if (value is Timestamp) dt = value.toDate();
  if (value is DateTime) dt = value;
  if (value is String) dt = DateTime.tryParse(value);
  if (dt == null) return '';
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final suffix = dt.hour >= 12 ? 'p. m.' : 'a. m.';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '$hour:$minute $suffix';
}

String _correctionTraceLabel(Map<String, dynamic> data) {
  final estado = (data['estadoHojaDeVida'] ?? '').toString();
  final requested = _formatHvTimestamp(data['correctionRequestedAt']);
  final updated = _formatHvTimestamp(data['correctionUpdatedAt']);
  final submitted = _formatHvTimestamp(data['correctionSubmittedAt']);

  if (estado == 'requiere_cambios') {
    if (updated.isNotEmpty) return 'Editada después de la devolución: $updated';
    if (requested.isNotEmpty) {
      return 'Devuelta por TH: $requested · sin cambios aún';
    }
    return 'Devuelta por TH · sin cambios aún';
  }
  if (submitted.isNotEmpty) {
    return 'Reenviada después de corrección: $submitted';
  }
  return '';
}

// ── Pantalla de lista ──────────────────────────────────────────────────────

class HojaDeVidaManagementScreen extends StatefulWidget {
  final String userId; // TH reviewer cedula
  final String empresaId;

  const HojaDeVidaManagementScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<HojaDeVidaManagementScreen> createState() =>
      _HojaDeVidaManagementScreenState();
}

class _HojaDeVidaManagementScreenState
    extends State<HojaDeVidaManagementScreen> {
  final _svc = HojaDeVidaService();
  String _search = '';
  String? _filtroEstado;
  String? _filtroArea;
  String? _filtroCargo;
  List<String> _areas = [];
  List<String> _cargos = [];

  @override
  void initState() {
    super.initState();
    _loadFiltros();
  }

  Future<void> _loadFiltros() async {
    final areas = await _svc.getAreaNames(widget.empresaId);
    final cargos = await _svc.getCargoNames(widget.empresaId);
    if (!mounted) return;
    setState(() {
      _areas = areas;
      _cargos = cargos;
    });
  }

  void _showFiltros() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FiltrosSheet(
        estadoActual: _filtroEstado,
        areaActual: _filtroArea,
        cargoActual: _filtroCargo,
        areas: _areas,
        cargos: _cargos,
        onApply: (estado, area, cargo) {
          setState(() {
            _filtroEstado = estado;
            _filtroArea = area;
            _filtroCargo = cargo;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hayFiltros =
        _filtroEstado != null || _filtroArea != null || _filtroCargo != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hojas de Vida'),
        backgroundColor: _thPrimary,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filtros',
                onPressed: _showFiltros,
              ),
              if (hayFiltros)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o cédula…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          if (hayFiltros)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [
                        if (_filtroEstado != null) 'Estado: $_filtroEstado',
                        if (_filtroArea != null) 'Área: $_filtroArea',
                        if (_filtroCargo != null) 'Cargo: $_filtroCargo',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => setState(() {
                      _filtroEstado = null;
                      _filtroArea = null;
                      _filtroCargo = null;
                    }),
                    child: const Text(
                      'Limpiar',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _svc.streamEmpleados(widget.empresaId),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                var docs = snap.data?.docs ?? [];

                // Solo docs con nombre (excluye credenciales de login) y de
                // personal vigente: el retirado conserva su hoja de vida, pero
                // no se le siguen pidiendo correcciones.
                docs = docs.where((d) {
                  final data = d.data();
                  if (!isPersonaActivaEnEmpresa(data, widget.empresaId)) {
                    return false;
                  }
                  return (data['primerNombre'] as String?)?.isNotEmpty ?? false;
                }).toList();

                // Filtrar por estado de hoja de vida
                if (_filtroEstado != null) {
                  docs = docs.where((d) {
                    final estado =
                        d.data()['estadoHojaDeVida'] as String? ?? 'sin_enviar';
                    return estado == _filtroEstado;
                  }).toList();
                }

                // Filtrar por área (campo areaNombre en TBL_USUARIOS)
                if (_filtroArea != null) {
                  docs = docs.where((d) {
                    final area =
                        (d.data()['areaNombre'] ?? d.data()['area'] ?? '')
                            as String;
                    return area == _filtroArea;
                  }).toList();
                }

                // Filtrar por cargo
                if (_filtroCargo != null) {
                  docs = docs.where((d) {
                    final cargo = (d.data()['cargo'] ?? '') as String;
                    return cargo == _filtroCargo;
                  }).toList();
                }

                // Filtrar por búsqueda libre
                if (_search.isNotEmpty) {
                  docs = docs.where((d) {
                    final data = d.data();
                    final nombre =
                        '${data['primerNombre'] ?? ''} ${data['primerApellido'] ?? ''}'
                            .toLowerCase();
                    final cedula = (data['cedula'] ?? d.id)
                        .toString()
                        .toLowerCase();
                    final usuario = (data['usuario'] ?? data['username'] ?? '')
                        .toString()
                        .toLowerCase();
                    final cargo = (data['cargo'] ?? '')
                        .toString()
                        .toLowerCase();
                    final area = (data['areaNombre'] ?? data['area'] ?? '')
                        .toString()
                        .toLowerCase();
                    return nombre.contains(_search) ||
                        cedula.contains(_search) ||
                        usuario.contains(_search) ||
                        cargo.contains(_search) ||
                        area.contains(_search);
                  }).toList();
                }

                // Ordenar: correcciones primero, luego en revisión
                docs.sort((a, b) {
                  const order = {
                    'requiere_cambios': 0,
                    'en_revision': 1,
                    'sin_enviar': 2,
                    'aprobado': 3,
                  };
                  final ea = order[a.data()['estadoHojaDeVida']] ?? 2;
                  final eb = order[b.data()['estadoHojaDeVida']] ?? 2;
                  return ea.compareTo(eb);
                });

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No hay empleados para mostrar'),
                  );
                }

                return _buildResumenCards(docs);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenCards(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    // Contar por estado
    final counts = <String, int>{
      'sin_enviar': 0,
      'en_revision': 0,
      'aprobado': 0,
      'requiere_cambios': 0,
    };
    for (final d in docs) {
      final e = d.data()['estadoHojaDeVida'] as String? ?? 'sin_enviar';
      counts[e] = (counts[e] ?? 0) + 1;
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final chipWidth = compact
                    ? (constraints.maxWidth - 8) / 2
                    : (constraints.maxWidth - 24) / 4;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: chipWidth,
                      child: _statChip(
                        'Sin enviar',
                        counts['sin_enviar']!,
                        Colors.grey.shade600,
                      ),
                    ),
                    SizedBox(
                      width: chipWidth,
                      child: _statChip(
                        'En revisión',
                        counts['en_revision']!,
                        Colors.orange.shade700,
                      ),
                    ),
                    SizedBox(
                      width: chipWidth,
                      child: _statChip(
                        'Aprobado',
                        counts['aprobado']!,
                        Colors.green,
                      ),
                    ),
                    SizedBox(
                      width: chipWidth,
                      child: _statChip(
                        'Correcciones',
                        counts['requiere_cambios']!,
                        Colors.red,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _EmpleadoTile(
              doc: docs[i],
              reviewerUserId: widget.userId,
              empresaId: widget.empresaId,
            ),
            childCount: docs.length,
          ),
        ),
      ],
    );
  }

  Widget _statChip(String label, int count, Color color) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: color),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

// ── Tile de empleado ───────────────────────────────────────────────────────

class _EmpleadoTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String reviewerUserId;
  final String empresaId;

  const _EmpleadoTile({
    required this.doc,
    required this.reviewerUserId,
    required this.empresaId,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final nombre =
        '${data['primerNombre'] ?? ''} ${data['segundoNombre'] ?? ''} '
                '${data['primerApellido'] ?? ''} ${data['segundoApellido'] ?? ''}'
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');
    final cedula = (data['cedula'] ?? doc.id).toString();
    final cedulaDigits = cedula.replaceAll(RegExp(r'\D'), '');
    bool isCedulaValue(String value) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      return cedulaDigits.isNotEmpty && digits == cedulaDigits;
    }

    final usuario =
        [
              data['usuario'],
              data['username'],
              data['userName'],
              data['login'],
              data['nombreUsuario'],
              data['nombreCompleto'],
              nombre,
              doc.id == cedula ? null : doc.id,
              data['email'],
            ]
            .whereType<Object>()
            .map((value) => value.toString().trim())
            .firstWhere(
              (value) => value.isNotEmpty && !isCedulaValue(value),
              orElse: () => nombre.isNotEmpty ? nombre : cedula,
            );
    final estado = data['estadoHojaDeVida'] as String? ?? 'sin_enviar';
    final fotoUrl = data['fotoUrl'] as String?;
    final cargo = (data['cargo'] ?? '') as String;
    final area = (data['areaNombre'] ?? data['area'] ?? '') as String;
    final traceLabel = _correctionTraceLabel(data);

    final subtitleParts = <String>[
      'Usuario: $usuario',
      if (cargo.isNotEmpty) cargo,
      if (area.isNotEmpty) area,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HojaDeVidaViewerScreen(
                empleadoId: doc.id,
                empleadoCedula: cedula,
                empleadoNombre: nombre,
                reviewerUserId: reviewerUserId,
                empresaId: empresaId,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Foto de la HV; si falta, UserAvatar resuelve por cédula.
                UserAvatar(
                  userId: cedula,
                  nameHint: nombre,
                  fotoUrlHint: fotoUrl,
                  radius: 25,
                  backgroundColor: Colors.grey[200],
                  foregroundColor: Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre.isEmpty ? '(sin nombre)' : nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitleParts.join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _EstadoChip(estado: estado),
                      ),
                      if (traceLabel.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          traceLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: estado == 'requiere_cambios'
                                ? Colors.orange.shade800
                                : Colors.green.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chip de estado ─────────────────────────────────────────────────────────

class _EstadoChip extends StatelessWidget {
  final String estado;
  const _EstadoChip({required this.estado});

  @override
  Widget build(BuildContext context) {
    final cfg = _cfgFor(estado);
    return Chip(
      label: Text(
        cfg.$1,
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
      backgroundColor: cfg.$2,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  (String, Color) _cfgFor(String estado) => switch (estado) {
    'en_revision' => ('En revisión', Colors.orange.shade700),
    'aprobado' => ('Aprobado', Colors.green),
    'requiere_cambios' => ('Correcciones', Colors.red),
    _ => ('Sin enviar', Colors.grey.shade600),
  };
}

class _TraceCard extends StatelessWidget {
  final String label;
  final String status;

  const _TraceCard({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'requiere_cambios'
        ? Colors.orange.shade800
        : Colors.green.shade700;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history_rounded, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Visor de hoja de vida (TH) ─────────────────────────────────────────────

class HojaDeVidaViewerScreen extends StatefulWidget {
  final String empleadoId;
  final String empleadoCedula;
  final String empleadoNombre;
  final String reviewerUserId;
  final String empresaId;

  const HojaDeVidaViewerScreen({
    super.key,
    required this.empleadoId,
    required this.empleadoCedula,
    required this.empleadoNombre,
    required this.reviewerUserId,
    this.empresaId = '',
  });

  @override
  State<HojaDeVidaViewerScreen> createState() => _HojaDeVidaViewerScreenState();
}

class _HojaDeVidaViewerScreenState extends State<HojaDeVidaViewerScreen> {
  final _svc = HojaDeVidaService();
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _orgData;
  bool _loading = true;
  bool _generandoPDF = false;
  bool _generandoQr = false;
  String? _reviewerNombre;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // La cédula puede diferir del doc ID (que puede ser el username)
    final cedula = widget.empleadoCedula.isNotEmpty
        ? widget.empleadoCedula
        : widget.empleadoId;

    final results = await Future.wait([
      _svc.getHojaDeVida(widget.empleadoId),
      _svc.getOrgData(cedula),
      FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.reviewerUserId)
          .get(),
    ]);

    final hv = results[0] as Map<String, dynamic>;
    final org = results[1] as Map<String, dynamic>?;
    final reviewerSnap = results[2] as DocumentSnapshot<Map<String, dynamic>>;
    final rd = reviewerSnap.data() ?? {};
    final rNombre = '${rd['primerNombre'] ?? ''} ${rd['primerApellido'] ?? ''}'
        .trim();

    if (!mounted) return;
    setState(() {
      _data = hv;
      _orgData = org;
      _reviewerNombre = rNombre.isEmpty ? widget.reviewerUserId : rNombre;
      _loading = false;
    });
  }

  Widget _buildBottomBar() {
    // El dato viene de getHojaDeVida() que usa la subcollection → campo 'estadoRevision'
    final estado = (_data?['estadoRevision'] as String? ?? '');
    final aprobado = estado == 'aprobado';

    if (aprobado) {
      // Hoja aprobada → descarga del PDF y QR para el carnet.
      final pdfButton = ElevatedButton.icon(
        icon: _generandoPDF
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.picture_as_pdf_rounded),
        label: Text(_generandoPDF ? 'Generando PDF…' : 'Descargar PDF'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _thPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        onPressed: _generandoPDF ? null : _descargarPDF,
      );

      return Column(
        children: [
          pdfButton,
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: _generandoQr
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_2_rounded),
            label: Text(_generandoQr ? 'Generando…' : 'QR para el carnet'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _thPrimary,
              minimumSize: const Size.fromHeight(46),
              side: const BorderSide(color: _thPrimary),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: _generandoQr ? null : _generarQrCarnet,
          ),
          TextButton(
            onPressed: _generandoQr ? null : _confirmarRotarCarnet,
            child: const Text(
              'Se perdió el carnet: generar uno nuevo',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      );
    }

    // Hoja pendiente / en revisión → botones de aprobar y pedir corrección
    final correctionButton = OutlinedButton.icon(
      icon: const Icon(Icons.edit_note, color: Colors.orange),
      label: const Text(
        'Pedir corrección',
        style: TextStyle(color: Colors.orange),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.orange),
      ),
      onPressed: _solicitarCorreccion,
    );
    final approveButton = ElevatedButton.icon(
      icon: const Icon(Icons.check_circle),
      label: const Text('Aprobar'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      onPressed: _aprobar,
    );

    return LayoutBuilder(
      builder: (_, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              correctionButton,
              const SizedBox(height: 8),
              approveButton,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: correctionButton),
            const SizedBox(width: 12),
            Expanded(child: approveButton),
          ],
        );
      },
    );
  }

  /// Genera el QR del carnet de esta persona.
  ///
  /// El QR no lleva la cédula: lleva un token aleatorio que no dice nada de
  /// ella. Un carnet se fotografía y se comparte, y la cédula es además el ID
  /// de la persona en varias colecciones, así que ponerla en el enlace lo
  /// convertiría en una llave.
  ///
  /// Al escanearlo se abre una página con foto, nombre, cargo, empresa y si
  /// sigue vinculada. Nada más: ni correo, ni teléfono, ni documento.
  Future<void> _generarQrCarnet({bool rotar = false}) async {
    if (_generandoQr) return;
    setState(() => _generandoQr = true);
    try {
      final empresaId = widget.empresaId.trim();
      if (empresaId.isEmpty) {
        throw StateError('No hay empresa activa.');
      }
      final token = rotar
          ? await rotarTokenCarnet(
              userId: widget.empleadoId,
              empresaId: empresaId,
            )
          : await asegurarTokenCarnet(
              userId: widget.empleadoId,
              empresaId: empresaId,
            );

      final datos = _data ?? const <String, dynamic>{};
      final bytes = await buildCarnetQrPdf(
        nombre: widget.empleadoNombre,
        cargo: (datos['cargo'] ?? datos['cargoNombre'] ?? '').toString(),
        token: token,
        fotoUrl: (datos['fotoUrl'] ?? '').toString(),
      );
      final limpio = widget.empleadoNombre.replaceAll(' ', '_');
      await Printing.sharePdf(bytes: bytes, filename: 'QR_carnet_$limpio.pdf');
      if (mounted && rotar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Carnet anterior invalidado. Imprime el nuevo QR.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo generar el QR: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoQr = false);
    }
  }

  /// Confirma antes de invalidar un carnet ya impreso.
  Future<void> _confirmarRotarCarnet() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Generar un carnet nuevo?'),
        content: const Text(
          'El QR que ya esté impreso dejará de funcionar. Se usa cuando un '
          'carnet se pierde o se lo quedó alguien que ya no trabaja aquí.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, invalidar el anterior'),
          ),
        ],
      ),
    );
    if (ok == true) await _generarQrCarnet(rotar: true);
  }

  Future<void> _descargarPDF() async {
    if (_data == null || _generandoPDF) return;
    setState(() => _generandoPDF = true);
    try {
      final bytes = await generarHojaDeVidaPDF(
        _data!,
        _orgData,
        widget.empleadoNombre,
      );
      final fileName = 'HV_${widget.empleadoNombre.replaceAll(' ', '_')}.pdf';
      // sharePdf: en web abre el diálogo de descarga/impresión del navegador;
      // en móvil abre el share sheet nativo.
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generando PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoPDF = false);
    }
  }

  Future<void> _aprobar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aprobar hoja de vida'),
        content: Text(
          '¿Confirmas que la hoja de vida de ${widget.empleadoNombre} cumple con todos los requisitos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aprobar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    _showLoading('Aprobando…');
    try {
      await _svc.aprobar(
        widget.empleadoId,
        widget.reviewerUserId,
        _reviewerNombre ?? '',
      );
      // Notificación al empleado
      await _sendNotification(
        'Tu hoja de vida ha sido aprobada por Talento Humano.',
        type: 'hv_aprobada',
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // cierra el loading
      // Recargar datos en pantalla para que aparezca el botón Descargar PDF
      setState(() => _loading = true);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Hoja de vida aprobada'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErr('Error: $e');
    }
  }

  Future<void> _solicitarCorreccion() async {
    final ctrl = TextEditingController();
    final nota = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Solicitar corrección'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Describe qué debe corregir el empleado…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                Navigator.pop(context, ctrl.text.trim());
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nota == null || nota.isEmpty) return;

    _showLoading('Enviando corrección…');
    try {
      await _svc.solicitarCorreccion(
        widget.empleadoId,
        nota,
        widget.reviewerUserId,
        _reviewerNombre ?? '',
      );
      await _sendNotification(
        'Talento Humano ha solicitado correcciones en tu hoja de vida: $nota',
        type: 'hv_correccion',
        extraData: {
          'taskId': 'hoja_vida:${widget.empleadoId}',
          'target': 'hoja_vida',
          'correctionNote': nota,
          'correctionRequestedAt': Timestamp.now(),
          'actionLabel': 'Abrir hoja de vida',
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrección solicitada al empleado')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErr('Error: $e');
    }
  }

  Future<void> _sendNotification(
    String message, {
    String type = 'talento_humano',
    Map<String, dynamic>? extraData,
  }) async {
    try {
      await TaskService().pushNotificationToMany(
        toUserIds: {
          widget.empleadoId,
          widget.empleadoCedula,
        }.where((id) => id.trim().isNotEmpty).toList(),
        title: 'Talento Humano',
        description: message,
        type: type,
        empresaId: widget.empresaId.isNotEmpty ? widget.empresaId : null,
        extraData: extraData,
      );
    } catch (_) {}
  }

  void _showLoading(String msg) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(msg)),
        ],
      ),
    ),
  );

  void _showErr(String msg) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.empleadoNombre.isEmpty
              ? 'Hoja de Vida'
              : widget.empleadoNombre,
        ),
        backgroundColor: _thPrimary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null || _data!.isEmpty
          ? const Center(
              child: Text('Este empleado aún no ha enviado su hoja de vida'),
            )
          : _HvReadOnlyBody(data: _data!, orgData: _orgData),
      bottomNavigationBar: _loading || _data == null || _data!.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _buildBottomBar(),
              ),
            ),
    );
  }
}

// ── Vista read-only de la hoja de vida ─────────────────────────────────────

class _HvReadOnlyBody extends StatelessWidget {
  final Map<String, dynamic> data;
  final Map<String, dynamic>? orgData;
  const _HvReadOnlyBody({required this.data, this.orgData});

  @override
  Widget build(BuildContext context) {
    final estado = data['estadoRevision'] as String? ?? 'sin_enviar';
    final nota = data['revisionNota'] as String?;
    final revisadoPor = data['revisadoPorNombre'] as String?;
    final traceLabel = _correctionTraceLabel({
      ...data,
      'estadoHojaDeVida': estado,
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Estado actual
          _EstadoChip(estado: estado),
          if (traceLabel.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TraceCard(label: traceLabel, status: estado),
          ],
          if (nota != null && nota.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text('Nota: $nota'),
            ),
          ],
          if (revisadoPor != null) ...[
            const SizedBox(height: 4),
            Text(
              'Revisado por: $revisadoPor',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 12),

          // Información organizacional (TBL_ESTRUCTURA_ORGANIZACIONAL)
          if (orgData != null && orgData!.isNotEmpty)
            _card('Información Organizacional', [
              _row('Cargo', orgData!['cargo'] ?? orgData!['cargoId']),
              _row('Área', orgData!['areaNombre'] ?? orgData!['area']),
              _row('Jefe directo', orgData!['jefe_directo']),
              _row(
                'Centro de costos',
                orgData!['centro_nombre'] ?? orgData!['centroCostos'],
              ),
            ])
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, size: 14, color: Colors.grey),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Sin cargo/área asignado en la estructura organizacional',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),

          // Foto (clickeable para ampliar)
          Center(
            child: GestureDetector(
              onTap: data['fotoUrl'] != null
                  ? () => previewImage(context, data['fotoUrl'] as String)
                  : null,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: data['fotoUrl'] != null
                        ? NetworkImage(data['fotoUrl'] as String)
                        : null,
                    child: data['fotoUrl'] == null
                        ? const Icon(Icons.person, size: 50, color: Colors.grey)
                        : null,
                  ),
                  if (data['fotoUrl'] != null)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: _thPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.zoom_in,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          _card('Datos Personales', [
            _row(
              'Nombre',
              '${data['primerNombre'] ?? ''} ${data['segundoNombre'] ?? ''} ${data['primerApellido'] ?? ''} ${data['segundoApellido'] ?? ''}'
                  .trim(),
            ),
            _row('Lugar expedición', data['lugarExpedicion']),
            _row('Email', data['email']),
            _row('Teléfono', data['telefono']),
            _row('Dirección', data['direccion']),
            _row('Ciudad', data['ciudad']),
            _row('Barrio', data['barrio']),
            _row('EPS', data['eps']),
            _row('Fondo de pensiones', data['fondoPensiones']),
            _row('Fondo de cesantías', data['fondoCesantias']),
            _docLink(context, data['cedulaDocUrl'], 'Documento de cédula'),
            _docLink(context, data['epsUrl'], 'Soporte EPS'),
            _docLink(context, data['pensionUrl'], 'Soporte pensiones'),
            _docLink(context, data['cesantiasUrl'], 'Soporte cesantías'),
          ]),

          _card('Perfil Demográfico (solo plataforma)', [
            _row('Estado civil', data['estadoCivil']),
            _row('Número de hijos', data['numeroHijos']),
            _row('Tipo de sangre', data['tipoSangre']),
            _row('Fecha de nacimiento', data['fechaNacimiento']),
            _row('Lugar de nacimiento', data['lugarNacimiento']),
            _row('Edad', data['edad']),
            _row('Género', data['genero']),
            _row('Personas a cargo', data['personasCargo']),
            _row('Estrato', data['estrato']),
            _row('Movilización', data['tipoVehiculo']),
            _row('Contacto de emergencia', data['contactoEmergenciaNombre']),
            _row('Teléfono de emergencia', data['contactoEmergenciaTelefono']),
          ]),

          _card('Antecedentes', [
            _docLink(context, data['procUrl'], 'Procuraduría'),
            _docLink(context, data['contrUrl'], 'Contraloría'),
            _docLink(context, data['polUrl'], 'Policía Nacional'),
            _docLink(context, data['medUrl'], 'Medidas Correctivas'),
          ]),

          _card('Datos Bancarios', [
            _row('Banco', data['banco']),
            _docLink(context, data['certBancoUrl'], 'Certificado bancario'),
          ]),

          _card('Formación Académica', [
            _row(
              'Bachillerato',
              '${data['bachInst'] ?? ''} (${data['bachFecha'] ?? ''})',
            ),
            _docLink(context, data['bachillerUrl'], 'Soporte bachillerato'),
            if (data['hasUniversity'] == true) ...[
              _divider(),
              _row(
                'Universidad',
                '${data['uniCarr'] ?? ''} — ${data['uniInst'] ?? ''} (${data['uniFecha'] ?? ''})',
              ),
              _docLink(context, data['uniUrl'], 'Soporte universidad'),
              if (data['hasTarjetaProf'] == true) ...[
                _row('Tarjeta Profesional', data['tarjetaNumero']),
                _docLink(
                  context,
                  data['tarjetaUrl'],
                  'Soporte tarjeta profesional',
                ),
              ],
            ],
            if (data['hasSecondCareer'] == true) ...[
              _divider(),
              _row(
                'Segunda carrera',
                '${data['secCarr'] ?? ''} — ${data['secInst'] ?? ''} (${data['secFecha'] ?? ''})',
              ),
              _docLink(context, data['secUrl'], 'Soporte segunda carrera'),
            ],
            if (data['hasEspecializacion'] == true) ...[
              _divider(),
              _row(
                'Especialización',
                '${data['espProg'] ?? ''} — ${data['espInst'] ?? ''} (${data['espFecha'] ?? ''})',
              ),
              _docLink(context, data['espUrl'], 'Soporte especialización'),
            ],
            if (data['hasMaestria'] == true) ...[
              _divider(),
              _row(
                'Maestría',
                '${data['maeProg'] ?? ''} — ${data['maeInst'] ?? ''} (${data['maeFecha'] ?? ''})',
              ),
              _docLink(context, data['maeUrl'], 'Soporte maestría'),
            ],
          ]),

          if (data['hasCertificados'] == true)
            _card('Cursos Complementarios', [
              for (final c
                  in (data['certificados'] as List<dynamic>? ?? [])) ...[
                _row('Curso', '${c['nombre'] ?? ''} (${c['fecha'] ?? ''})'),
                _docLink(context, c['url'] as String?, 'Soporte del curso'),
                _divider(),
              ],
            ]),

          _card('Experiencia Laboral', [
            for (final e in (data['experiencias'] as List<dynamic>? ?? [])) ...[
              _row(
                'Empresa / Cargo',
                '${e['empresa'] ?? ''} — ${e['cargo'] ?? ''}',
              ),
              _row('Período', '${e['inicio'] ?? ''} → ${e['fin'] ?? ''}'),
              _docLink(context, e['soporteUrl'] as String?, 'Soporte laboral'),
              _divider(),
            ],
          ]),

          const SizedBox(height: 80), // espacio para el BottomBar
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
    elevation: 1,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: _thPrimary,
              fontSize: 15,
            ),
          ),
          const Divider(thickness: 1.2),
          ...children,
        ],
      ),
    ),
  );

  Widget _row(String label, dynamic value) {
    final txt = value?.toString() ?? '';
    if (txt.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 14),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: txt),
          ],
        ),
      ),
    );
  }

  Widget _docLink(BuildContext context, String? url, String label) {
    if (url == null || url.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '$label: No subido',
          style: TextStyle(color: Colors.red.shade400, fontSize: 13),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // Vista previa
          Tooltip(
            message: 'Vista previa',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => previewDocument(context, url, label),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _thPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _thPrimary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.visibility_outlined,
                      size: 14,
                      color: _thPrimary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Ver',
                      style: TextStyle(
                        color: _thPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Descargar
          Tooltip(
            message: 'Descargar',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () =>
                  launchUrlString(url, mode: LaunchMode.externalApplication),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.download_outlined, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      'Descargar',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(thickness: 0.5, height: 16);
}

// ── Sheet de filtros ───────────────────────────────────────────────────────

class _FiltrosSheet extends StatefulWidget {
  final String? estadoActual;
  final String? areaActual;
  final String? cargoActual;
  final List<String> areas;
  final List<String> cargos;
  final void Function(String? estado, String? area, String? cargo) onApply;

  const _FiltrosSheet({
    required this.estadoActual,
    required this.areaActual,
    required this.cargoActual,
    required this.areas,
    required this.cargos,
    required this.onApply,
  });

  @override
  State<_FiltrosSheet> createState() => _FiltrosSheetState();
}

class _FiltrosSheetState extends State<_FiltrosSheet> {
  String? _estado;
  String? _area;
  String? _cargo;

  @override
  void initState() {
    super.initState();
    _estado = widget.estadoActual;
    _area = widget.areaActual;
    _cargo = widget.cargoActual;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Filtros',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _estado = null;
                      _area = null;
                      _cargo = null;
                    });
                  },
                  child: const Text('Limpiar todo'),
                ),
              ],
            ),
            const Divider(),
            const Text(
              'Estado hoja de vida',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children:
                  [
                        null,
                        'sin_enviar',
                        'en_revision',
                        'aprobado',
                        'requiere_cambios',
                      ]
                      .map(
                        (v) => ChoiceChip(
                          label: Text(_estadoLabel(v)),
                          selected: _estado == v,
                          onSelected: (_) => setState(() => _estado = v),
                        ),
                      )
                      .toList(),
            ),
            if (widget.areas.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Área',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: _area,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                hint: const Text('Todas las áreas'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas')),
                  ...widget.areas.map(
                    (a) => DropdownMenuItem(value: a, child: Text(a)),
                  ),
                ],
                onChanged: (v) => setState(() => _area = v),
              ),
            ],
            if (widget.cargos.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Cargo',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: _cargo,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                hint: const Text('Todos los cargos'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  ...widget.cargos.map(
                    (c) => DropdownMenuItem(value: c, child: Text(c)),
                  ),
                ],
                onChanged: (v) => setState(() => _cargo = v),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _thPrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                widget.onApply(_estado, _area, _cargo);
                Navigator.pop(context);
              },
              child: const Text('Aplicar filtros'),
            ),
          ],
        ),
      ),
    );
  }

  String _estadoLabel(String? v) => switch (v) {
    'sin_enviar' => 'Sin enviar',
    'en_revision' => 'En revisión',
    'aprobado' => 'Aprobado',
    'requiere_cambios' => 'Correcciones',
    _ => 'Todos',
  };
}
