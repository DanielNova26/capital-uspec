// lib/compras/compras_req_excel_parser.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'web_drag_drop.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import 'compras_models.dart';
import 'compras_catalog_logic.dart';
import 'compras_excel_download.dart';
import 'compras_excel_export.dart';
import 'compras_document_scanner_stub.dart'
    if (dart.library.io) 'compras_document_scanner_io.dart'
    as document_scanner;
import 'compras_recepcion_logic.dart';
import 'compras_service.dart';
import 'compras_req_engine.dart';
import 'compras_validation.dart';
import 'abastecimiento_screen.dart';
import '../core/guarded_module_page.dart';
import '../home/widgets/home_shared_widgets.dart' show CompanyNameWidget;
import '../widgets/internal_module_layout.dart';
import '../widgets/user_avatar.dart' show UserNameText;

// ══════════════════════════════════════════════════════════════════════════════
// COLORES DEL MÓDULO
// ══════════════════════════════════════════════════════════════════════════════

const Color kComprasPrimary = Color(0xFF1565C0); // Blue 800
const Color kComprasAccent = Color(0xFF42A5F5); // Blue 300
const Color kComprasBg = Color(0xFFF0F4FF); // Fondo azul muy claro
const Color kComprasCard = Colors.white;
const Color kComprasGreen = Color(0xFF16A34A);
const Color kComprasRed = Color(0xFFDC2626);
const String _kFont = 'Arial';

Future<T?> _showComprasAdaptiveSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  Color backgroundColor = Colors.white,
  ShapeBorder? shape,
  bool desktopHeader = true,
}) {
  final media = MediaQuery.of(context);
  Widget framedContent(BuildContext modalContext) {
    if (!desktopHeader) return builder(modalContext);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 8, 9),
          child: Row(
            children: [
              const Icon(
                Icons.shopping_cart_outlined,
                color: kComprasPrimary,
                size: 21,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(modalContext),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cerrar'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(fit: FlexFit.loose, child: builder(modalContext)),
      ],
    );
  }

  if (media.size.width < 700) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      backgroundColor: backgroundColor,
      constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
      shape:
          shape ??
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
      builder: framedContent,
    );
  }

  return showDialog<T>(
    context: context,
    useSafeArea: useSafeArea,
    builder: (dialogContext) => Dialog(
      backgroundColor: backgroundColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 780,
          maxHeight: MediaQuery.of(dialogContext).size.height * 0.88,
        ),
        child: framedContent(dialogContext),
      ),
    ),
  );
}

Widget _comprasDialogTitle(
  BuildContext context,
  String title, {
  IconData icon = Icons.info_outline,
}) {
  return Row(
    children: [
      Icon(icon, size: 21, color: kComprasPrimary),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: _kFont,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      IconButton(
        tooltip: 'Cerrar',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close, size: 20),
      ),
    ],
  );
}

Widget _comprasResponsiveList<T>({
  required List<T> items,
  required Widget Function(BuildContext context, T item, int index) itemBuilder,
  EdgeInsets padding = const EdgeInsets.fromLTRB(14, 0, 14, 80),
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 760) {
        return ListView.builder(
          padding: padding,
          itemCount: items.length,
          itemBuilder: (context, index) =>
              itemBuilder(context, items[index], index),
        );
      }
      final usableWidth = constraints.maxWidth - padding.horizontal - 14;
      final cardWidth = usableWidth / 2;
      return SingleChildScrollView(
        padding: padding,
        child: Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (var index = 0; index < items.length; index++)
              SizedBox(
                width: cardWidth,
                child: itemBuilder(context, items[index], index),
              ),
          ],
        ),
      );
    },
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════════════════════════════

String _normalizarNombre(String input) {
  return input.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

String _normalizarUM(String input) {
  return input.trim();
}

String _fmtFecha(Timestamp ts) {
  return DateFormat('dd/MM/yyyy', 'es').format(ts.toDate());
}

String _fmtFechaHora(Timestamp ts) {
  return DateFormat('dd/MM/yyyy HH:mm', 'es').format(ts.toDate());
}

Future<DateTime?> _solicitarVigenciaDespuesDeCargar(
  BuildContext context, {
  required String docKey,
  required Map<String, String> labels,
  DateTime? initialDate,
}) async {
  if (!documentoRequiereVigencia(docKey) || !context.mounted) return null;
  final today = DateUtils.dateOnly(DateTime.now());
  final suggested =
      initialDate != null && !DateUtils.dateOnly(initialDate).isBefore(today)
      ? DateUtils.dateOnly(initialDate)
      : today.add(const Duration(days: 365));
  final selected = await showDatePicker(
    context: context,
    initialDate: suggested,
    firstDate: today,
    lastDate: DateTime(today.year + 15, 12, 31),
    helpText: 'Vigente hasta · ${labels[docKey] ?? docKey}',
    cancelText: 'Ahora no',
    confirmText: 'Guardar vigencia',
  );
  if (selected == null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'El archivo quedó cargado, pero debes indicar “Vigente hasta” para '
          '${labels[docKey] ?? docKey} antes de completar el registro.',
          style: const TextStyle(fontFamily: _kFont),
        ),
        backgroundColor: kComprasRed,
      ),
    );
  }
  return selected;
}

bool _documentosAsociadosCompletos(Map<String, DocAdjunto> documentos) =>
    kDocumentosAsociadosLabels.keys.every(
      (key) =>
          documentos[key]?.tieneDoc == true &&
          documentos[key]?.aprobado == true &&
          (!documentoRequiereVigencia(key) ||
              documentos[key]?.fechaVencimiento != null),
    );

List<String> docsParaCategoria(String? categoria) {
  final cat = (categoria ?? '').trim().toLowerCase();

  // Puente de compatibilidad: hasta terminar la migración completa al motor
  // dinámico (ReqEngine), usamos un subconjunto por categoría para evitar
  // sobre-exigir documentos en vistas históricas/resumen.
  final base = <String>[
    'certCalidad',
    'evidenciaEtiqueta',
    'fechaVencimientoEtiqueta',
  ];

  final proteina = <String>[
    'guiaTransporte',
    'guiaSacrificio',
    'permisoZoo',
    'vistoInvima',
    'declImport',
    'docTransporte',
  ];

  final aseo = <String>['hojaSeguridad', 'sustanciasPermitidas', 'rotuladoSGA'];

  final fruver = <String>['permisoZoo', 'vistoInvima', 'declImport'];

  final merged = <String>[...base];
  if (cat.contains('prote')) merged.addAll(proteina);
  if (cat.contains('aseo')) merged.addAll(aseo);
  if (cat.contains('fruv')) merged.addAll(fruver);

  if (merged.length == base.length) {
    // Categoría no clasificada: mantener solo documentos universales.
    merged.addAll(['guiaTransporte', 'docTransporte']);
  }

  // Únicos + existentes en mapa de etiquetas para evitar llaves inválidas.
  final uniques = <String>[];
  for (final key in merged) {
    if (!kDocRecepcionLabels.containsKey(key)) continue;
    if (!uniques.contains(key)) uniques.add(key);
  }
  return uniques;
}

// ══════════════════════════════════════════════════════════════════════════════
// FUNCIÓN PÚBLICA: navegar directamente al detalle de un proveedor
// (usada desde notificaciones del Home)
// ══════════════════════════════════════════════════════════════════════════════

/// Navega directamente al formulario de edición de un proveedor,
/// cargando sus datos desde Firestore por su ID.
/// Usada desde las notificaciones de rechazo de documentos.
Future<void> abrirDetalleProveedor(
  BuildContext context, {
  required String userId,
  required String proveedorId,
  String? correccionTaskId,
  String? correccionDocKey,
}) async {
  final svc = ComprasService();
  ProveedorDoc? prov;
  String empresaId = '';
  try {
    final snap = await FirebaseFirestore.instance
        .collection('TBL_COMPRAS_PROVEEDORES')
        .doc(proveedorId)
        .get();
    if (snap.exists && snap.data() != null) {
      prov = ProveedorDoc.fromMap(snap.id, snap.data()!);
      empresaId = prov.empresaId;
    }
  } catch (_) {}

  if (!context.mounted) return;

  if (prov == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo encontrar el proveedor.'),
        backgroundColor: Colors.redAccent,
      ),
    );
    return;
  }

  // Al entrar por notificación no venimos del dashboard, así que el rol no
  // llega por parámetro: hay que resolverlo para saber si mostrar "Revertir".
  var esAdmin = false;
  try {
    final rol = await svc.resolveRolUsuario(empresaId, userId);
    esAdmin = normalizeComprasRol(rol?.rol) == kRolAdmin;
  } catch (_) {}

  if (!context.mounted) return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _ProveedorFormScreen(
        empresaId: empresaId,
        svc: svc,
        existing: prov,
        userId: userId,
        correccionTaskId: correccionTaskId,
        correccionDocKey: correccionDocKey,
        esAdmin: esAdmin,
      ),
    ),
  );
}

/// Abre los documentos asociados a una marca desde una notificación de
/// vigencia. Las fichas técnicas y registros sanitarios pertenecen a este
/// expediente, no al proveedor.
Future<void> abrirDocumentosMarcaCompras(
  BuildContext context, {
  required String userId,
  required String marcaId,
}) async {
  final svc = ComprasService();
  MarcaDoc? marca;
  try {
    final snap = await FirebaseFirestore.instance
        .collection('TBL_COMPRAS_MARCAS')
        .doc(marcaId)
        .get();
    if (snap.exists && snap.data() != null) {
      marca = MarcaDoc.fromMap(snap.id, snap.data()!);
    }
  } catch (_) {}

  if (!context.mounted) return;
  if (marca == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo encontrar la marca notificada.'),
        backgroundColor: Colors.redAccent,
      ),
    );
    return;
  }

  await _showComprasAdaptiveSheet<void>(
    context: context,
    title: 'Documentos asociados · ${marca.descripcion}',
    desktopHeader: false,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DocumentosAsociadosSheet(
      titulo: marca!.descripcion,
      marcaId: marca.id,
      empresaId: marca.empresaId,
      userId: userId,
      svc: svc,
      documentos: marca.documentosAsociados,
      onSave: (documentos) => svc.actualizarDocumentosAsociadosMarca(
        marcaId: marca!.id,
        documentos: documentos,
      ),
    ),
  );
}

/// Navega al formulario del proveedor asociado a una ficha técnica rechazada.
/// Carga la ficha por ID, obtiene proveedorId, y abre [abrirDetalleProveedor].
/// Usada desde notificaciones de tipo ficha_rechazada.
Future<void> abrirDetalleFichaRechazada(
  BuildContext context, {
  required String userId,
  required String fichaId,
}) async {
  Map<String, dynamic>? fichaData;
  try {
    final snap = await FirebaseFirestore.instance
        .collection('TBL_COMPRAS_FICHAS_TECNICAS')
        .doc(fichaId)
        .get();
    if (snap.exists) fichaData = snap.data();
  } catch (_) {}

  if (!context.mounted) return;

  if (fichaData == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo encontrar la ficha técnica rechazada.'),
        backgroundColor: Colors.redAccent,
      ),
    );
    return;
  }

  final proveedorId = (fichaData['proveedorId'] as String?) ?? '';
  if (proveedorId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ficha sin proveedor asociado.')),
    );
    return;
  }

  // El usuario debe ir al proveedor para volver a cargar la ficha rechazada.
  await abrirDetalleProveedor(
    context,
    userId: userId,
    proveedorId: proveedorId,
  );
}

/// Navega al formulario de la recepción cuando Calidad rechaza un documento.
/// Usada desde notificaciones globales de Compras/Bodega.
Future<void> abrirDetalleRecepcionCompras(
  BuildContext context, {
  required String userId,
  required String recepcionId,
  String? correccionTaskId,
  String? correccionDocKey,
  String? correccionProductoId,
}) async {
  final cleanId = recepcionId.replaceFirst('recepcion:', '').trim();
  if (cleanId.isEmpty) return;

  final svc = ComprasService();
  RecepcionDoc? recepcion;
  try {
    final snap = await FirebaseFirestore.instance
        .collection('TBL_COMPRAS_RECEPCIONES')
        .doc(cleanId)
        .get();
    if (snap.exists && snap.data() != null) {
      recepcion = RecepcionDoc.fromMap(snap.id, snap.data()!);
    }
  } catch (_) {}

  if (!context.mounted) return;

  if (recepcion == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo encontrar la recepción notificada.'),
        backgroundColor: Colors.redAccent,
      ),
    );
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _NuevaRecepcionScreen(
        empresaId: recepcion!.empresaId,
        svc: svc,
        existing: recepcion,
        userId: userId,
        correccionTaskId: correccionTaskId,
        correccionDocKey: correccionDocKey,
        correccionProductoId: correccionProductoId,
      ),
    ),
  );
}

/// Lleva una tarea de corrección al punto exacto de Compras donde se reemplaza
/// su documento. La carga persiste el documento y deja la tarea en revisión de
/// Calidad; por eso no se usa la pantalla genérica de evidencias.
Future<bool> abrirCorreccionComprasDesdeTarea(
  BuildContext context, {
  required String userId,
  required String taskId,
  required Map<String, dynamic> tarea,
}) async {
  final raw = tarea['comprasCorreccion'];
  final correction = raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};
  var tipo = (correction['tipo'] ?? '').toString().trim();
  var entidadId = (correction['entidadId'] ?? '').toString().trim();
  final docKey = (correction['docKey'] ?? tarea['docKey'] ?? '')
      .toString()
      .trim();
  final productoId = (correction['productoId'] ?? '').toString().trim();
  final esRequerimiento = correction['esRequerimiento'] == true;

  // Compatibilidad con tareas generadas antes de guardar comprasCorreccion.
  final legacyRef = (tarea['recepcionId'] ?? '').toString().trim();
  if (tipo.isEmpty) {
    if (legacyRef.startsWith('proveedor:')) tipo = 'proveedor';
    if (legacyRef.startsWith('ficha:')) tipo = 'ficha';
    if (tipo.isEmpty && legacyRef.isNotEmpty) tipo = 'recepcion';
  }
  if (entidadId.isEmpty) {
    final prefix = '$tipo:';
    entidadId = legacyRef.startsWith(prefix)
        ? legacyRef.substring(prefix.length).trim()
        : legacyRef;
  }

  if (taskId.trim().isEmpty || entidadId.isEmpty || !context.mounted) {
    return false;
  }

  switch (tipo) {
    case 'proveedor':
      await abrirDetalleProveedor(
        context,
        userId: userId,
        proveedorId: entidadId,
        correccionTaskId: taskId,
        correccionDocKey: docKey,
      );
      return true;
    case 'recepcion':
      await abrirDetalleRecepcionCompras(
        context,
        userId: userId,
        recepcionId: entidadId,
        correccionTaskId: taskId,
        correccionDocKey: docKey,
        correccionProductoId: productoId,
      );
      return true;
    case 'marca':
      await abrirDocumentosMarcaCompras(
        context,
        userId: userId,
        marcaId: entidadId,
      );
      return true;
    case 'ficha':
      final snap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_FICHAS_TECNICAS')
          .doc(entidadId)
          .get();
      if (!snap.exists || snap.data() == null || !context.mounted) {
        return false;
      }
      final ficha = FichaTecnicaDoc.fromMap(snap.id, snap.data()!);
      if (esRequerimiento &&
          ficha.documentoActual?.aprobadoConRequerimientos == true) {
        var documento = ficha.documentoActual!;
        final service = ComprasService();
        await _showComprasAdaptiveSheet<void>(
          context: context,
          title: 'Atender requerimiento de ficha técnica',
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.white,
          builder: (_) => StatefulBuilder(
            builder: (sheetContext, setSheetState) => SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: _DocAttachButton(
                label: ficha.marcaNombre.isEmpty
                    ? 'Ficha técnica · ${ficha.productoNombre}'
                    : 'Ficha técnica · ${ficha.productoNombre} / ${ficha.marcaNombre}',
                doc: documento,
                editable: false,
                qualityRequired: true,
                onAttach: () {},
                onView: () => _abrirUrl(sheetContext, documento.url),
                onRequirementUpload: (bytes, name) async {
                  final ext = name.toLowerCase().split('.').last;
                  final actualizado = await service.agregarSoporteRequerimiento(
                    empresaId: ficha.empresaId,
                    tipo: 'ficha',
                    entidadId: ficha.id,
                    docKey: 'fichaTecnica',
                    userId: userId,
                    bytes: bytes,
                    nombre: name,
                    contentType: ext == 'pdf'
                        ? 'application/pdf'
                        : 'image/$ext',
                  );
                  setSheetState(() => documento = actualizado);
                },
              ),
            ),
          ),
        );
        return true;
      }
      await _showComprasAdaptiveSheet<void>(
        context: context,
        title: 'Corregir ficha técnica rechazada',
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _SubirFichaSheet(
          empresaId: ficha.empresaId,
          svc: ComprasService(),
          productoId: ficha.productoId,
          productoNombre: ficha.productoNombre,
          productoCategoria: ficha.productoCategoria,
          marcaId: ficha.marcaId,
          marcaNombre: ficha.marcaNombre,
          userId: userId,
          fichasExistentes: const [],
          fichaExistente: ficha,
          correccionTaskId: taskId,
        ),
      );
      return true;
    default:
      return false;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// COMPRAS DASHBOARD SCREEN — pantalla principal (hub)
// ══════════════════════════════════════════════════════════════════════════════

class ComprasDashboardScreen extends StatelessWidget {
  final String userId;
  final String empresaId;

  /// Rol del usuario: 'calidad' | 'compras' | 'bodega' | null (sin restricción)
  final String? rolCompras;

  const ComprasDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.rolCompras,
  });

  String? get _rolNormalizado => normalizeComprasRol(rolCompras);
  bool get _esBodega => _rolNormalizado == kRolBodega;
  bool get _esCalidad => _rolNormalizado == kRolCalidad;
  bool get _esCompras => _rolNormalizado == kRolCompras;
  bool get _esConsultas => _rolNormalizado == kRolConsultas;
  bool get _esAdmin => _rolNormalizado == kRolAdmin;

  /// Oculta la sección de gestión (proveedores/productos/marcas/recepción)
  bool get _sinGestion => _esConsultas;

  @override
  Widget build(BuildContext context) {
    final svc = ComprasService();

    String subtituloRol = 'Gestión de proveedores, productos y recepciones';
    Color colorRol = kComprasPrimary;
    if (_esAdmin) {
      subtituloRol =
          'Admin Documental — acceso total, puede eliminar registros';
      colorRol = const Color(0xFF7B1FA2);
    } else if (_esBodega) {
      subtituloRol = 'Bodega — recepción de mercancía y consultas';
      colorRol = const Color(0xFF0277BD);
    } else if (_esCalidad) {
      subtituloRol = 'Calidad — revisión y aprobación de documentos';
      colorRol = const Color(0xFF15803D);
    } else if (_esCompras) {
      subtituloRol = 'Compras — gestión de proveedores y productos';
      colorRol = kComprasPrimary;
    } else if (_esConsultas) {
      subtituloRol = 'Consultas — solo lectura';
      colorRol = const Color(0xFF283593);
    }

    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;

    return GuardedModulePage(
      userIdentity: userId,
      appId: 'comprasdashboard',
      pageTitle: 'Compras & Bodega',
      fallbackEmpresaId: empresaId,
      child: InternalModuleLayout(
        userId: userId,
        empresaId: empresaId,
        title: 'Compras & Bodega',
        subtitle: subtituloRol,
        badge: _rolNormalizado == null
            ? null
            : labelComprasRol(_rolNormalizado),
        accentColor: colorRol,
        headerActions: [
          CompanyNameWidget(
            empresaId: empresaId,
            style: TextStyle(
              color: isDesktop ? colorRol : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isDesktop ? 14 : 12,
            ),
          ),
        ],
        child: isDesktop
            ? _buildWebLayout(context, svc, subtituloRol, colorRol)
            : _buildMobileLayout(context, svc, subtituloRol, colorRol),
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    ComprasService svc,
    String subtituloRol,
    Color colorRol,
  ) {
    return _buildDashboardShell(
      context,
      svc,
      subtituloRol,
      colorRol,
      isDesktop: false,
    );
  }

  Widget _buildWebLayout(
    BuildContext context,
    ComprasService svc,
    String subtituloRol,
    Color colorRol,
  ) {
    return _buildDashboardShell(
      context,
      svc,
      subtituloRol,
      colorRol,
      isDesktop: true,
    );
  }

  Widget _buildDashboardShell(
    BuildContext context,
    ComprasService svc,
    String subtituloRol,
    Color colorRol, {
    required bool isDesktop,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final outerPadding = isDesktop ? 28.0 : 16.0;
    final availableWidth = screenWidth - (outerPadding * 2);
    // InternalModuleViewport incluye el padding dentro de su ancho máximo.
    // Restarlo también del tope evita calcular tarjetas más anchas que el
    // espacio real y permite que tres columnas sí quepan en escritorio.
    final maxInnerWidth = 1240.0 - (outerPadding * 2);
    final contentWidth = availableWidth > maxInnerWidth
        ? maxInnerWidth
        : availableWidth;
    final columns = contentWidth >= 1050
        ? 3
        : contentWidth >= 620
        ? 2
        : 1;
    final gap = columns > 1 ? 18.0 : 0.0;
    final cardWidth = (contentWidth - (gap * (columns - 1))) / columns;
    final cards = _buildDashboardCards(context, svc, cardWidth);

    return SingleChildScrollView(
      child: InternalModuleViewport(
        maxWidth: 1240,
        padding: EdgeInsets.all(isDesktop ? 28 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModuleCard(
              padding: EdgeInsets.all(isDesktop ? 24 : 18),
              child: isDesktop
                  ? Row(
                      children: [
                        Expanded(
                          child: _buildOverviewLead(colorRol, subtituloRol),
                        ),
                        const SizedBox(width: 24),
                        Expanded(child: _buildOverviewContext(colorRol)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildOverviewLead(colorRol, subtituloRol),
                        const SizedBox(height: 16),
                        _buildOverviewContext(colorRol),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            if (columns > 1)
              Wrap(spacing: 18, runSpacing: 18, children: cards)
            else
              Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    cards[i],
                    if (i < cards.length - 1) const SizedBox(height: 14),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDashboardCards(
    BuildContext context,
    ComprasService svc,
    double cardWidth,
  ) {
    Widget card({
      required IconData icon,
      required String titulo,
      required String subtitulo,
      required Color color,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: cardWidth,
        child: _MenuTile(
          icon: icon,
          titulo: titulo,
          subtitulo: subtitulo,
          color: color,
          onTap: onTap,
        ),
      );
    }

    return [
      if (!_sinGestion && !_esBodega || _esAdmin) ...[
        card(
          icon: Icons.business,
          titulo: 'Proveedores',
          subtitulo: 'Registrar y gestionar proveedores',
          color: const Color(0xFF1565C0),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _ProveedoresScreen(
                empresaId: empresaId,
                svc: svc,
                userId: userId,
                esAdmin: _esAdmin,
              ),
            ),
          ),
        ),
        card(
          icon: Icons.label_important,
          titulo: 'Marcas',
          subtitulo: 'Gestionar marcas vinculadas a productos',
          color: const Color(0xFF1976D2),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  _MarcasScreen(empresaId: empresaId, svc: svc, userId: userId),
            ),
          ),
        ),
        card(
          icon: Icons.inventory_2,
          titulo: 'Productos',
          subtitulo: 'Catálogo de productos del almacén',
          color: const Color(0xFF0277BD),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _ProductosScreen(
                empresaId: empresaId,
                svc: svc,
                userId: userId,
              ),
            ),
          ),
        ),
      ],
      if (!_esConsultas)
        card(
          icon: Icons.local_shipping,
          titulo: 'Recepciones',
          subtitulo: 'Registrar, corregir y consultar recepciones',
          color: kComprasPrimary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _RecepcionesScreen(
                empresaId: empresaId,
                svc: svc,
                userId: userId,
                puedeEliminar: _esAdmin,
              ),
            ),
          ),
        ),
      card(
        icon: Icons.route_outlined,
        titulo: 'Abastecimiento',
        subtitulo: _esBodega
            ? 'Entregas programadas y recepción del día'
            : 'Programación, novedades y seguimiento de entregas',
        color: const Color(0xFF0F4C81),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AbastecimientoScreen(
              empresaId: empresaId,
              userId: userId,
              rolCompras: _rolNormalizado,
            ),
          ),
        ),
      ),
      card(
        icon: Icons.manage_search,
        titulo: 'Consultas',
        subtitulo: 'Consultar por proveedor, producto o recepción',
        color: const Color(0xFF283593),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _ConsultasScreen(
              empresaId: empresaId,
              svc: svc,
              esAdmin: _esAdmin,
              // Solo Calidad (y Admin) pueden descargar/exportar. El resto de
              // roles consulta en modo solo-lectura.
              canExport: _esCalidad || _esAdmin,
            ),
          ),
        ),
      ),
      card(
        icon: Icons.event_note_outlined,
        titulo: 'Vigencias documentales',
        subtitulo: 'Documentos vencidos y próximos a vencer',
        color: const Color(0xFFB45309),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _VencimientosScreen(empresaId: empresaId),
          ),
        ),
      ),
      if (_esCalidad || _esAdmin)
        card(
          icon: Icons.verified_user,
          titulo: 'Documentos pendientes',
          subtitulo: 'Revisar, aprobar o rechazar documentos',
          color: const Color(0xFF15803D),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _CalidadScreen(
                empresaId: empresaId,
                svc: svc,
                userId: userId,
                esAdmin: _esAdmin,
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildOverviewLead(Color colorRol, String subtituloRol) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorRol.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            _esAdmin
                ? Icons.admin_panel_settings_outlined
                : _esBodega
                ? Icons.warehouse_outlined
                : Icons.shopping_cart_outlined,
            color: colorRol,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accesos del módulo',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: colorRol,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Operación de Compras & Bodega',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtituloRol,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewContext(Color colorRol) {
    final pills = <String>[
      if (!_esConsultas) 'Recepción activa',
      if (!_sinGestion && !_esBodega) 'Gestión maestra',
      if (_esCalidad) 'Control de calidad',
      if (_esConsultas) 'Solo lectura',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contexto operativo',
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: pills
              .map(
                (pill) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorRol.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colorRol.withOpacity(0.18)),
                  ),
                  child: Text(
                    pill,
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colorRol,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _VencimientoItem {
  final String documento;
  final String titular;
  final String origen;
  final DocAdjunto doc;

  const _VencimientoItem({
    required this.documento,
    required this.titular,
    required this.origen,
    required this.doc,
  });

  /// null = el documento requiere vigencia pero nadie registró la fecha.
  DateTime? get fecha => doc.fechaVencimiento?.toDate();

  bool get sinFecha => fecha == null;

  /// Solo válido cuando [fecha] no es null.
  int diasDesde(DateTime hoy) {
    final f = fecha!;
    final inicio = DateTime(hoy.year, hoy.month, hoy.day);
    final fin = DateTime(f.year, f.month, f.day);
    return fin.difference(inicio).inDays;
  }
}

class _VencimientosScreen extends StatefulWidget {
  final String empresaId;

  /// Filtro con el que abre la pantalla ('vencidos', '30', '60', 'todos',
  /// 'sin_fecha'). Permite que el Resumen navegue directo al grupo tocado.
  final String? filtroInicial;

  const _VencimientosScreen({required this.empresaId, this.filtroInicial});

  @override
  State<_VencimientosScreen> createState() => _VencimientosScreenState();
}

class _VencimientosScreenState extends State<_VencimientosScreen> {
  late Future<List<_VencimientoItem>> _future;
  String _filtro = '60';

  /// null = decidir por ancho (escritorio sí, móvil no) hasta que el usuario toque el chip.
  bool? _verCalendario;
  DateTime _mesVisible = DateTime(DateTime.now().year, DateTime.now().month);

  /// Día tocado en el calendario: la lista muestra solo lo que vence ese día.
  DateTime? _diaSeleccionado;

  @override
  void initState() {
    super.initState();
    _filtro = widget.filtroInicial ?? '60';
    _future = _cargar();
  }

  Future<List<_VencimientoItem>> _cargar() async {
    final db = FirebaseFirestore.instance;
    final snapshots = await Future.wait([
      db
          .collection('TBL_COMPRAS_PROVEEDORES')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get(),
      db
          .collection('TBL_COMPRAS_RECEPCIONES')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get(),
    ]);
    final items = <_VencimientoItem>[];

    void agregar(
      String docKey,
      String documento,
      String titular,
      String origen,
      DocAdjunto doc,
    ) {
      // Los documentos cargados SIN fecha también entran: son justamente los
      // que hay que perseguir para que registren su "Vigente hasta".
      if (documentoRequiereVigencia(docKey) && doc.tieneDoc) {
        items.add(
          _VencimientoItem(
            documento: documento,
            titular: titular,
            origen: origen,
            doc: doc,
          ),
        );
      }
    }

    for (final raw in snapshots[0].docs) {
      final proveedor = ProveedorDoc.fromMap(raw.id, raw.data());
      for (final entry in proveedor.documentos.entries.where(
        (entry) => !kDocProveedorOcultos.contains(entry.key),
      )) {
        agregar(
          entry.key,
          kDocProveedorLabels[entry.key] ?? entry.key,
          proveedor.razonSocial,
          'Proveedor',
          entry.value,
        );
      }
    }
    for (final raw in snapshots[1].docs) {
      final recepcion = RecepcionDoc.fromMap(raw.id, raw.data());
      for (final producto in recepcion.productos) {
        for (final entry in producto.documentos.entries) {
          agregar(
            entry.key,
            kDocRecepcionLabels[entry.key] ?? entry.key,
            '${producto.nombre} · ${recepcion.razonSocial}',
            'Recepción',
            entry.value,
          );
        }
      }
    }
    items.sort((a, b) {
      final fa = a.fecha, fb = b.fecha;
      if (fa == null && fb == null) return 0;
      if (fa == null) return 1; // sin fecha al final
      if (fb == null) return -1;
      return fa.compareTo(fb);
    });
    return items;
  }

  Color _color(int dias) {
    if (dias < 0) return kComprasRed;
    if (dias <= 30) return const Color(0xFFB45309);
    return kComprasGreen;
  }

  String _estado(int dias) {
    if (dias < 0) return 'Vencido hace ${dias.abs()} día(s)';
    if (dias == 0) return 'Vence hoy';
    return 'Faltan $dias día(s)';
  }

  List<_VencimientoItem> _visibles(List<_VencimientoItem> items, DateTime hoy) {
    // Un día elegido en el calendario manda sobre el filtro por rango.
    final dia = _diaSeleccionado;
    if (dia != null) {
      return items.where((item) {
        final f = item.fecha;
        if (f == null) return false;
        return f.year == dia.year && f.month == dia.month && f.day == dia.day;
      }).toList();
    }
    if (_filtro == 'sin_fecha') {
      return items.where((item) => item.sinFecha).toList();
    }
    return items.where((item) {
      if (item.sinFecha) return _filtro == 'todos';
      final dias = item.diasDesde(hoy);
      if (_filtro == 'vencidos') return dias < 0;
      if (_filtro == '30') return dias >= 0 && dias <= 30;
      if (_filtro == '60') return dias >= 0 && dias <= 60;
      return true;
    }).toList();
  }

  /// Tarjeta de indicador. Tocarla aplica el filtro correspondiente.
  Widget _metric(String value, String label, Color color, {String? filtro}) {
    final activo =
        filtro != null && _filtro == filtro && _diaSeleccionado == null;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: filtro == null
            ? null
            : () => setState(() {
                _filtro = filtro;
                _diaSeleccionado = null;
              }),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(activo ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withOpacity(activo ? 0.9 : 0.25),
              width: activo ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filtros() {
    const labels = {
      'vencidos': 'Vencidos',
      '30': '30 días',
      '60': '60 días',
      'sin_fecha': 'Sin fecha',
      'todos': 'Todos',
    };
    final verCalendario =
        _verCalendario ?? (MediaQuery.of(context).size.width >= 800);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...labels.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(right: 7),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: _diaSeleccionado == null && _filtro == entry.key,
                onSelected: (_) => setState(() {
                  _filtro = entry.key;
                  _diaSeleccionado = null;
                }),
                selectedColor: kComprasPrimary.withOpacity(0.14),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 7),
            child: FilterChip(
              avatar: Icon(
                Icons.calendar_month,
                size: 16,
                color: verCalendario ? kComprasPrimary : Colors.black45,
              ),
              label: const Text('Calendario'),
              selected: verCalendario,
              onSelected: (v) => setState(() => _verCalendario = v),
              selectedColor: kComprasPrimary.withOpacity(0.14),
            ),
          ),
          if (_diaSeleccionado != null)
            InputChip(
              label: Text(
                'Día: ${DateFormat('dd/MM/yyyy').format(_diaSeleccionado!)}',
              ),
              selected: true,
              selectedColor: kComprasPrimary.withOpacity(0.14),
              onDeleted: () => setState(() => _diaSeleccionado = null),
            ),
        ],
      ),
    );
  }

  Widget _mobileList(List<_VencimientoItem> items, DateTime hoy) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final dias = item.sinFecha ? null : item.diasDesde(hoy);
        final color = dias == null ? const Color(0xFF64748B) : _color(dias);
        final estadoTxt = dias == null ? 'Sin fecha registrada' : _estado(dias);
        final fechaTxt = item.fecha == null
            ? 'Sin fecha'
            : DateFormat('dd/MM/yyyy').format(item.fecha!);
        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withOpacity(0.3)),
          ),
          child: ListTile(
            leading: Icon(Icons.description_outlined, color: color),
            title: Text(
              item.documento,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              '${item.titular}\n$fechaTxt · $estadoTxt',
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            isThreeLine: true,
            trailing: IconButton(
              onPressed: () => _abrirUrl(context, item.doc.url),
              icon: const Icon(Icons.open_in_new, size: 18),
              tooltip: 'Ver documento',
            ),
          ),
        );
      },
    );
  }

  Widget _webTable(List<_VencimientoItem> items, DateTime hoy) {
    return Card(
      margin: const EdgeInsets.only(top: 12, bottom: 24),
      elevation: 0,
      // Scroll vertical (la tabla puede superar la altura disponible) +
      // horizontal (columnas anchas). Sin el vertical, en pantallas anchas
      // las filas de abajo quedaban inalcanzables.
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Documento')),
              DataColumn(label: Text('Proveedor / producto')),
              DataColumn(label: Text('Origen')),
              DataColumn(label: Text('Vigente hasta')),
              DataColumn(label: Text('Estado')),
              DataColumn(label: Text('Abrir')),
            ],
            rows: items.map((item) {
              final dias = item.sinFecha ? null : item.diasDesde(hoy);
              final color = dias == null
                  ? const Color(0xFF64748B)
                  : _color(dias);
              final estadoTxt = dias == null
                  ? 'Sin fecha registrada'
                  : _estado(dias);
              return DataRow(
                cells: [
                  DataCell(Text(item.documento)),
                  DataCell(SizedBox(width: 320, child: Text(item.titular))),
                  DataCell(Text(item.origen)),
                  DataCell(
                    Text(
                      item.fecha == null
                          ? '—'
                          : DateFormat('dd/MM/yyyy').format(item.fecha!),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: color.withOpacity(0.35)),
                      ),
                      child: Text(
                        estadoTxt,
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 11.5,
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    IconButton(
                      onPressed: () => _abrirUrl(context, item.doc.url),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      tooltip: 'Ver documento',
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text(
          'Vigencias documentales',
          style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w700),
        ),
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => setState(() => _future = _cargar()),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: FutureBuilder<List<_VencimientoItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'No se pudieron cargar las vigencias: ${snapshot.error}',
                style: const TextStyle(fontFamily: _kFont, color: kComprasRed),
              ),
            );
          }
          final todos = snapshot.data ?? const <_VencimientoItem>[];
          final visibles = _visibles(todos, hoy);
          final vencidos = todos
              .where((item) => !item.sinFecha && item.diasDesde(hoy) < 0)
              .length;
          final proximos30 = todos.where((item) {
            if (item.sinFecha) return false;
            final dias = item.diasDesde(hoy);
            return dias >= 0 && dias <= 30;
          }).length;
          final sinFecha = todos.where((item) => item.sinFecha).length;
          // Conteo por día para pintar el calendario.
          final conteos = <DateTime, int>{};
          for (final item in todos) {
            final f = item.fecha;
            if (f == null) continue;
            final dia = DateTime(f.year, f.month, f.day);
            conteos[dia] = (conteos[dia] ?? 0) + 1;
          }
          final ancho = MediaQuery.of(context).size.width;
          final verCalendario = _verCalendario ?? (ancho >= 800);
          // En pantallas anchas el calendario va al lado de la lista para no
          // desperdiciar el espacio lateral ni empujar la tabla hacia abajo.
          final calendarioLateral = verCalendario && ancho >= 1100;

          final calendario = !verCalendario
              ? null
              : _CalendarioVencimientos(
                  mes: _mesVisible,
                  conteos: conteos,
                  hoy: hoy,
                  seleccionado: _diaSeleccionado,
                  onMesAnterior: () => setState(
                    () => _mesVisible = DateTime(
                      _mesVisible.year,
                      _mesVisible.month - 1,
                    ),
                  ),
                  onMesSiguiente: () => setState(
                    () => _mesVisible = DateTime(
                      _mesVisible.year,
                      _mesVisible.month + 1,
                    ),
                  ),
                  onDia: (dia) => setState(() {
                    _diaSeleccionado = _diaSeleccionado == dia ? null : dia;
                  }),
                );

          final lista = visibles.isEmpty
              ? const Center(
                  child: Text(
                    'No hay documentos para este filtro.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: _kFont, color: Colors.black45),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 800
                      ? _webTable(visibles, hoy)
                      : _mobileList(visibles, hoy),
                );

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _metric(
                      '$vencidos',
                      'Vencidos',
                      kComprasRed,
                      filtro: 'vencidos',
                    ),
                    const SizedBox(width: 8),
                    _metric(
                      '$proximos30',
                      'Próximos 30 días',
                      const Color(0xFFB45309),
                      filtro: '30',
                    ),
                    const SizedBox(width: 8),
                    _metric(
                      '$sinFecha',
                      'Sin fecha',
                      const Color(0xFF64748B),
                      filtro: 'sin_fecha',
                    ),
                    const SizedBox(width: 8),
                    _metric(
                      '${todos.length}',
                      'Todos',
                      kComprasPrimary,
                      filtro: 'todos',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _filtros(),
                const SizedBox(height: 10),
                Expanded(
                  child: calendarioLateral
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: lista),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 440,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 24,
                                ),
                                child: calendario!,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (calendario != null) calendario,
                            Expanded(child: lista),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Calendario mensual de vigencias: marca los días con documentos por vencer
/// (rojo = vencido, ámbar = dentro de 30 días, verde = posterior) y al tocar
/// un día filtra la lista a esa fecha exacta. Sin paquetes externos.
class _CalendarioVencimientos extends StatelessWidget {
  final DateTime mes;
  final Map<DateTime, int> conteos;
  final DateTime hoy;
  final DateTime? seleccionado;
  final VoidCallback onMesAnterior;
  final VoidCallback onMesSiguiente;
  final ValueChanged<DateTime> onDia;

  const _CalendarioVencimientos({
    required this.mes,
    required this.conteos,
    required this.hoy,
    required this.seleccionado,
    required this.onMesAnterior,
    required this.onMesSiguiente,
    required this.onDia,
  });

  Color _colorDia(DateTime dia) {
    final hoy0 = DateTime(hoy.year, hoy.month, hoy.day);
    final dias = dia.difference(hoy0).inDays;
    if (dias < 0) return kComprasRed;
    if (dias <= 30) return const Color(0xFFB45309);
    return kComprasGreen;
  }

  Widget _celda(int dia) {
    final fecha = DateTime(mes.year, mes.month, dia);
    final count = conteos[fecha] ?? 0;
    final esHoy =
        fecha.year == hoy.year &&
        fecha.month == hoy.month &&
        fecha.day == hoy.day;
    final esSeleccionado = seleccionado == fecha;
    final color = _colorDia(fecha);

    Widget contenido = Container(
      height: 42,
      decoration: BoxDecoration(
        color: esSeleccionado
            ? color.withValues(alpha: 0.18)
            : (count > 0 ? color.withValues(alpha: 0.07) : null),
        borderRadius: BorderRadius.circular(8),
        border: esSeleccionado
            ? Border.all(color: color, width: 1.6)
            : (esHoy ? Border.all(color: kComprasPrimary, width: 1.2) : null),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$dia',
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              fontWeight: count > 0 || esHoy
                  ? FontWeight.w800
                  : FontWeight.w500,
              color: count > 0 ? color : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );

    if (count > 0) {
      contenido = Tooltip(
        message:
            '$count documento(s) vencen el ${DateFormat('dd/MM/yyyy').format(fecha)}',
        child: contenido,
      );
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: count > 0 ? () => onDia(fecha) : null,
          child: contenido,
        ),
      ),
    );
  }

  Widget _leyenda(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(
          fontFamily: _kFont,
          fontSize: 10,
          color: Colors.black54,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final diasEnMes = DateTime(mes.year, mes.month + 1, 0).day;
    final offset = DateTime(mes.year, mes.month, 1).weekday - 1; // lunes = 0
    final filas = ((offset + diasEnMes) / 7).ceil();
    var titulo = DateFormat('MMMM yyyy', 'es').format(mes);
    titulo = titulo[0].toUpperCase() + titulo.substring(1);

    var diaActual = 1;
    final filasWidgets = <Widget>[];
    for (var f = 0; f < filas; f++) {
      final celdas = <Widget>[];
      for (var c = 0; c < 7; c++) {
        final idx = f * 7 + c;
        if (idx < offset || diaActual > diasEnMes) {
          celdas.add(const Expanded(child: SizedBox(height: 42)));
        } else {
          celdas.add(_celda(diaActual));
          diaActual++;
        }
      }
      filasWidgets.add(Row(children: celdas));
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: onMesAnterior,
                      icon: const Icon(Icons.chevron_left, size: 20),
                      tooltip: 'Mes anterior',
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      child: Text(
                        titulo,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onMesSiguiente,
                      icon: const Icon(Icons.chevron_right, size: 20),
                      tooltip: 'Mes siguiente',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                Row(
                  children: ['L', 'M', 'X', 'J', 'V', 'S', 'D']
                      .map(
                        (d) => Expanded(
                          child: Text(
                            d,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.black45,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 4),
                ...filasWidgets,
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    _leyenda(kComprasRed, 'Vencidos'),
                    _leyenda(const Color(0xFFB45309), 'Próximos 30 días'),
                    _leyenda(kComprasGreen, 'Posteriores'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final Color color;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ModuleCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SCANNER SHEET — escáner de documentos con cámara → PDF
// ══════════════════════════════════════════════════════════════════════════════

class _ScannerSheet extends StatefulWidget {
  final String empresaId;
  final String carpeta;
  final String nombreSugerido;
  final ComprasService svc;

  /// Usuario que está subiendo/reemplazando el documento. Se estampa en
  /// `subidoPor` de cada DocAdjunto devuelto para dejar trazabilidad de quién
  /// cargó (o reemplazó) cada archivo en Compras.
  final String userId;

  const _ScannerSheet({
    required this.empresaId,
    required this.carpeta,
    required this.nombreSugerido,
    required this.svc,
    this.userId = '',
  });

  @override
  State<_ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<_ScannerSheet> {
  final List<Uint8List> _imagenes = [];
  bool _subiendo = false;
  bool _escaneandoDocumento = false;
  final _picker = ImagePicker();
  bool _isDragging = false;
  StreamSubscription<bool>? _wDragSub;
  StreamSubscription<DroppedFile>? _wFileSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WebDragDrop.instance.enable();
      _wDragSub = WebDragDrop.instance.isDragging.listen((v) {
        if (mounted) setState(() => _isDragging = v);
      });
      _wFileSub = WebDragDrop.instance.droppedFile.listen(_onWebFileDrop);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) WebDragDrop.instance.disable();
    _wDragSub?.cancel();
    _wFileSub?.cancel();
    super.dispose();
  }

  Future<void> _tomarFoto() async {
    final img = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (img != null) {
      final bytes = await img.readAsBytes();
      setState(() => _imagenes.add(bytes));
    }
  }

  Future<void> _escanearDocumento() async {
    setState(() => _escaneandoDocumento = true);
    try {
      final pdfBytes = await document_scanner.scanDocumentPdf();
      if (pdfBytes == null || !mounted) return;

      setState(() => _subiendo = true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final doc = await widget.svc.subirBytes(
        bytes: pdfBytes,
        empresaId: widget.empresaId,
        carpeta: widget.carpeta,
        nombre: '${widget.nombreSugerido}_escaneado_$ts.pdf',
        contentType: 'application/pdf',
      );
      _popConDoc(doc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo completar el escaneo. Puedes usar Cámara rápida. Error: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _escaneandoDocumento = false;
          _subiendo = false;
        });
      }
    }
  }

  Future<void> _desdeGaleria() async {
    final imgs = await _picker.pickMultiImage(imageQuality: 80);
    for (final img in imgs) {
      final bytes = await img.readAsBytes();
      setState(() => _imagenes.add(bytes));
    }
  }

  /// Cierra el escáner devolviendo el documento, estampando `subidoPor` con el
  /// usuario que lo cargó/reemplazó (cuando se conoce).
  void _popConDoc(DocAdjunto doc) {
    if (!mounted) return;
    final uid = widget.userId.trim();
    Navigator.pop(context, uid.isEmpty ? doc : doc.copyWith(subidoPor: uid));
  }

  Future<void> _desdeArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    final nombre = file.name;
    final contentType = nombre.toLowerCase().endsWith('.pdf')
        ? 'application/pdf'
        : 'image/jpeg';
    setState(() => _subiendo = true);
    try {
      final doc = await widget.svc.subirBytes(
        bytes: file.bytes!,
        empresaId: widget.empresaId,
        carpeta: widget.carpeta,
        nombre: nombre,
        contentType: contentType,
      );
      _popConDoc(doc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al subir archivo: $e')));
      }
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<Uint8List> _imagenesToPdf() async {
    final doc = pw.Document();
    for (final imgBytes in _imagenes) {
      final pdfImg = pw.MemoryImage(imgBytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (ctx) =>
              pw.Center(child: pw.Image(pdfImg, fit: pw.BoxFit.contain)),
        ),
      );
    }
    return doc.save();
  }

  Future<void> _convertirYSubir() async {
    if (_imagenes.isEmpty) return;
    setState(() => _subiendo = true);
    try {
      final pdfBytes = await _imagenesToPdf();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final nombre = '${widget.nombreSugerido}_$ts.pdf';
      final doc = await widget.svc.subirBytes(
        bytes: pdfBytes,
        empresaId: widget.empresaId,
        carpeta: widget.carpeta,
        nombre: nombre,
        contentType: 'application/pdf',
      );
      _popConDoc(doc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al convertir PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  /// Maneja el drop de archivos desde el DropTarget nativo del navegador.
  Future<void> _handleScannerWebDrop(DropDoneDetails details) async {
    if (!mounted || details.files.isEmpty) return;
    if (mounted) setState(() => _isDragging = false);
    for (final xFile in details.files) {
      final name = xFile.name;
      final ext = name.toLowerCase().split('.').last;
      if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Archivo ignorado (${xFile.name}): solo PDF/JPG/PNG',
                style: const TextStyle(fontFamily: _kFont),
              ),
            ),
          );
        }
        continue;
      }
      final bytes = await xFile.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Archivo ignorado: supera el límite de 10 MB',
                style: TextStyle(fontFamily: _kFont),
              ),
            ),
          );
        }
        continue;
      }
      if (mounted) setState(() => _imagenes.add(bytes));
    }
  }

  // Zona drag-and-drop visible en web cuando no hay imágenes
  Widget _buildWebDropZoneArea(ScrollController scrollCtrl) {
    // Zona de arrastre + botón separado para abrir selector de archivo.
    // El DropzoneView (HTML) captura eventos HTML5 drag; el botón queda fuera
    // de esa área para que Flutter lo reciba correctamente en CanvasKit.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        children: [
          // Zona de arrastre
          Expanded(
            child: DropTarget(
              onDragEntered: (_) {
                if (mounted) setState(() => _isDragging = true);
              },
              onDragExited: (_) {
                if (mounted) setState(() => _isDragging = false);
              },
              onDragDone: _handleScannerWebDrop,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _isDragging
                      ? kComprasPrimary.withOpacity(0.07)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isDragging ? kComprasPrimary : Colors.grey.shade300,
                    width: _isDragging ? 2 : 1.5,
                  ),
                ),
                child: _subiendo
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            color: kComprasPrimary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Convirtiendo y subiendo como PDF…',
                            style: TextStyle(
                              fontFamily: _kFont,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 64,
                            color: _isDragging
                                ? kComprasPrimary
                                : Colors.grey.shade300,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _isDragging
                                ? '¡Suelta el archivo aquí!'
                                : 'Arrastra el archivo aquí',
                            style: TextStyle(
                              fontFamily: _kFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _isDragging
                                  ? kComprasPrimary
                                  : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'PDF · JPG · PNG — Se guarda como PDF',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          // Botón separado para abrir selector de archivo
          if (!_subiendo) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _desdeArchivo,
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text(
                  'o seleccionar archivo (PDF/img)',
                  style: TextStyle(fontFamily: _kFont),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kComprasPrimary,
                  side: const BorderSide(color: kComprasPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  // Recibe archivo arrastrado vía dart:html y lo procesa
  Future<void> _onWebFileDrop(DroppedFile file) async {
    if (!mounted) return;
    final name = file.name;
    final ext = name.toLowerCase().split('.').last;
    if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Solo se permiten PDF, JPG o PNG',
              style: TextStyle(fontFamily: _kFont),
            ),
          ),
        );
      }
      return;
    }
    final bytes = file.bytes;
    if (ext == 'pdf') {
      // PDF: subir directamente
      setState(() => _subiendo = true);
      try {
        final doc = await widget.svc.subirBytes(
          bytes: bytes,
          empresaId: widget.empresaId,
          carpeta: widget.carpeta,
          nombre: name,
          contentType: 'application/pdf',
        );
        _popConDoc(doc);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error al subir: $e')));
        }
      } finally {
        if (mounted) setState(() => _subiendo = false);
      }
    } else {
      // Imagen: agregar a la lista y convertir a PDF
      setState(() => _imagenes.add(bytes));
      await _convertirYSubir();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.document_scanner, color: kComprasPrimary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Adjuntar Documento',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Thumbnails / Drag zone
          Expanded(
            child: _imagenes.isEmpty
                ? (kIsWeb
                      ? _buildWebDropZoneArea(scrollCtrl)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt_outlined,
                              size: 56,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Sin imágenes capturadas',
                              style: TextStyle(
                                fontFamily: _kFont,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Usa la cámara o selecciona un archivo',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ))
                : (_subiendo && kIsWeb
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                              color: kComprasPrimary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Convirtiendo y subiendo como PDF…',
                              style: TextStyle(
                                fontFamily: _kFont,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        )
                      : GridView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                          itemCount: _imagenes.length,
                          itemBuilder: (ctx, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(_imagenes[i], fit: BoxFit.cover),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _imagenes.removeAt(i)),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(3),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 6,
                                  left: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Pág. ${i + 1}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
          ),
          // Botones
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 6,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: kIsWeb
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _subiendo ? null : _desdeArchivo,
                          icon: const Icon(Icons.upload_file, size: 18),
                          label: const Text(
                            'Seleccionar archivo (PDF/img)',
                            style: TextStyle(fontFamily: _kFont),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kComprasPrimary,
                            side: const BorderSide(color: kComprasPrimary),
                          ),
                        ),
                      ),
                      if (_imagenes.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: (_subiendo || _imagenes.isEmpty)
                                ? null
                                : _convertirYSubir,
                            icon: _subiendo
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.picture_as_pdf, size: 18),
                            label: Text(
                              _subiendo
                                  ? 'Subiendo…'
                                  : 'PDF (${_imagenes.length} pág.)',
                              style: const TextStyle(fontFamily: _kFont),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: kComprasPrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                : Column(
                    children: [
                      if (document_scanner.documentScannerAvailable) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: (_subiendo || _escaneandoDocumento)
                                ? null
                                : _escanearDocumento,
                            icon: _escaneandoDocumento
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.document_scanner, size: 19),
                            label: Text(
                              _escaneandoDocumento
                                  ? 'Abriendo escáner...'
                                  : 'Escanear documento',
                              style: const TextStyle(fontFamily: _kFont),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: kComprasPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Detecta bordes, recorta, mejora la imagen y permite varias páginas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_subiendo || _escaneandoDocumento)
                                  ? null
                                  : _tomarFoto,
                              icon: const Icon(Icons.camera_alt, size: 18),
                              label: const Text(
                                'Cámara rápida',
                                style: TextStyle(fontFamily: _kFont),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kComprasPrimary,
                                side: const BorderSide(color: kComprasPrimary),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_subiendo || _escaneandoDocumento)
                                  ? null
                                  : _desdeGaleria,
                              icon: const Icon(Icons.photo_library, size: 18),
                              label: const Text(
                                'Galería',
                                style: TextStyle(fontFamily: _kFont),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kComprasPrimary,
                                side: const BorderSide(color: kComprasPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_subiendo || _escaneandoDocumento)
                                  ? null
                                  : _desdeArchivo,
                              icon: const Icon(Icons.attach_file, size: 18),
                              label: const Text(
                                'Archivo (PDF/img)',
                                style: TextStyle(fontFamily: _kFont),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (_subiendo || _imagenes.isEmpty)
                                  ? null
                                  : _convertirYSubir,
                              icon: _subiendo
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.picture_as_pdf, size: 18),
                              label: Text(
                                _subiendo
                                    ? 'Subiendo...'
                                    : 'PDF (${_imagenes.length} pág.)',
                                style: const TextStyle(fontFamily: _kFont),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: kComprasPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

Future<DocAdjunto?> _mostrarEscaneador(
  BuildContext context, {
  required String empresaId,
  required String carpeta,
  required String nombreSugerido,
  required ComprasService svc,
  String userId = '',
}) async {
  return _showComprasAdaptiveSheet<DocAdjunto>(
    context: context,
    title: 'Adjuntar documento',
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ScannerSheet(
      empresaId: empresaId,
      carpeta: carpeta,
      nombreSugerido: nombreSugerido,
      svc: svc,
      userId: userId,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// HISTORIAL DOCUMENTAL DE PRODUCTOS CÁRNICOS (últimas 4 semanas)
// Los productos de proteína requieren documentación semanal (guías de transporte,
// sacrificio y certificados de calidad) por rotación de lotes. Esta vista muestra
// las recepciones del producto en las últimas 4 semanas con sus documentos.
// ══════════════════════════════════════════════════════════════════════════════

/// True si la categoría corresponde a productos cárnicos (proteína).
bool _esCarnico(String categoria) {
  final c = categoria
      .trim()
      .toLowerCase()
      .replaceAll('í', 'i')
      .replaceAll('á', 'a');
  return c.contains('protein') || c.contains('carnic') || c.contains('carne');
}

/// Documentos relevantes de la recepción de un cárnico, en orden de interés.
const List<String> kDocsCarnico = [
  'guiaTransporte',
  'guiaSacrificio',
  'certCalidad',
  'fichaTecnica',
];

Future<void> _mostrarHistorialCarnico(
  BuildContext context, {
  required String empresaId,
  required ComprasService svc,
  required ProductoDoc producto,
}) {
  return _showComprasAdaptiveSheet<void>(
    context: context,
    title: 'Historial documental del producto',
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _HistorialCarnicoSheet(
      empresaId: empresaId,
      svc: svc,
      producto: producto,
    ),
  );
}

class _HistorialCarnicoSheet extends StatelessWidget {
  final String empresaId;
  final ComprasService svc;
  final ProductoDoc producto;

  /// Número de semanas de historial a conservar/mostrar.
  static const int semanas = 4;

  const _HistorialCarnicoSheet({
    required this.empresaId,
    required this.svc,
    required this.producto,
  });

  @override
  Widget build(BuildContext context) {
    final desde = DateTime.now().subtract(const Duration(days: 7 * semanas));
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.history, color: kComprasPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          producto.nombre,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const Text(
                          'Historial documental · últimas 4 semanas',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: StreamBuilder<List<RecepcionDoc>>(
                stream: svc.streamRecepcionesByProducto(empresaId, producto.id),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final recepciones =
                      (snap.data ?? const <RecepcionDoc>[])
                          .where((r) => r.fecha.toDate().isAfter(desde))
                          .toList()
                        ..sort((a, b) => b.fecha.compareTo(a.fecha));

                  if (recepciones.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Sin recepciones de este producto en las últimas 4 semanas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: _kFont,
                            color: Colors.black45,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: recepciones.length,
                    itemBuilder: (_, i) => _semanaCard(context, recepciones[i]),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _semanaCard(BuildContext context, RecepcionDoc r) {
    final rp = r.productos.firstWhere(
      (p) => p.productoId == producto.id,
      orElse: () => const RecepcionProducto(),
    );
    final fecha = DateFormat('EEE d MMM, y', 'es').format(r.fecha.toDate());
    // Documentos a mostrar: los cárnicos conocidos + cualquier otro cargado.
    final keys = <String>[
      ...kDocsCarnico.where((k) => rp.documentos.containsKey(k)),
      ...rp.documentos.keys.where((k) => !kDocsCarnico.contains(k)),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: kComprasPrimary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fecha,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (r.razonSocial.isNotEmpty)
                  Flexible(
                    child: Text(
                      r.razonSocial,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
            ),
            if (rp.marca.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Marca: ${rp.marca}',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
            ],
            if (rp.lotes.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Lotes: ${rp.lotes.map((lote) => lote.numero).join(', ')}',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (keys.isEmpty)
              const Text(
                'Sin documentos en esta recepción.',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.black45,
                ),
              )
            else
              ...keys.map((k) => _docLinea(context, k, rp.documentos[k])),
          ],
        ),
      ),
    );
  }

  Widget _docLinea(BuildContext context, String key, DocAdjunto? doc) {
    final label = kDocRecepcionLabels[key] ?? key;
    final tiene = doc?.tieneDoc == true;
    Color color;
    IconData icon;
    if (doc?.aprobado == true) {
      color = kComprasGreen;
      icon = Icons.check_circle;
    } else if (doc?.rechazado == true) {
      color = kComprasRed;
      icon = Icons.cancel;
    } else if (tiene) {
      color = const Color(0xFFB45309);
      icon = Icons.schedule;
    } else {
      color = Colors.black38;
      icon = Icons.remove_circle_outline;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Colors.black87,
              ),
            ),
          ),
          if (tiene)
            IconButton(
              onPressed: () => _abrirUrl(context, doc!.url),
              icon: const Icon(Icons.open_in_new, size: 14, color: Colors.blue),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Ver documento',
            )
          else
            const Text(
              'Sin cargar',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 10,
                color: Colors.black45,
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DOC ATTACH BUTTON — botón reutilizable para adjuntar documentos
// ══════════════════════════════════════════════════════════════════════════════

/// Archivo en espera de ser combinado/subido (solo web).
class _PendingFile {
  final Uint8List bytes;
  final String name;
  const _PendingFile(this.bytes, this.name);
  bool get isPdf => name.toLowerCase().endsWith('.pdf');
}

class _DocAttachButton extends StatefulWidget {
  final String label;
  final DocAdjunto? doc;
  final bool required_;
  final bool uploading;
  final bool editable;
  final bool qualityRequired;
  final VoidCallback onAttach;
  final VoidCallback? onView;

  /// Mostrar selector de fecha de vencimiento.
  final bool showCalendar;
  final ValueChanged<DateTime?>? onDateChanged;

  /// Solo web: callback que recibe bytes + nombre y sube el archivo.
  /// El caller es responsable de actualizar su estado con el DocAdjunto resultante.
  final Future<void> Function(Uint8List bytes, String name)? onWebUpload;

  /// Carga una evidencia para un documento aprobado con requerimientos. No
  /// reemplaza el original: el servicio genera un PDF consolidado y devuelve
  /// el documento actualizado al caller.
  final Future<void> Function(Uint8List bytes, String name)?
  onRequirementUpload;

  /// Solo web: elimina el documento ya adjunto (limpia la referencia en el estado del padre).
  final VoidCallback? onDelete;

  /// Revierte una aprobación dada por error. Solo se muestra cuando el
  /// documento está aprobado y quien mira es Admin Documental; si es null el
  /// botón no aparece.
  final VoidCallback? onRevertir;

  const _DocAttachButton({
    required this.label,
    required this.doc,
    this.required_ = false,
    this.uploading = false,
    this.editable = true,
    this.qualityRequired = false,
    required this.onAttach,
    this.onView,
    this.showCalendar = false,
    this.onDateChanged,
    this.onWebUpload,
    this.onRequirementUpload,
    this.onDelete,
    this.onRevertir,
  });

  @override
  State<_DocAttachButton> createState() => _DocAttachButtonState();
}

class _DocAttachButtonState extends State<_DocAttachButton> {
  bool _isDragging = false;
  bool _webUploading = false;
  bool _requirementUploading = false;
  // Drag-and-drop web
  final _dropKey = GlobalKey();
  StreamSubscription<bool>? _wDragSub;
  StreamSubscription<DroppedFile>? _wFileSub;

  /// Archivos en espera de combinarse y subir (solo web).
  final List<_PendingFile> _pending = [];
  bool _combining = false;

  static const int _maxBytes = 10 * 1024 * 1024; // 10 MB

  @override
  void initState() {
    super.initState();
    if (kIsWeb && widget.editable) {
      WebDragDrop.instance.enable();
      _wDragSub = WebDragDrop.instance.isDragging.listen((v) {
        if (mounted) setState(() => _isDragging = v);
      });
      _wFileSub = WebDragDrop.instance.droppedFile.listen(_onWebFileDrop);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) WebDragDrop.instance.disable();
    _wDragSub?.cancel();
    _wFileSub?.cancel();
    super.dispose();
  }

  Future<void> _selectDate() async {
    if (!widget.editable) return;
    final now = DateTime.now();
    final initialDate = widget.doc?.fechaVencimiento?.toDate() ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(now) ? now : initialDate,
      firstDate: now.subtract(const Duration(days: 365 * 5)),
      lastDate: now.add(const Duration(days: 365 * 10)),
      helpText: 'Vigente hasta',
      cancelText: 'Cancelar',
      confirmText: 'Seleccionar',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: kComprasPrimary,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && widget.onDateChanged != null) {
      widget.onDateChanged!(picked);
    }
  }

  Widget _buildExpiryPicker() {
    final expiry = widget.doc?.fechaVencimiento?.toDate();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.onDateChanged == null ? null : _selectDate,
              icon: const Icon(Icons.event_available_outlined, size: 16),
              label: Text(
                expiry == null
                    ? 'Agregar “Vigente hasta”'
                    : 'Vigente hasta: ${DateFormat('dd/MM/yyyy').format(expiry)}',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: expiry != null
                    ? kComprasPrimary
                    : Colors.blueGrey.shade600,
                side: BorderSide(
                  color: expiry != null
                      ? kComprasPrimary.withOpacity(0.45)
                      : Colors.grey.shade300,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
          if (expiry != null && widget.onDateChanged != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => widget.onDateChanged!(null),
              icon: const Icon(Icons.close, size: 17),
              tooltip: 'Quitar fecha de vigencia',
              color: Colors.black45,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }

  /// Recibe archivo arrastrado; lo agrega a la cola de pendientes si el cursor
  /// cayó sobre este widget.
  void _onWebFileDrop(DroppedFile file) {
    if (!mounted ||
        !widget.editable ||
        _isUploading ||
        _combining ||
        widget.onWebUpload == null) {
      return;
    }
    // Verificar que el drop ocurrió dentro de los límites de este widget.
    // Si la zona drop no está visible (rb == null) rechazar el drop.
    final rb = _dropKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null) return;
    final topLeft = rb.localToGlobal(Offset.zero);
    final bounds = topLeft & rb.size;
    if (!bounds.contains(WebDragDrop.instance.lastDropPosition)) return;
    final name = file.name;
    final ext = name.toLowerCase().split('.').last;
    if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Solo se permiten PDF, JPG o PNG',
              style: TextStyle(fontFamily: _kFont),
            ),
          ),
        );
      }
      return;
    }
    if (file.bytes.length > _maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El archivo supera el límite de 10 MB',
              style: TextStyle(fontFamily: _kFont),
            ),
          ),
        );
      }
      return;
    }
    setState(() => _pending.add(_PendingFile(file.bytes, name)));
  }

  bool get _pendienteCalidad {
    final doc = widget.doc;
    if (doc == null || !doc.tieneDoc) return false;
    return doc.pendiente ||
        (widget.qualityRequired && !doc.aprobado && !doc.rechazado);
  }

  Color get _borderColor {
    if (widget.doc?.aprobadoConRequerimientos == true) {
      return const Color(0xFFD97706);
    }
    if (_pendienteCalidad) return Colors.orange;
    if (widget.doc?.aprobado == true) return kComprasGreen;
    if (widget.doc?.rechazado == true) return kComprasRed;
    if (widget.doc?.tieneDoc == true) return kComprasGreen;
    return Colors.grey.shade300;
  }

  Color get _iconColor {
    if (widget.doc?.aprobadoConRequerimientos == true) {
      return const Color(0xFFD97706);
    }
    if (_pendienteCalidad) return Colors.orange;
    if (widget.doc?.aprobado == true) return kComprasGreen;
    if (widget.doc?.rechazado == true) return kComprasRed;
    if (widget.doc?.tieneDoc == true) return kComprasGreen;
    return kComprasPrimary;
  }

  IconData get _icon {
    if (widget.doc?.aprobadoConRequerimientos == true) {
      return Icons.rule_folder_outlined;
    }
    if (_pendienteCalidad) return Icons.hourglass_empty;
    if (widget.doc?.aprobado == true) return Icons.check_circle;
    if (widget.doc?.rechazado == true) return Icons.cancel;
    if (widget.doc?.tieneDoc == true) return Icons.check_circle;
    return Icons.upload_file;
  }

  String get _estadoLabel {
    if (widget.doc?.aprobadoConRequerimientos == true) {
      return ' · Aprobado con requerimientos';
    }
    if (_pendienteCalidad) return ' · Pendiente revisión Calidad';
    if (widget.doc?.aprobado == true) return ' · Aprobado';
    if (widget.doc?.rechazado == true) return ' · Rechazado';
    return '';
  }

  bool get _isUploading =>
      widget.uploading || _webUploading || _requirementUploading;

  Future<void> _pickRequirementSupport() async {
    if (_requirementUploading || widget.onRequirementUpload == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    if (bytes.length > _maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El soporte supera el límite de 10 MB.'),
            backgroundColor: kComprasRed,
          ),
        );
      }
      return;
    }
    setState(() => _requirementUploading = true);
    try {
      await widget.onRequirementUpload!(bytes, file.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Soporte consolidado y enviado a revisión de Calidad.',
            ),
            backgroundColor: Color(0xFFD97706),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo cargar el soporte: $error'),
            backgroundColor: kComprasRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _requirementUploading = false);
    }
  }

  Widget _buildRequirementPanel() {
    final doc = widget.doc;
    if (doc?.aprobadoConRequerimientos != true) {
      return const SizedBox.shrink();
    }
    final deadline = doc!.requerimientoFechaLimite?.toDate();
    final hasSupport = doc.soportesRequerimiento.isNotEmpty;
    final needsAttachment = doc.requerimientoRequiereAdjunto;
    final canUpload =
        needsAttachment &&
        doc.requerimientoAbierto &&
        widget.onRequirementUpload != null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.rule_folder_outlined,
                size: 17,
                color: Color(0xFFB45309),
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Requerimiento de Calidad abierto',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          if (doc.requerimientoNota?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 5),
            Text(
              doc.requerimientoNota!.trim(),
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 11,
                height: 1.3,
                color: Color(0xFF78350F),
              ),
            ),
          ],
          const SizedBox(height: 5),
          Text(
            '${needsAttachment ? 'Requiere soporte adjunto' : 'No requiere adjunto'}'
            '${deadline == null ? '' : ' · Límite ${DateFormat('dd/MM/yyyy').format(deadline)}'}'
            '${hasSupport ? ' · ${doc.soportesRequerimiento.length} soporte(s) enviado(s)' : ''}',
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF92400E),
            ),
          ),
          if (canUpload) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _requirementUploading ? null : _pickRequirementSupport,
              icon: _requirementUploading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file, size: 15),
              label: Text(
                _requirementUploading
                    ? 'Consolidando soporte...'
                    : hasSupport
                    ? 'Adjuntar otro soporte'
                    : 'Adjuntar soporte solicitado',
                style: const TextStyle(fontFamily: _kFont, fontSize: 11),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB45309),
                side: const BorderSide(color: Color(0xFFF59E0B)),
                minimumSize: const Size(0, 34),
              ),
            ),
          ] else if (needsAttachment && !hasSupport) ...[
            const SizedBox(height: 6),
            const Text(
              'El responsable asignado debe adjuntar el soporte desde su gestión documental.',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 10,
                color: Color(0xFF92400E),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleWebFilePick() async {
    if (!widget.editable ||
        _isUploading ||
        _combining ||
        widget.onWebUpload == null) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final newFiles = <_PendingFile>[];
    for (final f in result.files) {
      if (f.bytes == null) continue;
      if (f.bytes!.length > _maxBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${f.name}: supera el límite de 10 MB',
                style: const TextStyle(fontFamily: _kFont),
              ),
            ),
          );
        }
        continue;
      }
      newFiles.add(_PendingFile(f.bytes!, f.name));
    }
    if (newFiles.isNotEmpty && mounted) {
      setState(() => _pending.addAll(newFiles));
    }
  }

  Future<void> _handleWebDrop(DropDoneDetails details) async {
    if (!mounted || details.files.isEmpty || widget.onWebUpload == null) return;
    setState(() => _isDragging = false);
    final xFile = details.files.first;
    final name = xFile.name;
    final ext = name.toLowerCase().split('.').last;
    if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Solo se permiten PDF, JPG o PNG',
              style: TextStyle(fontFamily: _kFont),
            ),
          ),
        );
      }
      return;
    }
    final bytes = await xFile.readAsBytes();
    await _processWebBytes(bytes, name);
  }

  Future<void> _processWebBytes(Uint8List bytes, String name) async {
    if (bytes.length > _maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El archivo supera el límite de 10 MB',
              style: TextStyle(fontFamily: _kFont),
            ),
          ),
        );
      }
      return;
    }
    setState(() => _webUploading = true);
    try {
      await widget.onWebUpload!(bytes, name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al subir: $e',
              style: const TextStyle(fontFamily: _kFont),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _webUploading = false);
    }
  }

  /// Combina todos los archivos pendientes en un único PDF y lo sube.
  Future<void> _combinarYSubir() async {
    if (_pending.isEmpty || widget.onWebUpload == null) return;
    setState(() => _combining = true);
    try {
      Uint8List finalBytes;
      String finalName;

      if (_pending.length == 1 && _pending.first.isPdf) {
        // Un único PDF: subir directo sin recodificar
        finalBytes = _pending.first.bytes;
        finalName = _pending.first.name;
      } else {
        // Combinar en un único PDF
        final pdfDoc = pw.Document();
        for (final pf in _pending) {
          if (pf.isPdf) {
            // Rasterizar cada página del PDF a imagen
            await for (final raster in Printing.raster(pf.bytes, dpi: 150)) {
              final imgBytes = await raster.toPng();
              final pwImg = pw.MemoryImage(imgBytes);
              // Reconstituir tamaño original en puntos (150 dpi → puntos a 72 dpi)
              final wPt = raster.width * 72.0 / 150.0;
              final hPt = raster.height * 72.0 / 150.0;
              pdfDoc.addPage(
                pw.Page(
                  pageFormat: PdfPageFormat(wPt, hPt),
                  margin: pw.EdgeInsets.zero,
                  build: (_) => pw.Image(pwImg, fit: pw.BoxFit.fill),
                ),
              );
            }
          } else {
            // Imagen: agregar como página A4
            final pwImg = pw.MemoryImage(pf.bytes);
            pdfDoc.addPage(
              pw.Page(
                pageFormat: PdfPageFormat.a4,
                margin: const pw.EdgeInsets.all(16),
                build: (_) =>
                    pw.Center(child: pw.Image(pwImg, fit: pw.BoxFit.contain)),
              ),
            );
          }
        }
        finalBytes = await pdfDoc.save();
        finalName = 'documento_combinado.pdf';
      }

      await widget.onWebUpload!(finalBytes, finalName);
      if (mounted) setState(() => _pending.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al combinar: $e',
              style: const TextStyle(fontFamily: _kFont),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _combining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tiene = widget.doc?.tieneDoc == true;

    if (kIsWeb) {
      return _buildWeb(tiene);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                softWrap: true,
              ),
            ),
            if (widget.required_)
              const Text(
                ' *',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    !widget.editable ||
                        widget.uploading ||
                        widget.doc?.aprobadoConRequerimientos == true
                    ? null
                    : widget.onAttach,
                icon: widget.uploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_icon, size: 16, color: _iconColor),
                label: Text(
                  widget.uploading
                      ? 'Subiendo...'
                      : tiene
                      ? '${widget.doc!.nombre ?? 'Adjunto'}$_estadoLabel'
                      : 'Adjuntar / Escanear',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: widget.uploading ? Colors.grey : _iconColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _borderColor),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
            if (tiene && widget.onView != null) ...[
              const SizedBox(width: 6),
              IconButton(
                onPressed: widget.onView,
                icon: const Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: Colors.blue,
                ),
                tooltip: 'Ver documento',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ],
        ),
        if (widget.showCalendar && tiene) _buildExpiryPicker(),
        if (widget.doc?.rechazado == true &&
            widget.doc?.observacionCalidad != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'Motivo: ${widget.doc!.observacionCalidad}',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 11,
                color: Colors.red.shade700,
              ),
            ),
          ),
        ],
        _buildRequirementPanel(),
        _buildRevertirAprobacion(),
      ],
    );
  }

  /// Acceso directo del Admin Documental para corregir una aprobación dada por
  /// error, sin tener que ir a la pestaña "Aprobados" de Calidad.
  Widget _buildRevertirAprobacion() {
    if (widget.onRevertir == null || widget.doc?.aprobado != true) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: widget.onRevertir,
          icon: const Icon(Icons.undo, size: 15),
          label: const Text(
            'Revertir aprobación',
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFB45309),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  // ── Web layout ──────────────────────────────────────────────────────────────

  Widget _buildWeb(bool tiene) {
    if (!widget.editable && !tiene) {
      return _buildWebLockedEmpty();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                softWrap: true,
              ),
            ),
            if (widget.required_)
              const Text(
                ' *',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Zona de contenido según estado
        if (_pending.isNotEmpty)
          _buildWebPendingList()
        else if (tiene)
          _buildWebFileRow()
        else
          _buildWebDropZone(),
        if (widget.showCalendar && tiene) ...[
          const SizedBox(height: 6),
          _buildExpiryPicker(),
        ],
        // Observación de calidad
        if (widget.doc?.rechazado == true &&
            widget.doc?.observacionCalidad != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'Motivo: ${widget.doc!.observacionCalidad}',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 11,
                color: Colors.red.shade700,
              ),
            ),
          ),
        ],
        _buildRequirementPanel(),
        _buildRevertirAprobacion(),
      ],
    );
  }

  Widget _buildWebLockedEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: Color(0xFF94A3B8)),
          SizedBox(width: 8),
          Text(
            'Sin documento · recepción cerrada',
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 11,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  /// Lista de archivos en espera de ser combinados y subidos.
  Widget _buildWebPendingList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Encabezado con contador y botón "Agregar más"
        Row(
          children: [
            Text(
              'Archivos a combinar (${_pending.length})',
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _combining ? null : _handleWebFilePick,
              icon: const Icon(Icons.add, size: 14),
              label: const Text(
                'Agregar más',
                style: TextStyle(fontFamily: _kFont, fontSize: 11),
              ),
              style: TextButton.styleFrom(
                foregroundColor: kComprasPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Lista de archivos pendientes
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: _pending.asMap().entries.map((e) {
              final idx = e.key;
              final pf = e.value;
              final ext = pf.name.split('.').last.toLowerCase();
              final isImg = ['jpg', 'jpeg', 'png'].contains(ext);
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                leading: Icon(
                  isImg ? Icons.image : Icons.picture_as_pdf,
                  size: 18,
                  color: isImg ? Colors.blue.shade600 : Colors.red.shade600,
                ),
                title: Text(
                  pf.name,
                  style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${(pf.bytes.length / 1024).toStringAsFixed(0)} KB',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: _combining
                      ? null
                      : () => setState(() => _pending.removeAt(idx)),
                  tooltip: 'Quitar',
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Botones de acción
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _combining
                    ? null
                    : () => setState(() => _pending.clear()),
                icon: const Icon(Icons.clear, size: 13),
                label: const Text(
                  'Cancelar',
                  style: TextStyle(fontFamily: _kFont, fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _combining ? null : _combinarYSubir,
                icon: _combining
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.merge_type, size: 14),
                label: Text(
                  _combining
                      ? 'Combinando...'
                      : _pending.length == 1
                      ? 'Subir archivo'
                      : 'Combinar y subir PDF',
                  style: const TextStyle(fontFamily: _kFont, fontSize: 11),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: kComprasPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWebDropZone() {
    // En web: zona drag-and-drop + botón separado para abrir selector
    // El DropzoneView (HTML) captura los eventos de arrastre del navegador.
    // El botón queda fuera del área del DropzoneView para que Flutter lo reciba.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Zona de arrastre
        SizedBox(
          key: _dropKey,
          height: 72,
          child: DropTarget(
            onDragEntered: (_) {
              if (mounted) setState(() => _isDragging = true);
            },
            onDragExited: (_) {
              if (mounted) setState(() => _isDragging = false);
            },
            onDragDone: _handleWebDrop,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              decoration: BoxDecoration(
                color: _isDragging
                    ? kComprasPrimary.withOpacity(0.07)
                    : (_isUploading
                          ? Colors.blue.shade50
                          : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isDragging ? kComprasPrimary : Colors.grey.shade300,
                  width: _isDragging ? 2 : 1,
                ),
              ),
              child: _isUploading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kComprasPrimary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Subiendo...',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 26,
                          color: _isDragging
                              ? kComprasPrimary
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isDragging
                                  ? '¡Suelta el archivo aquí!'
                                  : 'Arrastra el archivo aquí',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _isDragging
                                    ? kComprasPrimary
                                    : Colors.black54,
                              ),
                            ),
                            Text(
                              'PDF · JPG · PNG · Máx. 10 MB',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ),
        // Botón separado para abrir selector de archivo
        if (!_isUploading && widget.onWebUpload != null) ...[
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _handleWebFilePick,
            icon: Icon(
              Icons.folder_open,
              size: 13,
              color: Colors.grey.shade600,
            ),
            label: Text(
              'o seleccionar archivo',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWebFileRow() {
    final doc = widget.doc!;
    final nombre = doc.nombre ?? 'Adjunto';
    final ext = nombre.split('.').last.toLowerCase();
    final isImg = ['jpg', 'jpeg', 'png'].contains(ext);

    Color statusColor = kComprasGreen;
    String statusText = 'Adjunto';
    IconData statusIcon = Icons.check_circle;
    if (doc.aprobadoConRequerimientos) {
      statusColor = const Color(0xFFD97706);
      statusText = 'Aprobado con requerimientos';
      statusIcon = Icons.rule_folder_outlined;
    } else if (_pendienteCalidad) {
      statusColor = Colors.orange;
      statusText = 'Pendiente revisión Calidad';
      statusIcon = Icons.hourglass_empty;
    } else if (doc.rechazado == true) {
      statusColor = kComprasRed;
      statusText = 'Rechazado';
      statusIcon = Icons.cancel;
    } else if (doc.aprobado == true) {
      statusColor = kComprasGreen;
      statusText = 'Aprobado';
      statusIcon = Icons.verified;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            isImg ? Icons.image : Icons.picture_as_pdf,
            color: statusColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Icon(statusIcon, size: 11, color: statusColor),
                    const SizedBox(width: 3),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 10,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.onView != null)
            TextButton.icon(
              onPressed: widget.onView,
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text(
                'Ver',
                style: TextStyle(fontFamily: _kFont, fontSize: 11),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          if (widget.onWebUpload != null && !doc.aprobadoConRequerimientos)
            TextButton.icon(
              onPressed: _isUploading ? null : _handleWebFilePick,
              icon: const Icon(Icons.add_circle_outline, size: 14),
              label: const Text(
                'Agregar',
                style: TextStyle(fontFamily: _kFont, fontSize: 11),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          if (widget.onDelete != null && !doc.aprobadoConRequerimientos)
            IconButton(
              onPressed: _isUploading ? null : widget.onDelete,
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red.shade400,
              ),
              tooltip: 'Eliminar documento',
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}

void _abrirUrl(BuildContext context, String? url) async {
  if (url == null || url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el documento')),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PROVEEDORES SCREEN — listado
// ══════════════════════════════════════════════════════════════════════════════

class _DocumentosAsociadosSheet extends StatefulWidget {
  final String titulo;
  final String marcaId;
  final String empresaId;
  final String userId;
  final ComprasService svc;
  final Map<String, DocAdjunto> documentos;
  final Future<void> Function(Map<String, DocAdjunto>) onSave;
  final bool requiredForCompletion;

  const _DocumentosAsociadosSheet({
    required this.titulo,
    required this.marcaId,
    required this.empresaId,
    required this.userId,
    required this.svc,
    required this.documentos,
    required this.onSave,
    this.requiredForCompletion = false,
  });

  @override
  State<_DocumentosAsociadosSheet> createState() =>
      _DocumentosAsociadosSheetState();
}

class _DocumentosAsociadosSheetState extends State<_DocumentosAsociadosSheet> {
  late Map<String, DocAdjunto> _documentos;
  late Future<List<DocumentoMarcaVinculado>> _documentosVinculados;
  final Set<String> _subiendo = {};

  @override
  void initState() {
    super.initState();
    _documentos = Map<String, DocAdjunto>.from(widget.documentos);
    _documentosVinculados = widget.svc.getDocumentosVinculadosMarca(
      widget.empresaId,
      widget.marcaId,
      marcaNombre: widget.titulo,
    );
  }

  Future<void> _persistir() => widget.onSave(_documentos);

  Future<void> _actualizarFecha(String key, DateTime? date) async {
    final actual = _documentos[key] ?? const DocAdjunto();
    if (date == null && actual.tieneDoc && documentoRequiereVigencia(key)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No puedes quitar la vigencia mientras el documento esté cargado.',
          ),
          backgroundColor: kComprasRed,
        ),
      );
      return;
    }
    setState(() {
      _documentos = {
        ..._documentos,
        key: actual.copyWith(
          fechaVencimiento: date == null ? null : Timestamp.fromDate(date),
          clearFechaVencimiento: date == null,
        ),
      };
    });
    await _persistir();
  }

  Future<void> _subirBytes(String key, Uint8List bytes, String nombre) async {
    setState(() => _subiendo.add(key));
    try {
      final ext = nombre.toLowerCase().split('.').last;
      final contentType = ext == 'pdf' ? 'application/pdf' : 'image/$ext';
      final subido = await widget.svc.subirBytes(
        bytes: bytes,
        empresaId: widget.empresaId,
        carpeta: 'documentos_asociados',
        nombre: nombre,
        contentType: contentType,
        pendienteCalidad: true,
      );
      var doc = prepararDocumentoPendienteCalidad(
        subido,
        subidoPor: widget.userId,
      );
      setState(() => _documentos = {..._documentos, key: doc});
      if (documentoRequiereVigencia(key) && mounted) {
        final vigencia = await _solicitarVigenciaDespuesDeCargar(
          context,
          docKey: key,
          labels: kDocumentosAsociadosLabels,
        );
        if (vigencia != null) {
          doc = doc.copyWith(fechaVencimiento: Timestamp.fromDate(vigencia));
          if (mounted) {
            setState(() => _documentos = {..._documentos, key: doc});
          }
        }
      }
      await _persistir();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !documentoRequiereVigencia(key)
                  ? '${kDocumentosAsociadosLabels[key]} cargado y enviado a revisión de Calidad.'
                  : doc.fechaVencimiento != null
                  ? '${kDocumentosAsociadosLabels[key]} cargado con su vigencia.'
                  : '${kDocumentosAsociadosLabels[key]} cargado; falta registrar su vigencia.',
            ),
            backgroundColor:
                doc.fechaVencimiento != null || !documentoRequiereVigencia(key)
                ? kComprasGreen
                : kComprasRed,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No fue posible cargar el documento: $error'),
            backgroundColor: kComprasRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendo.remove(key));
    }
  }

  Future<void> _seleccionarArchivo(String key) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    await _subirBytes(key, file.bytes!, file.name);
  }

  Future<void> _eliminar(String key) async {
    setState(() => _documentos = {..._documentos, key: const DocAdjunto()});
    await _persistir();
  }

  String _origenDocumentoVinculado(String origen) => switch (origen) {
    'producto_marca_proveedor' => 'Producto · marca · proveedor',
    'producto_por_marca' => 'Producto · marca (modelo anterior)',
    'producto_general' => 'Producto con una sola marca',
    'producto_asociado' => 'Documento asociado al producto',
    _ => 'Modelo anterior',
  };

  Widget _documentosVinculadosSection() {
    return FutureBuilder<List<DocumentoMarcaVinculado>>(
      future: _documentosVinculados,
      builder: (context, snapshot) {
        final identidadesActuales = _documentos.values
            .where((doc) => doc.tieneDoc)
            .map((doc) {
              final path = doc.path?.trim() ?? '';
              return path.isNotEmpty ? path : (doc.url?.trim() ?? '');
            })
            .where((identidad) => identidad.isNotEmpty)
            .toSet();
        final vinculados = (snapshot.data ?? const <DocumentoMarcaVinculado>[])
            .where(
              (vinculado) =>
                  !identidadesActuales.contains(vinculado.identidadArchivo),
            )
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 32),
            Row(
              children: [
                const Icon(
                  Icons.account_tree_outlined,
                  size: 19,
                  color: Color(0xFF283593),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Documentos vinculados desde productos',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF283593),
                    ),
                  ),
                ),
                if (snapshot.hasData)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EAF6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${vinculados.length}',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF283593),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Aquí aparecen las fichas y soportes que se cargaron desde el producto con el modelo anterior. Se conservan asociados a su producto, marca y proveedor; no se convierten en un documento principal ni se duplican.',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 11.5,
                height: 1.35,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot.hasError)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDBA74)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'No fue posible consultar los documentos del modelo anterior.',
                        style: TextStyle(fontFamily: _kFont, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _documentosVinculados = widget.svc
                            .getDocumentosVinculadosMarca(
                              widget.empresaId,
                              widget.marcaId,
                              marcaNombre: widget.titulo,
                            );
                      }),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
            else if (vinculados.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Text(
                  'No hay otros documentos vinculados desde productos.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              )
            else
              ...vinculados.map((vinculado) {
                final label =
                    kDocumentosAsociadosLabels[vinculado.tipo] ??
                    kDocRecepcionLabels[vinculado.tipo] ??
                    vinculado.tipo;
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDDE3F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8EAF6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.description_outlined,
                              size: 17,
                              color: Color(0xFF283593),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  vinculado.productoNombre.isEmpty
                                      ? 'Producto sin nombre registrado'
                                      : vinculado.productoNombre,
                                  style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 12,
                                    color: Colors.black87,
                                  ),
                                ),
                                if (vinculado.proveedorNombre.isNotEmpty)
                                  Text(
                                    'Proveedor: ${vinculado.proveedorNombre}',
                                    style: const TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 11,
                                      color: Colors.black54,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _consultaDocumentoChip(
                            vinculado.tipo,
                            'Estado',
                            vinculado.documento,
                            requerido: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        vinculado.documento.nombre ?? 'Documento sin nombre',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _origenDocumentoVinculado(vinculado.origen),
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 10.5,
                                fontStyle: FontStyle.italic,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _abrirUrl(context, vinculado.documento.url),
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: const Text('Ver documento'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_copy_outlined, color: kComprasPrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Documentos asociados',
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        widget.titulo,
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.requiredForCompletion
                  ? 'La ficha técnica y el registro sanitario son obligatorios para esta marca. Todo archivo nuevo o reemplazado queda pendiente de revisión de Calidad.'
                  : 'Carga o reemplaza los archivos de la marca. Quedarán pendientes hasta que Calidad los apruebe.',
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 18),
            for (final entry in kDocumentosAsociadosLabels.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _DocAttachButton(
                  label: entry.value,
                  doc: _documentos[entry.key],
                  qualityRequired: true,
                  uploading: _subiendo.contains(entry.key),
                  onAttach: () => _seleccionarArchivo(entry.key),
                  onView: _documentos[entry.key]?.tieneDoc == true
                      ? () => _abrirUrl(context, _documentos[entry.key]?.url)
                      : null,
                  onDelete: _documentos[entry.key]?.tieneDoc == true
                      ? () => _eliminar(entry.key)
                      : null,
                  showCalendar: documentoRequiereVigencia(entry.key),
                  onDateChanged: (date) => _actualizarFecha(entry.key, date),
                  onRequirementUpload:
                      _documentos[entry.key]?.aprobadoConRequerimientos == true
                      ? (bytes, name) async {
                          final ext = name.toLowerCase().split('.').last;
                          final actualizado = await widget.svc
                              .agregarSoporteRequerimiento(
                                empresaId: widget.empresaId,
                                tipo: 'marca',
                                entidadId: widget.marcaId,
                                docKey: entry.key,
                                userId: widget.userId,
                                bytes: bytes,
                                nombre: name,
                                contentType: ext == 'pdf'
                                    ? 'application/pdf'
                                    : 'image/$ext',
                              );
                          if (mounted) {
                            setState(
                              () => _documentos = {
                                ..._documentos,
                                entry.key: actualizado,
                              },
                            );
                          }
                        }
                      : null,
                  onWebUpload: (bytes, name) =>
                      _subirBytes(entry.key, bytes, name),
                ),
              ),
            _documentosVinculadosSection(),
          ],
        ),
      ),
    );
  }
}

class _ProveedoresScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final String userId;

  /// Se propaga al formulario para habilitar "Revertir aprobación".
  final bool esAdmin;

  const _ProveedoresScreen({
    required this.empresaId,
    required this.svc,
    required this.userId,
    this.esAdmin = false,
  });

  @override
  State<_ProveedoresScreen> createState() => _ProveedoresScreenState();
}

class _ProveedoresScreenState extends State<_ProveedoresScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _estadoVista = 'activos';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text(
          'Proveedores',
          style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold),
        ),
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, NIT o ciudad...',
                    hintStyle: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => setState(() => _query = v.toLowerCase()),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in const [
                        ('activos', 'Activos', Icons.check_circle_outline),
                        ('inactivos', 'Inhabilitados', Icons.block_outlined),
                        ('todos', 'Todos', Icons.people_alt_outlined),
                      ])
                        ChoiceChip(
                          avatar: Icon(option.$3, size: 16),
                          label: Text(option.$2),
                          selected: _estadoVista == option.$1,
                          onSelected: (_) =>
                              setState(() => _estadoVista = option.$1),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ProveedorDoc>>(
              stream: widget.svc.streamProveedores(widget.empresaId),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? [];
                final filtered = all.where((p) {
                  final stateMatches = switch (_estadoVista) {
                    'activos' => p.activo,
                    'inactivos' => !p.activo,
                    _ => true,
                  };
                  if (!stateMatches) return false;
                  return _query.isEmpty ||
                      p.razonSocial.toLowerCase().contains(_query) ||
                      p.nit.contains(_query) ||
                      p.ciudad.toLowerCase().contains(_query);
                }).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _query.isEmpty
                          ? 'Sin proveedores registrados'
                          : 'Sin resultados para "$_query"',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        color: Colors.black45,
                      ),
                    ),
                  );
                }
                return _comprasResponsiveList<ProveedorDoc>(
                  items: filtered,
                  itemBuilder: (ctx, p, i) => _ProveedorCard(
                    proveedor: p,
                    onTap: () => _openForm(existing: p),
                    onDelete: () => _confirmDelete(p),
                    onCambiarEstado: () => _cambiarEstado(p),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text(
          'Nuevo Proveedor',
          style: TextStyle(fontFamily: _kFont),
        ),
      ),
    );
  }

  void _openForm({ProveedorDoc? existing}) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _ProveedorFormScreen(
        empresaId: widget.empresaId,
        svc: widget.svc,
        existing: existing,
        userId: widget.userId,
        esAdmin: widget.esAdmin,
      ),
    ),
  );

  Future<void> _confirmDelete(ProveedorDoc p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: _comprasDialogTitle(
          ctx,
          'Eliminar proveedor',
          icon: Icons.delete_outline,
        ),
        content: Text(
          '¿Desea eliminar a "${p.razonSocial}"?',
          style: const TextStyle(fontFamily: _kFont),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) await widget.svc.eliminarProveedor(p.id);
  }

  Future<void> _cambiarEstado(ProveedorDoc proveedor) async {
    final motivo = TextEditingController();
    final activar = !proveedor.activo;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(activar ? 'Reactivar proveedor' : 'Inhabilitar proveedor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              activar
                  ? '${proveedor.razonSocial} volverá a estar disponible para nuevas recepciones.'
                  : '${proveedor.razonSocial} dejará de aparecer al crear nuevas recepciones. Su historial se conservará.',
            ),
            if (!activar) ...[
              const SizedBox(height: 14),
              TextField(
                controller: motivo,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(activar ? 'Reactivar' : 'Inhabilitar'),
          ),
        ],
      ),
    );
    final detalle = motivo.text;
    motivo.dispose();
    if (confirmado != true) return;
    await widget.svc.cambiarEstadoProveedor(
      proveedorId: proveedor.id,
      activo: activar,
      userId: widget.userId,
      motivo: detalle,
    );
  }
}

class _ProveedorCard extends StatelessWidget {
  final ProveedorDoc proveedor;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onCambiarEstado;

  const _ProveedorCard({
    required this.proveedor,
    required this.onTap,
    required this.onDelete,
    required this.onCambiarEstado,
  });

  @override
  Widget build(BuildContext context) {
    final docsKeys = [kDocRut, kDocCertExistencia, kDocActaInspeccion];
    final tieneRequeridos = docsKeys.every(
      (k) => proveedor.documentos[k]?.tieneDoc == true,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      proveedor.razonSocial,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  _StatusDot(ok: tieneRequeridos),
                  const SizedBox(width: 6),
                  _ConsultaLegendChip(
                    color: proveedor.activo ? kComprasGreen : kComprasRed,
                    label: proveedor.activo ? 'Activo' : 'Inhabilitado',
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'delete') onDelete();
                      if (v == 'edit') onTap();
                      if (v == 'status') onCambiarEstado();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text(
                          'Editar',
                          style: TextStyle(fontFamily: _kFont),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'status',
                        child: Text(
                          proveedor.activo ? 'Inhabilitar' : 'Reactivar',
                          style: TextStyle(
                            fontFamily: _kFont,
                            color: proveedor.activo
                                ? Colors.orange.shade800
                                : kComprasGreen,
                          ),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Eliminar',
                          style: TextStyle(
                            fontFamily: _kFont,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.badge, size: 14, color: Colors.black45),
                  const SizedBox(width: 4),
                  Text(
                    'NIT: ${proveedor.nit}',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  const Spacer(),
                  if (proveedor.ciudad.isNotEmpty)
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 13,
                          color: Colors.black38,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          proveedor.ciudad,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (proveedor.categorias.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: proveedor.categorias
                      .map((c) => _Chip(c, kComprasPrimary))
                      .toList(),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (proveedor.esLocal)
                    _Chip('Local', kComprasGreen)
                  else
                    _Chip('No local', Colors.grey),
                  const Spacer(),
                  ...docsKeys.map((k) {
                    final tiene = proveedor.documentos[k]?.tieneDoc == true;
                    return Tooltip(
                      message: kDocProveedorLabels[k] ?? k,
                      child: Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: tiene ? kComprasGreen : kComprasRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PROVEEDOR FORM SCREEN — crear / editar
// ══════════════════════════════════════════════════════════════════════════════

class _ProveedorFormScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final ProveedorDoc? existing;
  final String userId;
  final String? correccionTaskId;
  final String? correccionDocKey;

  /// Habilita "Revertir aprobación" en cada documento ya aprobado.
  final bool esAdmin;

  const _ProveedorFormScreen({
    required this.empresaId,
    required this.svc,
    this.existing,
    required this.userId,
    this.correccionTaskId,
    this.correccionDocKey,
    this.esAdmin = false,
  });

  @override
  State<_ProveedorFormScreen> createState() => _ProveedorFormScreenState();
}

class _ProveedorFormScreenState extends State<_ProveedorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nitCtrl;
  late final TextEditingController _razonCtrl;
  late final TextEditingController _dirCtrl;
  late final TextEditingController _telCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _ciudadCtrl;

  String? _departamentoCod;
  String? _departamentoNombre;
  String? _ciudadCod;
  List<ComprasCatalogItem> _departamentos = [];
  List<ComprasCatalogItem> _ciudades = [];
  bool _cargandoDepartamentos = false;
  bool _cargandoCiudades = false;
  String? _catalogoError;
  bool _esLocal = false;
  List<String> _categorias = [];
  Map<String, DocAdjunto> _documentos = {};
  bool _guardando = false;

  bool get isNew => widget.existing == null;
  bool get _esCorreccionDirigida =>
      (widget.correccionTaskId ?? '').trim().isNotEmpty &&
      (widget.correccionDocKey ?? '').trim().isNotEmpty;

  bool _esDocumentoCorreccion(String key) =>
      _esCorreccionDirigida && key == widget.correccionDocKey!.trim();

  Future<void> _enviarCorreccionARevision(DocAdjunto doc) async {
    final taskId = widget.correccionTaskId?.trim() ?? '';
    if (taskId.isEmpty) return;
    await widget.svc.enviarTareaCorreccionARevision(
      taskId: taskId,
      subidoPor: widget.userId,
      nombreDocumento: doc.nombre ?? 'Documento corregido',
      urlDocumento: doc.url,
    );
  }

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nitCtrl = TextEditingController(text: p?.nit ?? '');
    _razonCtrl = TextEditingController(text: p?.razonSocial ?? '');
    _dirCtrl = TextEditingController(text: p?.direccion ?? '');
    _telCtrl = TextEditingController(text: p?.telefono ?? '');
    _emailCtrl = TextEditingController(text: p?.email ?? '');
    _ciudadCtrl = TextEditingController(text: p?.ciudad ?? '');
    _departamentoCod = p?.departamentoCod;
    _departamentoNombre = p?.departamento;
    _ciudadCod = p?.ciudadCod;
    _esLocal = p?.esLocal ?? false;
    _categorias = List.from(p?.categorias ?? []);
    _documentos = Map.from(p?.documentos ?? {});
    _cargarDepartamentos();
  }

  @override
  void dispose() {
    for (final c in [
      _nitCtrl,
      _razonCtrl,
      _dirCtrl,
      _telCtrl,
      _emailCtrl,
      _ciudadCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _catalogKey(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');

  ComprasCatalogItem? _findCatalogItem(
    List<ComprasCatalogItem> items, {
    String? code,
    String? name,
  }) {
    final cleanedCode = (code ?? '').trim();
    if (cleanedCode.isNotEmpty) {
      for (final item in items) {
        if (item.code == cleanedCode) return item;
      }
    }
    final cleanedName = _catalogKey(name ?? '');
    if (cleanedName.isEmpty) return null;
    for (final item in items) {
      if (_catalogKey(item.name) == cleanedName) return item;
    }
    return null;
  }

  String? _catalogValue(List<ComprasCatalogItem> items, String? code) {
    final cleanedCode = (code ?? '').trim();
    if (cleanedCode.isEmpty) return null;
    return items.any((item) => item.code == cleanedCode) ? cleanedCode : null;
  }

  Future<void> _cargarDepartamentos() async {
    setState(() {
      _cargandoDepartamentos = true;
      _catalogoError = null;
    });
    try {
      final items = await widget.svc.getDepartamentos();
      if (!mounted) return;
      final matched = _findCatalogItem(
        items,
        code: _departamentoCod,
        name: _departamentoNombre,
      );
      setState(() {
        _departamentos = items;
        if (matched != null) {
          _departamentoCod = matched.code;
          _departamentoNombre = matched.name;
        }
      });
      if ((_departamentoCod ?? '').isNotEmpty) {
        await _cargarCiudades(
          _departamentoCod!,
          initialCityName: _ciudadCtrl.text,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catalogoError = 'No se pudieron cargar departamentos y ciudades.';
      });
    } finally {
      if (mounted) setState(() => _cargandoDepartamentos = false);
    }
  }

  Future<void> _cargarCiudades(
    String departamentoCode, {
    String? initialCityName,
  }) async {
    setState(() {
      _cargandoCiudades = true;
      _catalogoError = null;
    });
    try {
      final items = await widget.svc.getCiudades(departamentoCode);
      if (!mounted) return;
      final matched = _findCatalogItem(
        items,
        code: _ciudadCod,
        name: initialCityName ?? _ciudadCtrl.text,
      );
      setState(() {
        _ciudades = items;
        if (matched != null) {
          _ciudadCod = matched.code;
          _ciudadCtrl.text = matched.name;
        } else {
          _ciudadCod = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ciudades = [];
        _ciudadCod = null;
        _catalogoError = 'No se pudieron cargar las ciudades.';
      });
    } finally {
      if (mounted) setState(() => _cargandoCiudades = false);
    }
  }

  void _onDepartamentoChanged(String? code) {
    final item = _findCatalogItem(_departamentos, code: code);
    setState(() {
      _departamentoCod = item?.code;
      _departamentoNombre = item?.name;
      _ciudadCod = null;
      _ciudadCtrl.clear();
      _ciudades = [];
      _catalogoError = null;
    });
    if (item != null) {
      _cargarCiudades(item.code);
    }
  }

  void _onCiudadChanged(String? code) {
    final item = _findCatalogItem(_ciudades, code: code);
    setState(() {
      _ciudadCod = item?.code;
      _ciudadCtrl.text = item?.name ?? '';
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final pendientes = resumenPendientesDocumentalesProveedor(_documentos);
    setState(() => _guardando = true);
    try {
      final p = ProveedorDoc(
        id: widget.existing?.id ?? '',
        empresaId: widget.empresaId,
        nit: _nitCtrl.text.trim(),
        razonSocial: _normalizarNombre(_razonCtrl.text),
        direccion: _dirCtrl.text.trim(),
        telefono: _telCtrl.text.trim(),
        email: _emailCtrl.text.trim().toLowerCase(),
        departamentoCod: _departamentoCod ?? '',
        departamento: _departamentoNombre ?? '',
        ciudadCod: _ciudadCod ?? '',
        ciudad: _normalizarNombre(_ciudadCtrl.text),
        esLocal: _esLocal,
        categorias: _categorias,
        documentos: _documentos,
        createdAt: widget.existing?.createdAt ?? Timestamp.now(),
        activo: widget.existing?.activo ?? true,
        inactivadoAt: widget.existing?.inactivadoAt,
        inactivadoPor: widget.existing?.inactivadoPor ?? '',
        motivoInactivacion: widget.existing?.motivoInactivacion ?? '',
      );
      await widget.svc.guardarProveedor(
        p,
        isNew: isNew,
        creadoPor: widget.userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pendientes == null
                  ? (isNew ? 'Proveedor creado' : 'Proveedor actualizado')
                  : (isNew
                        ? 'Proveedor creado con documentación pendiente.'
                        : 'Avance documental guardado. Aún hay pendientes por completar.'),
            ),
            backgroundColor: pendientes == null
                ? kComprasGreen
                : const Color(0xFFB45309),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kComprasRed),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _adjuntarDoc(String key) async {
    final nombre = kDocProveedorLabels[key] ?? key;
    final doc = await _mostrarEscaneador(
      context,
      empresaId: widget.empresaId,
      carpeta: 'proveedores',
      nombreSugerido: '${_nitCtrl.text}_$nombre',
      svc: widget.svc,
      userId: widget.userId,
    );
    if (doc == null) return;
    DateTime? vigencia;
    if (documentoRequiereVigencia(key) && mounted) {
      vigencia = await _solicitarVigenciaDespuesDeCargar(
        context,
        docKey: key,
        labels: kDocProveedorLabels,
      );
    }
    if (!mounted) return;
    final docFinal = prepararDocumentoPendienteCalidad(
      doc,
      subidoPor: widget.userId,
      fechaVencimiento: vigencia == null ? null : Timestamp.fromDate(vigencia),
    );
    setState(() => _documentos = {..._documentos, key: docFinal});
    if (!isNew) {
      await widget.svc.actualizarDocProveedor(
        proveedorId: widget.existing!.id,
        docKey: key,
        doc: docFinal,
      );
      if (_esDocumentoCorreccion(key)) {
        await _enviarCorreccionARevision(docFinal);
      }
    }
  }

  Future<void> _actualizarVigenciaDocumento(String key, DateTime? date) async {
    final anterior = _documentos[key] ?? const DocAdjunto();
    if (date == null && anterior.tieneDoc && documentoRequiereVigencia(key)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No puedes quitar la vigencia mientras el documento esté cargado.',
          ),
          backgroundColor: kComprasRed,
        ),
      );
      return;
    }

    final actualizado = anterior.copyWith(
      fechaVencimiento: date == null ? null : Timestamp.fromDate(date),
      clearFechaVencimiento: date == null,
    );
    setState(() {
      _documentos = {..._documentos, key: actualizado};
    });

    // Un proveedor nuevo todavía no tiene documento en Firestore. La fecha
    // queda en el formulario y se persiste al crear el registro.
    if (isNew || !anterior.tieneDoc) return;

    try {
      await widget.svc.actualizarDocProveedor(
        proveedorId: widget.existing!.id,
        docKey: key,
        doc: actualizado,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vigencia actualizada automáticamente.'),
          backgroundColor: kComprasGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _documentos = {..._documentos, key: anterior};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la vigencia: $error'),
          backgroundColor: kComprasRed,
        ),
      );
    }
  }

  /// Revierte una aprobación dada por error, sin salir del expediente.
  /// Solo llega aquí el Admin Documental sobre un proveedor ya existente.
  Future<void> _revertirAprobacion(String key) async {
    final anterior = _documentos[key];
    if (anterior == null || !anterior.aprobado) return;

    final decision = await _pedirMotivoReversion(
      context,
      docLabel: kDocProveedorLabels[key] ?? key,
      contexto: _razonCtrl.text.trim().isEmpty
          ? 'Proveedor'
          : _razonCtrl.text.trim(),
    );
    if (decision == null || !mounted) return;

    try {
      await widget.svc.revertirAprobacionDocProveedor(
        proveedorId: widget.existing!.id,
        docKey: key,
        motivo: decision.motivo,
        revertidoPor: widget.userId,
        rechazar: decision.rechazar,
      );
      if (!mounted) return;
      // Reflejar el nuevo estado en el formulario sin recargar la pantalla.
      setState(() {
        _documentos = {
          ..._documentos,
          key: anterior.copyWith(
            estadoCalidad: decision.rechazar
                ? 'rechazado'
                : 'pendiente_revision_calidad',
            observacionCalidad: decision.rechazar ? decision.motivo : null,
            revertidoPor: widget.userId,
            fechaReversion: Timestamp.now(),
            motivoReversion: decision.motivo,
            estadoAnteriorReversion: anterior.estadoCalidad,
          ),
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: decision.rechazar
              ? kComprasRed
              : const Color(0xFFB45309),
          content: Text(
            decision.rechazar
                ? 'Aprobación revertida. El documento quedó rechazado y se notificó a quien lo subió.'
                : 'Aprobación revertida. El documento volvió a la cola de Calidad.',
            style: const TextStyle(fontFamily: _kFont),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final mensaje = error is StateError ? error.message : error.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo revertir: $mensaje'),
          backgroundColor: kComprasRed,
        ),
      );
    }
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: kComprasPrimary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: kComprasPrimary,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: Text(
          isNew ? 'Nuevo Proveedor' : 'Editar Proveedor',
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
        actions: [
          if (_guardando)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            TextButton(
              onPressed: _guardar,
              child: const Text(
                'Guardar',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: _kFont,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Info básica ──────────────────────────────
                  _sectionHeader('Información básica'),
                  _buildField(
                    controller: _nitCtrl,
                    label: 'NIT *',
                    hint: 'Ej: 900123456-1',
                    keyboardType: TextInputType.text,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\-]')),
                    ],
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Campo requerido'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _razonCtrl,
                    label: 'Razón Social *',
                    hint: 'Nombre de la empresa proveedora',
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Campo requerido'
                        : null,
                  ),
                  // ── Contacto ────────────────────────────────
                  _sectionHeader('Contacto'),
                  _buildField(
                    controller: _dirCtrl,
                    label: 'Dirección',
                    hint: 'Calle 123 # 45-67',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildField(
                          controller: _telCtrl,
                          label: 'Teléfono',
                          keyboardType: TextInputType.phone,
                          hint: '3001234567',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildField(
                          controller: _emailCtrl,
                          label: 'Email',
                          keyboardType: TextInputType.emailAddress,
                          hint: 'correo@empresa.com',
                          uppercase: false,
                        ),
                      ),
                    ],
                  ),
                  // ── Ubicación ────────────────────────────────
                  _sectionHeader('Ubicación'),
                  if (_catalogoError != null) ...[
                    Text(
                      _catalogoError!,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: kComprasRed,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'proveedor_departamento_${_departamentoCod ?? ''}_${_departamentos.length}',
                    ),
                    initialValue: _catalogValue(
                      _departamentos,
                      _departamentoCod,
                    ),
                    decoration: _inputDecoration('Departamento').copyWith(
                      suffixIcon: _cargandoDepartamentos
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                    isExpanded: true,
                    items: _departamentos
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.code,
                            child: Text(
                              d.name,
                              style: const TextStyle(fontFamily: _kFont),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _cargandoDepartamentos
                        ? null
                        : _onDepartamentoChanged,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'proveedor_ciudad_${_departamentoCod ?? ''}_${_ciudadCod ?? ''}_${_ciudades.length}',
                    ),
                    initialValue: _catalogValue(_ciudades, _ciudadCod),
                    decoration: _inputDecoration('Ciudad / Municipio').copyWith(
                      hintText: (_departamentoCod ?? '').isEmpty
                          ? 'Selecciona primero el departamento'
                          : 'Selecciona ciudad',
                      suffixIcon: _cargandoCiudades
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                    isExpanded: true,
                    items: _ciudades
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.code,
                            child: Text(
                              c.name,
                              style: const TextStyle(fontFamily: _kFont),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged:
                        (_departamentoCod ?? '').isEmpty || _cargandoCiudades
                        ? null
                        : _onCiudadChanged,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _esLocal,
                    onChanged: (v) => setState(() => _esLocal = v),
                    title: const Text(
                      'Es proveedor local',
                      style: TextStyle(fontFamily: _kFont, fontSize: 14),
                    ),
                    activeColor: kComprasPrimary,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  // ── Categorías ───────────────────────────────
                  _sectionHeader('Categorías de productos'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kCategoriasCompras.map((cat) {
                      final sel = _categorias.contains(cat);
                      return FilterChip(
                        label: Text(
                          cat,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 13,
                          ),
                        ),
                        selected: sel,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _categorias.add(cat);
                            } else {
                              _categorias.remove(cat);
                            }
                          });
                        },
                        selectedColor: kComprasPrimary.withOpacity(0.15),
                        checkmarkColor: kComprasPrimary,
                        side: BorderSide(
                          color: sel ? kComprasPrimary : Colors.grey.shade300,
                        ),
                      );
                    }).toList(),
                  ),
                  // ── Documentos ───────────────────────────────
                  _sectionHeader('Documentos'),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF93C5FD)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.save_outlined,
                          size: 19,
                          color: kComprasPrimary,
                        ),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Puedes guardar el avance aunque falten documentos o fechas de vigencia. Los pendientes seguirán visibles hasta completar el expediente.',
                            style: TextStyle(
                              fontFamily: _kFont,
                              fontSize: 12,
                              height: 1.35,
                              color: Color(0xFF1E3A5F),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_esCorreccionDirigida) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF93C5FD)),
                      ),
                      child: Text(
                        'Carga el documento corregido señalado. Al hacerlo quedará enviado a revisión de Calidad.',
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  ...kDocProveedorLabels.entries
                      .where((e) => !kDocProveedorOcultos.contains(e.key))
                      .map((e) {
                        final key = e.key;
                        final label = e.value;
                        final isReq =
                            key == kDocRut || key == kDocCertExistencia;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DocAttachButton(
                            label: label,
                            required_: isReq,
                            doc: _documentos[key],
                            onAttach: () => _adjuntarDoc(key),
                            onView: _documentos[key]?.tieneDoc == true
                                ? () =>
                                      _abrirUrl(context, _documentos[key]!.url)
                                : null,
                            onDelete: _documentos[key]?.tieneDoc == true
                                ? () => setState(
                                    () => _documentos = {
                                      ..._documentos,
                                      key: const DocAdjunto(),
                                    },
                                  )
                                : null,
                            onRevertir:
                                (widget.esAdmin &&
                                    !isNew &&
                                    _documentos[key]?.aprobado == true)
                                ? () => _revertirAprobacion(key)
                                : null,
                            showCalendar: documentoRequiereVigencia(key),
                            onDateChanged: (date) =>
                                _actualizarVigenciaDocumento(key, date),
                            onRequirementUpload:
                                !isNew &&
                                    _documentos[key]
                                            ?.aprobadoConRequerimientos ==
                                        true
                                ? (bytes, name) async {
                                    final ext = name
                                        .toLowerCase()
                                        .split('.')
                                        .last;
                                    final actualizado = await widget.svc
                                        .agregarSoporteRequerimiento(
                                          empresaId: widget.empresaId,
                                          tipo: 'proveedor',
                                          entidadId: widget.existing!.id,
                                          docKey: key,
                                          userId: widget.userId,
                                          bytes: bytes,
                                          nombre: name,
                                          contentType: ext == 'pdf'
                                              ? 'application/pdf'
                                              : 'image/$ext',
                                        );
                                    if (mounted) {
                                      setState(
                                        () => _documentos = {
                                          ..._documentos,
                                          key: actualizado,
                                        },
                                      );
                                    }
                                  }
                                : null,
                            onWebUpload: (bytes, name) async {
                              final ext = name.toLowerCase().split('.').last;
                              final ct = ext == 'pdf'
                                  ? 'application/pdf'
                                  : 'image/$ext';
                              final doc = await widget.svc.subirBytes(
                                bytes: bytes,
                                empresaId: widget.empresaId,
                                carpeta: 'proveedores',
                                nombre:
                                    '${_nitCtrl.text}_${kDocProveedorLabels[key] ?? key}_$name',
                                contentType: ct,
                              );
                              if (!mounted) return;
                              DateTime? vigencia;
                              if (documentoRequiereVigencia(key)) {
                                vigencia =
                                    await _solicitarVigenciaDespuesDeCargar(
                                      context,
                                      docKey: key,
                                      labels: kDocProveedorLabels,
                                    );
                              }
                              if (!mounted) return;
                              // Registrar quién subió el doc y marcarlo pendiente de revisión.
                              final docFinal =
                                  prepararDocumentoPendienteCalidad(
                                    doc,
                                    subidoPor: widget.userId,
                                    fechaVencimiento: vigencia == null
                                        ? null
                                        : Timestamp.fromDate(vigencia),
                                  );
                              setState(
                                () => _documentos = {
                                  ..._documentos,
                                  key: docFinal,
                                },
                              );
                              // Auto-guardar en Firestore inmediatamente para que
                              // Revisión de Calidad lo vea sin tener que pulsar Guardar
                              if (!isNew) {
                                await widget.svc.actualizarDocProveedor(
                                  proveedorId: widget.existing!.id,
                                  docKey: key,
                                  doc: docFinal,
                                );
                                if (_esDocumentoCorreccion(key)) {
                                  await _enviarCorreccionARevision(docFinal);
                                }
                              }
                            },
                          ),
                        );
                      }),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    bool uppercase = true,
  }) => TextFormField(
    controller: controller,
    decoration: _inputDecoration(label).copyWith(hintText: hint),
    keyboardType: keyboardType,
    inputFormatters: [
      ...?inputFormatters,
      if (uppercase) const _UpperCaseTextFormatter(),
    ],
    textCapitalization: uppercase
        ? TextCapitalization.characters
        : TextCapitalization.none,
    validator: validator,
    style: const TextStyle(
      fontFamily: _kFont,
      fontSize: 14,
      letterSpacing: 0.35,
      height: 1.25,
    ),
  );
}

InputDecoration _inputDecoration(String label) => InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(fontFamily: _kFont, fontSize: 13),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  filled: true,
  fillColor: Colors.white,
);

// ══════════════════════════════════════════════════════════════════════════════
// PRODUCTOS SCREEN — listado
// ══════════════════════════════════════════════════════════════════════════════

class _ProductosScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final String userId;

  const _ProductosScreen({
    required this.empresaId,
    required this.svc,
    required this.userId,
  });

  @override
  State<_ProductosScreen> createState() => _ProductosScreenState();
}

class _ProductosScreenState extends State<_ProductosScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _filtroCategoria;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text(
          'Productos',
          style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0277BD),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar producto o código...',
                hintStyle: const TextStyle(fontFamily: _kFont, fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          // Filtro por categoría
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _CatChip(
                  'Todos',
                  _filtroCategoria == null,
                  () => setState(() => _filtroCategoria = null),
                ),
                ...kCategoriasCompras.map(
                  (c) => _CatChip(
                    c,
                    _filtroCategoria == c,
                    () => setState(() => _filtroCategoria = c),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<ProductoDoc>>(
              stream: widget.svc.streamProductos(widget.empresaId),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? [];
                var filtered = _query.isEmpty
                    ? all
                    : all
                          .where(
                            (p) =>
                                p.nombre.toLowerCase().contains(_query) ||
                                p.codigo.toLowerCase().contains(_query) ||
                                p.categoria.toLowerCase().contains(_query),
                          )
                          .toList();
                if (_filtroCategoria != null) {
                  filtered = filtered
                      .where((p) => p.categoria == _filtroCategoria)
                      .toList();
                }
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'Sin productos',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        color: Colors.black45,
                      ),
                    ),
                  );
                }
                return _comprasResponsiveList<ProductoDoc>(
                  items: filtered,
                  itemBuilder: (_, producto, i) => _ProductoCard(
                    producto: producto,
                    onTap: () => _openForm(existing: producto),
                    onDelete: () => _confirmDelete(producto),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0277BD),
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text(
          'Nuevo Producto',
          style: TextStyle(fontFamily: _kFont),
        ),
      ),
    );
  }

  void _openForm({ProductoDoc? existing}) => _showComprasAdaptiveSheet(
    context: context,
    title: existing == null ? 'Nuevo producto' : 'Editar producto',
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ProductoFormSheet(
      empresaId: widget.empresaId,
      svc: widget.svc,
      existing: existing,
      userId: widget.userId,
    ),
  );

  Future<void> _confirmDelete(ProductoDoc p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: _comprasDialogTitle(
          ctx,
          'Eliminar producto',
          icon: Icons.delete_outline,
        ),
        content: Text(
          '¿Eliminar "${p.nombre}"?',
          style: const TextStyle(fontFamily: _kFont),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) await widget.svc.eliminarProducto(p.id);
  }
}

Widget _CatChip(String label, bool selected, VoidCallback onTap) => Padding(
  padding: const EdgeInsets.only(right: 6),
  child: GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF0277BD) : Colors.white,
        border: Border.all(
          color: selected ? const Color(0xFF0277BD) : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: _kFont,
          fontSize: 12,
          color: selected ? Colors.white : Colors.black54,
        ),
      ),
    ),
  ),
);

class _ProductoCard extends StatelessWidget {
  final ProductoDoc producto;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProductoCard({
    required this.producto,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF0277BD).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.inventory_2,
                  color: Color(0xFF0277BD),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            producto.codigo,
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (producto.esPerecedero)
                          _Chip('Perecedero', Colors.orange.shade700),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      producto.nombre,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _Chip(producto.categoria, const Color(0xFF0277BD)),
                        const SizedBox(width: 6),
                        _Chip(producto.unidadMedida, Colors.blueGrey),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onTap();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text(
                      'Editar y gestionar marcas',
                      style: TextStyle(fontFamily: _kFont),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Eliminar',
                      style: TextStyle(fontFamily: _kFont, color: Colors.red),
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_vert, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PRODUCTO FORM SHEET — crear / editar (bottom sheet)
// ══════════════════════════════════════════════════════════════════════════════

class _ProductoFormSheet extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final ProductoDoc? existing;
  final String userId;

  const _ProductoFormSheet({
    required this.empresaId,
    required this.svc,
    this.existing,
    required this.userId,
  });

  @override
  State<_ProductoFormSheet> createState() => _ProductoFormSheetState();
}

class _ProductoFormSheetState extends State<_ProductoFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codigoCtrl;
  late final TextEditingController _nombreCtrl;
  String? _unidad;
  String? _categoria;
  bool _perecedero = false;
  bool _guardando = false;
  List<MarcaRef> _marcasProducto = [];
  List<MarcaDoc> _todasMarcas = [];
  List<ProductoDoc> _productosExistentes = [];
  bool _loadingMarcas = true;
  bool _loadingFichasProveedor = false;
  String _origen = 'NACIONAL'; // 'NACIONAL' | 'IMPORTADO'
  Map<String, DocAdjunto> _fichasPorMarca = {};
  List<FichaTecnicaDoc> _fichasTecnicasProveedor = [];

  bool get isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _codigoCtrl = TextEditingController(text: p?.codigo ?? '');
    _nombreCtrl = TextEditingController(text: p?.nombre ?? '');
    _unidad = p?.unidadMedida.isNotEmpty == true ? p!.unidadMedida : null;
    _categoria = p?.categoria.isNotEmpty == true ? p!.categoria : null;
    _perecedero = p?.esPerecedero ?? false;
    _marcasProducto = List.from(p?.marcas ?? []);
    _origen = p?.origen ?? 'NACIONAL';
    _fichasPorMarca = Map<String, DocAdjunto>.from(
      p?.fichasTecnicasPorMarca ?? {},
    );
    _loadMarcas();
    _loadFichasProveedor();
    _loadProductosExistentes();
  }

  Future<void> _loadFichasProveedor() async {
    final productoId = widget.existing?.id.trim() ?? '';
    if (productoId.isEmpty) return;
    setState(() => _loadingFichasProveedor = true);
    try {
      final fichas = await widget.svc.getFichasTecnicas(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _fichasTecnicasProveedor = fichas
            .where(
              (ficha) => fichaTecnicaCorrespondeProducto(
                ficha,
                productoId: productoId,
                productoNombre:
                    widget.existing?.nombre ?? _nombreCtrl.text.trim(),
              ),
            )
            .toList();
        _loadingFichasProveedor = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingFichasProveedor = false);
    }
  }

  Future<void> _loadMarcas() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_MARCAS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      if (!mounted) return;
      final list =
          snap.docs.map((d) => MarcaDoc.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.descripcion.compareTo(b.descripcion));
      setState(() {
        _todasMarcas = list;
        _loadingMarcas = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMarcas = false);
    }
  }

  Future<void> _loadProductosExistentes() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_PRODUCTOS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      if (!mounted) return;
      setState(() {
        _productosExistentes = snap.docs
            .map((d) => ProductoDoc.fromMap(d.id, d.data()))
            .toList();
      });
    } catch (_) {}
  }

  ProductoDoc? _buscarCoincidenciaProducto({
    required String codigo,
    required String nombre,
  }) {
    final code = codigo.trim().toUpperCase();
    final name = _normalizarNombre(nombre).toLowerCase();
    for (final p in _productosExistentes) {
      if (!isNew && p.id == widget.existing?.id) continue;
      final sameCode = p.codigo.trim().toUpperCase() == code;
      final sameName = p.nombre.trim().toLowerCase() == name;
      if (sameCode || sameName) return p;
    }
    return null;
  }

  bool _pareceProteina(String texto) {
    final t = texto.toLowerCase();
    return t.contains('prote') ||
        t.contains('carne') ||
        t.contains('pollo') ||
        t.contains('cerdo') ||
        t.contains('pescado') ||
        t.contains('res');
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _agregarMarca() async {
    // Mostrar sólo las marcas que aún no están vinculadas
    final yaVinculadas = _marcasProducto.map((r) => r.marcaId).toSet();
    final disponibles = _todasMarcas
        .where((m) => !yaVinculadas.contains(m.id))
        .toList();
    if (disponibles.isEmpty) {
      await _crearMarcaDesdeProducto();
      return;
    }
    final seleccionada = await _showComprasAdaptiveSheet<MarcaDoc>(
      context: context,
      title: 'Seleccionar marca',
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MarcaSelectorSheet(marcas: disponibles),
    );
    if (seleccionada != null && mounted) {
      setState(() => _marcasProducto.add(seleccionada.toRef()));
      await _abrirDocumentosMarca(seleccionada.toRef());
    }
  }

  Future<void> _crearMarcaDesdeProducto() async {
    final creada = await _showComprasAdaptiveSheet<MarcaDoc>(
      context: context,
      title: 'Crear marca',
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _MarcaFormSheet(empresaId: widget.empresaId, svc: widget.svc),
      ),
    );
    if (creada == null || !mounted) return;

    setState(() {
      _todasMarcas = [
        ..._todasMarcas.where((marca) => marca.id != creada.id),
        creada,
      ]..sort((a, b) => a.descripcion.compareTo(b.descripcion));
      if (!_marcasProducto.any((marca) => marca.marcaId == creada.id)) {
        _marcasProducto.add(creada.toRef());
      }
    });
    await _abrirDocumentosMarca(creada.toRef());
  }

  MarcaDoc? _marcaPorId(String marcaId) {
    for (final marca in _todasMarcas) {
      if (marca.id == marcaId) return marca;
    }
    return null;
  }

  Future<void> _abrirDocumentosMarca(MarcaRef ref) async {
    final marca = _marcaPorId(ref.marcaId);
    if (marca == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No fue posible cargar la información de ${ref.descripcion}.',
          ),
          backgroundColor: kComprasRed,
        ),
      );
      return;
    }
    await _showComprasAdaptiveSheet(
      context: context,
      title: 'Documentos de marca · ${ref.descripcion}',
      desktopHeader: false,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DocumentosAsociadosSheet(
        titulo: ref.descripcion,
        marcaId: marca.id,
        empresaId: widget.empresaId,
        userId: widget.userId,
        svc: widget.svc,
        documentos: marca.documentosAsociados,
        requiredForCompletion: true,
        onSave: (documentos) async {
          await widget.svc.actualizarDocumentosAsociadosMarca(
            marcaId: marca.id,
            documentos: documentos,
          );
          if (!mounted) return;
          final actualizada = MarcaDoc(
            id: marca.id,
            empresaId: marca.empresaId,
            codigo: marca.codigo,
            descripcion: marca.descripcion,
            documentosAsociados: Map<String, DocAdjunto>.from(documentos),
            createdAt: marca.createdAt,
            updatedAt: Timestamp.now(),
          );
          setState(() {
            _todasMarcas = _todasMarcas
                .map((item) => item.id == actualizada.id ? actualizada : item)
                .toList();
          });
        },
      ),
    );
  }

  List<FichaTecnicaDoc> _fichasProveedorMarca(MarcaRef marca) {
    final productoId = widget.existing?.id ?? '';
    if (productoId.isEmpty) return const [];
    return fichasCargadasProductoMarca(
      productoId: productoId,
      productoNombre: widget.existing?.nombre ?? _nombreCtrl.text,
      marcaId: marca.marcaId,
      marcaNombre: marca.descripcion,
      fichasTecnicas: _fichasTecnicasProveedor,
    );
  }

  DocAdjunto? _documentoVisibleFicha(FichaTecnicaDoc ficha) {
    final actual = ficha.documentoActual;
    if (actual?.tieneDoc == true) return actual;
    final aprobado = ficha.documentoAprobado;
    return aprobado?.tieneDoc == true ? aprobado : null;
  }

  ({String label, Color color, IconData icon}) _estadoFichaProveedor(
    DocAdjunto documento,
  ) {
    if (documento.rechazado) {
      return (label: 'Rechazada', color: kComprasRed, icon: Icons.cancel);
    }
    if (documento.aprobadoConRequerimientos) {
      return (
        label: 'Con requerimientos',
        color: const Color(0xFFD97706),
        icon: Icons.rule_folder_outlined,
      );
    }
    if (documento.aprobado) {
      return (label: 'Aprobada', color: kComprasGreen, icon: Icons.verified);
    }
    return (
      label: 'Pendiente Calidad',
      color: Colors.orange.shade800,
      icon: Icons.hourglass_top,
    );
  }

  Widget _resumenFichasProveedor(List<FichaTecnicaDoc> fichas) {
    if (fichas.isEmpty) return const SizedBox.shrink();
    final porProveedor = <String, FichaTecnicaDoc>{};
    for (final ficha in fichas) {
      final key = ficha.proveedorId.trim().isNotEmpty
          ? ficha.proveedorId.trim()
          : ficha.proveedorNombre.trim().toLowerCase();
      porProveedor.putIfAbsent(key, () => ficha);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 480;
        final fichasVisibles = porProveedor.values
            .where((ficha) => _documentoVisibleFicha(ficha) != null)
            .toList();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          padding: EdgeInsets.all(isMobile ? 12 : 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    size: 17,
                    color: kComprasPrimary,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Fichas cargadas por proveedor',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: kComprasPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${fichasVisibles.length}',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: kComprasPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              if (isMobile)
                Column(
                  children: fichasVisibles
                      .map(
                        (ficha) => Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: _fichaProveedorTile(ficha),
                        ),
                      )
                      .toList(),
                )
              else
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: fichasVisibles
                      .map(
                        (ficha) => SizedBox(
                          width: constraints.maxWidth < 700 ? 290 : 330,
                          child: _fichaProveedorTile(ficha),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _fichaProveedorTile(FichaTecnicaDoc ficha) {
    final documento = _documentoVisibleFicha(ficha)!;
    final estado = _estadoFichaProveedor(documento);
    final proveedor = ficha.proveedorNombre.trim().isEmpty
        ? 'Proveedor sin nombre'
        : ficha.proveedorNombre.trim();
    return Tooltip(
      message: 'Ficha técnica · ${estado.label}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: estado.color.withOpacity(0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: estado.color.withOpacity(0.11),
                shape: BoxShape.circle,
              ),
              child: Icon(estado.icon, size: 15, color: estado.color),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    proveedor,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 11.5,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    estado.label,
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: estado.color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _documentoMarcaEstado(
    MarcaDoc? marca,
    String key,
    String label, {
    List<FichaTecnicaDoc> fichasProveedor = const [],
  }) {
    final doc = marca?.documentosAsociados[key];
    final tieneDoc = doc?.tieneDoc == true;
    final faltaVigencia =
        tieneDoc &&
        documentoRequiereVigencia(key) &&
        doc?.fechaVencimiento == null;
    late final Color color;
    late final IconData icon;
    late final String estado;
    if (!tieneDoc && key == 'fichaTecnica' && _loadingFichasProveedor) {
      color = Colors.blueGrey;
      icon = Icons.sync;
      estado = 'Consultando';
    } else if (!tieneDoc && fichasProveedor.isNotEmpty) {
      color = const Color(0xFF0369A1);
      icon = Icons.cloud_done_outlined;
      final proveedores = fichasProveedor
          .map(
            (ficha) => ficha.proveedorId.isNotEmpty
                ? ficha.proveedorId
                : ficha.proveedorNombre,
          )
          .toSet()
          .length;
      estado = proveedores == 1
          ? 'Cargada por 1 proveedor'
          : 'Cargada por $proveedores proveedores';
    } else if (!tieneDoc) {
      color = kComprasRed;
      icon = Icons.cancel;
      estado = 'Falta';
    } else if (doc!.rechazado) {
      color = kComprasRed;
      icon = Icons.cancel;
      estado = 'Rechazado';
    } else if (faltaVigencia) {
      color = kComprasRed;
      icon = Icons.event_busy_outlined;
      estado = 'Falta vigencia';
    } else if (doc.aprobadoConRequerimientos) {
      color = const Color(0xFFD97706);
      icon = Icons.rule_folder_outlined;
      estado = 'Con requerimientos';
    } else if (doc.aprobado) {
      color = kComprasGreen;
      icon = Icons.verified;
      estado = 'Aprobado';
    } else {
      color = Colors.orange.shade800;
      icon = Icons.hourglass_top;
      estado = 'Pendiente Calidad';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            '$label · $estado',
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_unidad == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione la unidad de medida')),
      );
      return;
    }
    if (_categoria == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seleccione la categoría')));
      return;
    }
    if (isNew) {
      final marcaError = validarMarcasNuevoProducto(_marcasProducto);
      if (marcaError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(marcaError), backgroundColor: kComprasRed),
        );
        return;
      }
      final documentosError = validarDocumentosMarcasProducto(
        _marcasProducto,
        _todasMarcas,
      );
      if (documentosError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(documentosError),
            backgroundColor: kComprasRed,
          ),
        );
        return;
      }
    }

    final coincidencia = _buscarCoincidenciaProducto(
      codigo: _codigoCtrl.text,
      nombre: _nombreCtrl.text,
    );
    if (coincidencia != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ya existe un producto similar (${coincidencia.codigo} - ${coincidencia.nombre}). Revise antes de crear uno nuevo.',
          ),
          backgroundColor: kComprasRed,
        ),
      );
      return;
    }

    final textoProducto = '${_codigoCtrl.text} ${_nombreCtrl.text}';
    if (_categoria != 'Proteína' && _pareceProteina(textoProducto)) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: _comprasDialogTitle(
            dialogContext,
            'Posible producto de proteína',
            icon: Icons.warning_amber_rounded,
          ),
          content: const Text(
            'Detectamos palabras asociadas a proteína. Si aplica, seleccione la categoría Proteína para exigir la documentación correcta en recepción.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Revisar categoría'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (continuar != true) return;
    }

    setState(() => _guardando = true);
    try {
      final codigo = _codigoCtrl.text.trim().toUpperCase();
      final p = ProductoDoc(
        id: widget.existing?.id ?? '',
        empresaId: widget.empresaId,
        codigo: codigo,
        nombre: _normalizarNombre(_nombreCtrl.text),
        unidadMedida: _normalizarUM(_unidad!),
        categoria: _categoria!,
        esPerecedero: _perecedero,
        marcas: _marcasProducto,
        origen: _origen,
        fichaTecnica: widget.existing?.fichaTecnica,
        fichasTecnicasPorMarca: _fichasPorMarca,
        documentosAsociados: widget.existing?.documentosAsociados ?? const {},
        createdAt: widget.existing?.createdAt ?? Timestamp.now(),
      );
      await widget.svc.guardarProducto(p, isNew: isNew);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNew ? 'Producto creado' : 'Producto actualizado'),
            backgroundColor: kComprasGreen,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kComprasRed),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.inventory_2, color: Color(0xFF0277BD)),
                  const SizedBox(width: 8),
                  Text(
                    isNew ? 'Nuevo Producto' : 'Editar Producto',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Código — ingreso manual
              TextFormField(
                controller: _codigoCtrl,
                inputFormatters: const [_UpperCaseTextFormatter()],
                decoration: _inputDecoration('Código *').copyWith(
                  hintText: 'Ej: PRD-0001, CARNE-001',
                  prefixIcon: const Icon(Icons.qr_code, size: 18),
                  helperText: 'Se guardará en mayúsculas automáticamente',
                ),
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nombreCtrl,
                inputFormatters: const [_UpperCaseTextFormatter()],
                decoration: _inputDecoration(
                  'Nombre del producto *',
                ).copyWith(hintText: 'Ej: Carne De Res'),
                style: const TextStyle(fontFamily: _kFont, fontSize: 14),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _unidad,
                      decoration: _inputDecoration('Unidad de medida *'),
                      isExpanded: true,
                      items: kUnidadesMedida
                          .map(
                            (u) => DropdownMenuItem(
                              value: u,
                              child: Text(
                                u,
                                style: const TextStyle(fontFamily: _kFont),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _unidad = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _categoria,
                      decoration: _inputDecoration('Categoría *'),
                      isExpanded: true,
                      items: kCategoriasCompras
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c,
                                style: const TextStyle(fontFamily: _kFont),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _categoria = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: _perecedero,
                onChanged: (v) => setState(() => _perecedero = v),
                title: const Text(
                  'Es perecedero',
                  style: TextStyle(fontFamily: _kFont, fontSize: 14),
                ),
                activeColor: const Color(0xFF0277BD),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 14),
              // ── Origen Nacional / Importado ───────────────────────────────
              const Text(
                'Origen del producto',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _OrigenButton(
                      label: 'Nacional',
                      icon: Icons.home_work_outlined,
                      selected: _origen == 'NACIONAL',
                      color: Colors.green.shade700,
                      onTap: () => setState(() => _origen = 'NACIONAL'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OrigenButton(
                      label: 'Importado',
                      icon: Icons.flight_land,
                      selected: _origen == 'IMPORTADO',
                      color: Colors.purple.shade700,
                      onTap: () => setState(() => _origen = 'IMPORTADO'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const SizedBox(height: 20),
              const Text(
                'Documentos que se solicitarán en recepción',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kComprasPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: _DocumentosRecepcionPreview(categoria: _categoria),
              ),
              const SizedBox(height: 16),
              // ── Marcas vinculadas ─────────────────────────────────────────
              Row(
                children: [
                  const Icon(
                    Icons.label_important,
                    size: 16,
                    color: Color(0xFF1976D2),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Marcas del producto',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (_loadingMarcas)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_marcasProducto.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Sin marcas vinculadas',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 13,
                      color: Colors.blueGrey.shade400,
                    ),
                  ),
                )
              else
                ...List.generate(_marcasProducto.length, (i) {
                  final ref = _marcasProducto[i];
                  final marca = _marcaPorId(ref.marcaId);
                  final fichasProveedor = _fichasProveedorMarca(ref);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: const Color(0xFFE3F2FD),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(
                        color: Color(0xFF90CAF9),
                        width: 0.8,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.label,
                                size: 18,
                                color: Color(0xFF1976D2),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${ref.codigo} – ${ref.descripcion}',
                                  style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => setState(() {
                                  final removed = _marcasProducto.removeAt(i);
                                  _fichasPorMarca.remove(removed.marcaId);
                                }),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Documentos asociados a esta marca',
                            style: TextStyle(
                              fontFamily: _kFont,
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _documentoMarcaEstado(
                                marca,
                                'fichaTecnica',
                                'Ficha técnica',
                                fichasProveedor: fichasProveedor,
                              ),
                              _documentoMarcaEstado(
                                marca,
                                'registroSanitario',
                                'Registro sanitario',
                              ),
                            ],
                          ),
                          _resumenFichasProveedor(fichasProveedor),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _abrirDocumentosMarca(ref),
                              icon: const Icon(
                                Icons.folder_copy_outlined,
                                size: 18,
                              ),
                              label: const Text(
                                'Gestionar documentos de esta marca',
                                style: TextStyle(fontFamily: _kFont),
                              ),
                            ),
                          ),
                          if (!isNew)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () async {
                                  await _showComprasAdaptiveSheet(
                                    context: context,
                                    title: 'Fichas técnicas por proveedor',
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    backgroundColor: Colors.white,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(20),
                                      ),
                                    ),
                                    builder: (_) =>
                                        _FichasTecnicasPorMarcaSheet(
                                          empresaId: widget.empresaId,
                                          svc: widget.svc,
                                          productoId: widget.existing!.id,
                                          productoNombre:
                                              widget.existing!.nombre,
                                          productoCategoria:
                                              widget.existing!.categoria,
                                          marcaId: ref.marcaId,
                                          marcaNombre: ref.descripcion,
                                          userId: widget.userId,
                                        ),
                                  );
                                  if (mounted) await _loadFichasProveedor();
                                },
                                icon: const Icon(
                                  Icons.storefront_outlined,
                                  size: 17,
                                ),
                                label: const Text(
                                  'Fichas específicas por proveedor',
                                  style: TextStyle(fontFamily: _kFont),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              if (!_loadingMarcas)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final agregarExistente = OutlinedButton.icon(
                      onPressed: _agregarMarca,
                      icon: const Icon(Icons.playlist_add, size: 17),
                      label: const Text(
                        'Agregar existente',
                        style: TextStyle(fontFamily: _kFont),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1976D2),
                        side: const BorderSide(color: Color(0xFF1976D2)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    );
                    final crearNueva = FilledButton.icon(
                      onPressed: _crearMarcaDesdeProducto,
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text(
                        'Crear nueva marca',
                        style: TextStyle(fontFamily: _kFont),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    );

                    if (constraints.maxWidth < 430) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          agregarExistente,
                          const SizedBox(height: 8),
                          crearNueva,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: agregarExistente),
                        const SizedBox(width: 10),
                        Expanded(child: crearNueva),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _guardando ? 'Guardando...' : 'Guardar',
                    style: const TextStyle(fontFamily: _kFont),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0277BD),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentosRecepcionPreview extends StatelessWidget {
  final String? categoria;

  const _DocumentosRecepcionPreview({required this.categoria});

  @override
  Widget build(BuildContext context) {
    if (categoria == null) {
      return const SelectableText(
        'Seleccione una categoría para previsualizar los documentos obligatorios.',
        style: TextStyle(fontFamily: _kFont, fontSize: 12, height: 1.4),
      );
    }

    final labels = docsParaCategoria(
      categoria,
    ).map((key) => kDocRecepcionLabels[key] ?? key).toList();
    final text = labels.map((label) => '• $label').join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lista de documentos copiada')),
              );
            },
            icon: const Icon(Icons.content_copy, size: 15),
            label: const Text(
              'Copiar texto',
              style: TextStyle(fontFamily: _kFont, fontSize: 11),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          text,
          style: const TextStyle(
            fontFamily: _kFont,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FICHAS TÉCNICAS POR MARCA — gestión desde formulario de producto
// ══════════════════════════════════════════════════════════════════════════════

class _FichasTecnicasPorMarcaSheet extends StatelessWidget {
  final String empresaId;
  final ComprasService svc;
  final String productoId;
  final String productoNombre;
  final String productoCategoria;
  final String marcaId;
  final String marcaNombre;
  final String userId;

  const _FichasTecnicasPorMarcaSheet({
    required this.empresaId,
    required this.svc,
    required this.productoId,
    required this.productoNombre,
    required this.productoCategoria,
    required this.marcaId,
    required this.marcaNombre,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, ctrl) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.description, color: Color(0xFF0277BD)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productoNombre,
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (marcaNombre.isNotEmpty)
                        Text(
                          'Marca: $marcaNombre',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: StreamBuilder<List<FichaTecnicaDoc>>(
              stream: svc.streamFichasTecnicas(empresaId),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final fichas =
                    (snap.data ?? [])
                        .where(
                          (f) =>
                              f.productoId == productoId &&
                              f.marcaId == marcaId,
                        )
                        .toList()
                      ..sort(
                        (a, b) =>
                            a.proveedorNombre.compareTo(b.proveedorNombre),
                      );

                return ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                  children: [
                    ...fichas.map(
                      (f) => _FichaProveedorCard(
                        ficha: f,
                        svc: svc,
                        userId: userId,
                        empresaId: empresaId,
                        productoId: productoId,
                        productoNombre: productoNombre,
                        productoCategoria: productoCategoria,
                        marcaId: marcaId,
                        marcaNombre: marcaNombre,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _showComprasAdaptiveSheet(
                        context: ctx,
                        title: 'Agregar ficha técnica',
                        isScrollControlled: true,
                        useSafeArea: true,
                        backgroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        builder: (_) => _SubirFichaSheet(
                          empresaId: empresaId,
                          svc: svc,
                          productoId: productoId,
                          productoNombre: productoNombre,
                          productoCategoria: productoCategoria,
                          marcaId: marcaId,
                          marcaNombre: marcaNombre,
                          userId: userId,
                          fichasExistentes: fichas,
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text(
                        'Agregar ficha para otro proveedor',
                        style: TextStyle(fontFamily: _kFont),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF0277BD)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FichaProveedorCard extends StatelessWidget {
  final FichaTecnicaDoc ficha;
  final ComprasService svc;
  final String userId;
  final String empresaId;
  final String productoId;
  final String productoNombre;
  final String productoCategoria;
  final String marcaId;
  final String marcaNombre;

  const _FichaProveedorCard({
    required this.ficha,
    required this.svc,
    required this.userId,
    required this.empresaId,
    required this.productoId,
    required this.productoNombre,
    required this.productoCategoria,
    required this.marcaId,
    required this.marcaNombre,
  });

  Future<void> _cargarSoporte(
    BuildContext context,
    DocAdjunto documento,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    if (file.bytes!.length > 10 * 1024 * 1024) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El soporte supera el límite de 10 MB.'),
            backgroundColor: kComprasRed,
          ),
        );
      }
      return;
    }
    final ext = file.name.toLowerCase().split('.').last;
    try {
      await svc.agregarSoporteRequerimiento(
        empresaId: empresaId,
        tipo: 'ficha',
        entidadId: ficha.id,
        docKey: 'fichaTecnica',
        userId: userId,
        bytes: file.bytes!,
        nombre: file.name,
        contentType: ext == 'pdf' ? 'application/pdf' : 'image/$ext',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Soporte consolidado y enviado a revisión de Calidad.',
            ),
            backgroundColor: Color(0xFFD97706),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo adjuntar el soporte: $error'),
            backgroundColor: kComprasRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = ficha.documentoActual;
    Color badgeColor;
    String badgeLabel;
    if (doc == null || !doc.tieneDoc) {
      badgeColor = Colors.grey;
      badgeLabel = 'Sin ficha';
    } else if (doc.aprobadoConRequerimientos) {
      badgeColor = const Color(0xFFD97706);
      badgeLabel = 'Aprobada con requerimientos';
    } else if (doc.aprobado) {
      badgeColor = kComprasGreen;
      badgeLabel = 'Aprobada';
    } else if (doc.rechazado) {
      badgeColor = kComprasRed;
      badgeLabel = 'Rechazada';
    } else {
      badgeColor = const Color(0xFFB45309);
      badgeLabel = 'Pendiente';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ficha.proveedorNombre,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            if (doc != null && doc.tieneDoc) ...[
              const SizedBox(height: 4),
              Text(
                doc.nombre ?? '',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
              if (doc.observacionActualizacion?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Obs: ${doc.observacionActualizacion}',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Colors.black45,
                    ),
                  ),
                ),
              if (doc.rechazado && doc.observacionCalidad?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Motivo rechazo: ${doc.observacionCalidad}',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 11,
                      color: kComprasRed,
                    ),
                  ),
                ),
              if (doc.aprobadoConRequerimientos) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.requerimientoNota?.trim().isNotEmpty == true
                            ? doc.requerimientoNota!.trim()
                            : 'Calidad dejó un requerimiento abierto.',
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 11,
                          color: Color(0xFF78350F),
                        ),
                      ),
                      if (doc.requerimientoRequiereAdjunto &&
                          doc.requerimientoAbierto) ...[
                        const SizedBox(height: 7),
                        OutlinedButton.icon(
                          onPressed: () => _cargarSoporte(context, doc),
                          icon: const Icon(Icons.attach_file, size: 15),
                          label: Text(
                            doc.soportesRequerimiento.isEmpty
                                ? 'Adjuntar soporte solicitado'
                                : 'Adjuntar otro soporte',
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 11,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB45309),
                            side: const BorderSide(color: Color(0xFFF59E0B)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (doc != null && doc.tieneDoc)
                  TextButton.icon(
                    onPressed: () => _abrirUrl(context, doc.url),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text(
                      'Ver PDF',
                      style: TextStyle(fontFamily: _kFont, fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showComprasAdaptiveSheet(
                    context: context,
                    title: 'Actualizar ficha técnica',
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (_) => _SubirFichaSheet(
                      empresaId: empresaId,
                      svc: svc,
                      productoId: productoId,
                      productoNombre: productoNombre,
                      productoCategoria: productoCategoria,
                      marcaId: marcaId,
                      marcaNombre: marcaNombre,
                      userId: userId,
                      fichasExistentes: [],
                      fichaExistente: ficha,
                    ),
                  ),
                  icon: const Icon(
                    Icons.upload_file,
                    size: 14,
                    color: Color(0xFF0277BD),
                  ),
                  label: Text(
                    doc != null && doc.tieneDoc ? 'Actualizar' : 'Subir',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Color(0xFF0277BD),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
                // ── Botón eliminar ficha ───────────────────────────────────
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: kComprasRed,
                  ),
                  tooltip: 'Eliminar ficha técnica',
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: _comprasDialogTitle(
                          dialogContext,
                          'Eliminar ficha técnica',
                          icon: Icons.delete_outline,
                        ),
                        content: Text(
                          '¿Eliminar la ficha de "${ficha.proveedorNombre}"?\n'
                          'Esta acción no se puede deshacer.',
                          style: const TextStyle(fontFamily: _kFont),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: kComprasRed,
                            ),
                            child: const Text('Eliminar'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true || !context.mounted) return;
                    try {
                      await svc.eliminarFichaTecnica(ficha);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ficha técnica eliminada'),
                            backgroundColor: kComprasRed,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: kComprasRed,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SUBIR / ACTUALIZAR FICHA TÉCNICA — bottom sheet
// ══════════════════════════════════════════════════════════════════════════════

class _SubirFichaSheet extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final String productoId;
  final String productoNombre;
  final String productoCategoria;
  final String marcaId;
  final String marcaNombre;
  final String userId;

  /// Fichas ya existentes para el producto+marca (para validar unicidad proveedor).
  final List<FichaTecnicaDoc> fichasExistentes;

  /// Si se pasa, es actualización de la ficha existente.
  final FichaTecnicaDoc? fichaExistente;

  /// Tarea de corrección que debe pasar a revisión tras guardar esta ficha.
  final String? correccionTaskId;

  const _SubirFichaSheet({
    required this.empresaId,
    required this.svc,
    required this.productoId,
    required this.productoNombre,
    required this.productoCategoria,
    required this.marcaId,
    required this.marcaNombre,
    required this.userId,
    required this.fichasExistentes,
    this.fichaExistente,
    this.correccionTaskId,
  });

  @override
  State<_SubirFichaSheet> createState() => _SubirFichaSheetState();
}

class _SubirFichaSheetState extends State<_SubirFichaSheet> {
  final _obsCtrl = TextEditingController();
  bool get isUpdate => widget.fichaExistente != null;
  DateTime? _vigenteHasta;

  // Proveedor seleccionado (sólo para fichas nuevas)
  ProveedorDoc? _proveedor;
  List<ProveedorDoc> _proveedores = [];
  bool _loadingProvs = true;

  // Archivo
  String? _fileName;
  Uint8List? _fileBytes;
  bool _subiendo = false;

  // Web drag-and-drop
  bool _isDragging = false;
  StreamSubscription<bool>? _wDragSub;
  StreamSubscription<DroppedFile>? _wFileSub;

  @override
  void initState() {
    super.initState();
    _vigenteHasta = widget.fichaExistente?.documentoActual?.fechaVencimiento
        ?.toDate();
    _cargarProveedores();
    if (kIsWeb) {
      WebDragDrop.instance.enable();
      _wDragSub = WebDragDrop.instance.isDragging.listen((v) {
        if (mounted) setState(() => _isDragging = v);
      });
      _wFileSub = WebDragDrop.instance.droppedFile.listen(_onWebFileDrop);
    }
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    if (kIsWeb) WebDragDrop.instance.disable();
    _wDragSub?.cancel();
    _wFileSub?.cancel();
    super.dispose();
  }

  Future<void> _cargarProveedores() async {
    final snap = await FirebaseFirestore.instance
        .collection('TBL_COMPRAS_PROVEEDORES')
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    if (!mounted) return;
    setState(() {
      _proveedores =
          snap.docs.map((d) => ProveedorDoc.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.razonSocial.compareTo(b.razonSocial));
      // Pre-seleccionar si es actualización
      if (isUpdate) {
        try {
          _proveedor = _proveedores.firstWhere(
            (p) => p.id == widget.fichaExistente!.proveedorId,
          );
        } catch (_) {}
      }
      _loadingProvs = false;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    setState(() {
      _fileName = f.name;
      _fileBytes = f.bytes;
    });
    await _pedirVigenciaTrasSeleccionarArchivo();
  }

  // Recibe archivo arrastrado vía dart:html (stream global)
  Future<void> _onWebFileDrop(DroppedFile file) async {
    if (!mounted) return;
    final name = file.name;
    final ext = name.toLowerCase().split('.').last;
    if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Solo se permiten PDF, JPG o PNG',
              style: TextStyle(fontFamily: _kFont),
            ),
          ),
        );
      }
      return;
    }
    if (file.bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El archivo supera el límite de 10 MB',
              style: TextStyle(fontFamily: _kFont),
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      _fileName = name;
      _fileBytes = file.bytes;
    });
    await _pedirVigenciaTrasSeleccionarArchivo();
  }

  /// Maneja el drop desde el DropTarget nativo de desktop_drop.
  Future<void> _handleFichaWebDrop(DropDoneDetails details) async {
    if (!mounted || details.files.isEmpty) return;
    if (mounted) setState(() => _isDragging = false);
    final xFile = details.files.first;
    final name = xFile.name;
    final ext = name.toLowerCase().split('.').last;
    if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Solo se permiten PDF, JPG o PNG',
              style: TextStyle(fontFamily: _kFont),
            ),
          ),
        );
      }
      return;
    }
    final bytes = await xFile.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El archivo supera el límite de 10 MB',
              style: TextStyle(fontFamily: _kFont),
            ),
          ),
        );
      }
      return;
    }
    if (mounted)
      setState(() {
        _fileName = name;
        _fileBytes = bytes;
      });
    await _pedirVigenciaTrasSeleccionarArchivo();
  }

  Future<bool> _pedirVigenciaTrasSeleccionarArchivo() async {
    if (!mounted || _fileBytes == null) return false;
    final selected = await _solicitarVigenciaDespuesDeCargar(
      context,
      docKey: 'fichaTecnica',
      labels: kDocumentosAsociadosLabels,
      initialDate: _vigenteHasta,
    );
    if (selected == null) return false;
    if (mounted) setState(() => _vigenteHasta = selected);
    return true;
  }

  Widget _buildFileZone() {
    if (!kIsWeb) {
      return OutlinedButton.icon(
        onPressed: _subiendo ? null : _pickFile,
        icon: const Icon(Icons.attach_file, size: 16),
        label: Text(
          _fileName ?? 'Seleccionar PDF o imagen',
          style: const TextStyle(fontFamily: _kFont, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
      );
    }

    // Web: zona drag-and-drop + botón separado para abrir selector de archivo
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Si hay archivo seleccionado, mostrar preview en lugar de la zona
        if (_fileBytes != null)
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade300, width: 1.5),
            ),
            child: _buildFilePreview(),
          )
        else
          // Zona de arrastre
          SizedBox(
            height: 110,
            child: DropTarget(
              onDragEntered: (_) {
                if (mounted) setState(() => _isDragging = true);
              },
              onDragExited: (_) {
                if (mounted) setState(() => _isDragging = false);
              },
              onDragDone: _handleFichaWebDrop,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _isDragging
                      ? kComprasPrimary.withOpacity(0.07)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isDragging ? kComprasPrimary : Colors.grey.shade300,
                    width: _isDragging ? 2 : 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 34,
                      color: _isDragging
                          ? kComprasPrimary
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isDragging
                          ? '¡Suelta el archivo aquí!'
                          : 'Arrastra el archivo aquí',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _isDragging ? kComprasPrimary : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PDF · JPG · PNG · Máx. 10 MB',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        // Botón separado para abrir selector de archivo
        OutlinedButton.icon(
          onPressed: _subiendo ? null : _pickFile,
          icon: Icon(
            Icons.folder_open,
            size: 14,
            color: _subiendo ? Colors.grey : kComprasPrimary,
          ),
          label: Text(
            _fileBytes != null
                ? 'Cambiar archivo'
                : 'o seleccionar archivo (PDF/img)',
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              color: _subiendo ? Colors.grey : kComprasPrimary,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: _subiendo
                  ? Colors.grey.shade300
                  : kComprasPrimary.withOpacity(0.5),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildFilePreview() {
    final ext = (_fileName ?? '').split('.').last.toLowerCase();
    final isImg = ['jpg', 'jpeg', 'png'].contains(ext);
    return Row(
      children: [
        const SizedBox(width: 16),
        Icon(
          isImg ? Icons.image : Icons.picture_as_pdf,
          color: isImg ? Colors.blue.shade600 : Colors.red.shade600,
          size: 38,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _fileName ?? '',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                'Haz clic para cambiar',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(
            Icons.check_circle,
            color: Colors.green.shade600,
            size: 22,
          ),
        ),
      ],
    );
  }

  Future<void> _subir() async {
    if (!isUpdate && _proveedor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecciona un proveedor.',
            style: TextStyle(fontFamily: _kFont),
          ),
        ),
      );
      return;
    }
    if (isUpdate && _obsCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ingresa el motivo de la actualización.',
            style: TextStyle(fontFamily: _kFont),
          ),
        ),
      );
      return;
    }
    if (_fileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecciona un archivo PDF o imagen.',
            style: TextStyle(fontFamily: _kFont),
          ),
        ),
      );
      return;
    }
    if (_vigenteHasta == null &&
        !await _pedirVigenciaTrasSeleccionarArchivo()) {
      return;
    }

    setState(() => _subiendo = true);
    try {
      final ext = _fileName?.split('.').last.toLowerCase() ?? 'pdf';
      final contentType = ext == 'pdf' ? 'application/pdf' : 'image/$ext';
      final docSubido = await widget.svc.subirBytes(
        bytes: _fileBytes!,
        empresaId: widget.empresaId,
        carpeta: 'fichas_tecnicas',
        nombre: _fileName ?? 'ficha.pdf',
        contentType: contentType,
        pendienteCalidad:
            false, // guardarFichaTecnica marca pendiente_revision_calidad
      );
      // Registrar quién subió/reemplazó la ficha.
      final doc = prepararDocumentoPendienteCalidad(
        docSubido,
        subidoPor: widget.userId,
        fechaVencimiento: _vigenteHasta == null
            ? null
            : Timestamp.fromDate(_vigenteHasta!),
      );

      final prov = isUpdate
          ? ProveedorDoc(
              id: widget.fichaExistente!.proveedorId,
              empresaId: widget.empresaId,
              nit: '',
              razonSocial: widget.fichaExistente!.proveedorNombre,
              createdAt: Timestamp.now(),
            )
          : _proveedor!;

      final ficha = FichaTecnicaDoc(
        id: isUpdate ? widget.fichaExistente!.id : '',
        empresaId: widget.empresaId,
        proveedorId: prov.id,
        proveedorNombre: prov.razonSocial,
        productoId: widget.productoId,
        productoNombre: widget.productoNombre,
        productoCategoria: widget.productoCategoria,
        marcaId: widget.marcaId,
        marcaNombre: widget.marcaNombre,
        documentoActual: doc,
        documentoAprobado: isUpdate
            ? widget.fichaExistente!.documentoAprobado
            : null,
        historial: isUpdate ? widget.fichaExistente!.historial : [],
        creadoPor: widget.userId,
        createdAt: isUpdate
            ? widget.fichaExistente!.createdAt
            : Timestamp.now(),
      );

      await widget.svc.guardarFichaTecnica(
        ficha,
        isNew: !isUpdate,
        observacion: _obsCtrl.text.trim(),
        actualizadoPor: widget.userId,
      );
      final correccionTaskId = widget.correccionTaskId?.trim() ?? '';
      if (correccionTaskId.isNotEmpty) {
        await widget.svc.enviarTareaCorreccionARevision(
          taskId: correccionTaskId,
          subidoPor: widget.userId,
          nombreDocumento: doc.nombre ?? 'Ficha técnica corregida',
          urlDocumento: doc.url,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isUpdate
                ? 'Ficha actualizada. Pendiente de revisión de calidad.'
                : 'Ficha cargada. Pendiente de revisión de calidad.',
            style: const TextStyle(fontFamily: _kFont),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: $e',
            style: const TextStyle(fontFamily: _kFont),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            isUpdate ? 'Actualizar ficha técnica' : 'Agregar ficha técnica',
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.productoNombre}'
            '${widget.marcaNombre.isNotEmpty ? ' / ${widget.marcaNombre}' : ''}',
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 16),
          // Proveedor
          if (!isUpdate)
            _loadingProvs
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<ProveedorDoc>(
                    value: _proveedor,
                    decoration: const InputDecoration(
                      labelText: 'Proveedor *',
                      labelStyle: TextStyle(fontFamily: _kFont),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    isExpanded: true,
                    items: _proveedores
                        .where(
                          (p) => widget.fichasExistentes.every(
                            (f) => f.proveedorId != p.id,
                          ),
                        )
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(
                              p.razonSocial,
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _proveedor = v),
                  ),
          if (!isUpdate) const SizedBox(height: 12),
          if (isUpdate)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.store, size: 16, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(
                    widget.fichaExistente!.proveedorNombre,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          // Observación
          TextFormField(
            controller: _obsCtrl,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [_UpperCaseTextFormatter()],
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: isUpdate
                  ? 'Motivo de actualización *'
                  : 'Observación (opcional)',
              labelStyle: const TextStyle(fontFamily: _kFont),
              hintText: isUpdate
                  ? '¿Por qué se actualiza la ficha técnica?'
                  : 'Nota inicial sobre la ficha…',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            style: const TextStyle(fontFamily: _kFont, fontSize: 13),
          ),
          const SizedBox(height: 12),
          // Archivo (botón normal en móvil, zona drag-and-drop en web)
          _buildFileZone(),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _fileBytes == null
                ? null
                : _pedirVigenciaTrasSeleccionarArchivo,
            icon: const Icon(Icons.event_available_outlined, size: 17),
            label: Text(
              _vigenteHasta == null
                  ? 'Falta indicar “Vigente hasta”'
                  : 'Vigente hasta: ${DateFormat('dd/MM/yyyy').format(_vigenteHasta!)}',
              style: const TextStyle(fontFamily: _kFont, fontSize: 12),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0277BD),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _subiendo ? null : _subir,
              icon: _subiendo
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(
                _subiendo
                    ? 'Subiendo...'
                    : (isUpdate ? 'Actualizar ficha' : 'Subir ficha'),
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SELECTOR DE MARCA para ProductoFormSheet (bottom sheet con búsqueda)
// ══════════════════════════════════════════════════════════════════════════════

class _MarcaSelectorSheet extends StatefulWidget {
  final List<MarcaDoc> marcas;
  const _MarcaSelectorSheet({required this.marcas});
  @override
  State<_MarcaSelectorSheet> createState() => _MarcaSelectorSheetState();
}

class _MarcaSelectorSheetState extends State<_MarcaSelectorSheet> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.marcas
        : widget.marcas
              .where(
                (m) =>
                    m.descripcion.toLowerCase().contains(_q) ||
                    m.codigo.toLowerCase().contains(_q),
              )
              .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.label_important, color: Color(0xFF1976D2)),
              const SizedBox(width: 8),
              const Text(
                'Seleccionar Marca',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Buscar marca...',
              prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            style: const TextStyle(fontFamily: _kFont, fontSize: 13),
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final m = filtered[i];
              return ListTile(
                leading: const Icon(
                  Icons.label,
                  size: 18,
                  color: Color(0xFF1976D2),
                ),
                title: Text(
                  m.descripcion,
                  style: const TextStyle(fontFamily: _kFont, fontSize: 14),
                ),
                subtitle: Text(
                  m.codigo,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                onTap: () => Navigator.pop(context, m),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RECEPCIONES SCREEN — listado de recepciones
// ══════════════════════════════════════════════════════════════════════════════

class _RecepcionesScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final String userId;
  final bool puedeEliminar;

  const _RecepcionesScreen({
    required this.empresaId,
    required this.svc,
    required this.userId,
    this.puedeEliminar = false,
  });

  @override
  State<_RecepcionesScreen> createState() => _RecepcionesScreenState();
}

class _RecepcionesScreenState extends State<_RecepcionesScreen> {
  /// Ventana por defecto de Histórico y Rechazadas. Acordado en la reunión del
  /// 29/07/2026: estas pestañas crecen sin límite y traerlas completas
  /// sobrecarga la app, así que arrancan acotadas y el usuario amplía.
  static const int _diasPorDefecto = 60;

  late DateTime _desde;
  late DateTime _hasta;

  /// Stream memoizada: recrearla en cada build dispara "INTERNAL ASSERTION
  /// FAILED" en web (ver memoria del proyecto sobre listener churn).
  Stream<List<RecepcionDoc>>? _historicoRangoStream;
  Stream<List<RecepcionDoc>>? _rechazadasRangoStream;
  DateTime? _rangoStreamDesde;
  DateTime? _rangoStreamHasta;
  List<ComprasGrupoDoc> _gruposFiltro = [];
  String _grupoFiltro = '';

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _hasta = DateTime(hoy.year, hoy.month, hoy.day);
    _desde = _hasta.subtract(const Duration(days: _diasPorDefecto));
    _cargarGruposFiltro();
  }

  Future<void> _cargarGruposFiltro() async {
    final grupos = await widget.svc.getGruposCompras(widget.empresaId);
    if (!mounted) return;
    setState(() => _gruposFiltro = grupos);
  }

  Widget _filtroGrupoRecepcion() {
    if (_gruposFiltro.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: DropdownButtonFormField<String>(
        value: _grupoFiltro,
        decoration: InputDecoration(
          labelText: 'Filtrar por grupo de Compras',
          prefixIcon: const Icon(Icons.groups_2_outlined, size: 19),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos los grupos')),
          const DropdownMenuItem(
            value: '__sin_grupo__',
            child: Text('Recepciones anteriores sin grupo'),
          ),
          ..._gruposFiltro.map(
            (grupo) =>
                DropdownMenuItem(value: grupo.id, child: Text(grupo.nombre)),
          ),
        ],
        onChanged: (value) => setState(() => _grupoFiltro = value ?? ''),
      ),
    );
  }

  Stream<List<RecepcionDoc>> _streamRango(EstadoRecepcionCompras estado) {
    if (_rangoStreamDesde != _desde || _rangoStreamHasta != _hasta) {
      _rangoStreamDesde = _desde;
      _rangoStreamHasta = _hasta;
      _historicoRangoStream = null;
      _rechazadasRangoStream = null;
    }

    final actual = estado == EstadoRecepcionCompras.historico
        ? _historicoRangoStream
        : _rechazadasRangoStream;
    if (actual != null) return actual;

    final nuevo = widget.svc.streamRecepcionesPorRango(
      widget.empresaId,
      desde: _desde,
      hasta: _hasta,
    );
    if (estado == EstadoRecepcionCompras.historico) {
      _historicoRangoStream = nuevo;
    } else {
      _rechazadasRangoStream = nuevo;
    }
    return nuevo;
  }

  Future<void> _elegirRango() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _desde, end: _hasta),
      helpText: 'Rango de fechas de recepción',
      saveText: 'Aplicar',
    );
    if (picked == null) return;
    setState(() {
      _desde = picked.start;
      _hasta = picked.end;
    });
  }

  void _aplicarDias(int dias) {
    final hoy = DateTime.now();
    setState(() {
      _hasta = DateTime(hoy.year, hoy.month, hoy.day);
      _desde = _hasta.subtract(Duration(days: dias));
    });
  }

  /// Barra de rango para Histórico y Rechazadas.
  Widget _barraRango() {
    final fmt = DateFormat('dd/MM/yyyy');
    final dias = _hasta.difference(_desde).inDays;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.date_range, size: 16, color: kComprasPrimary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${fmt.format(_desde)} — ${fmt.format(_hasta)}',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _elegirRango,
                icon: const Icon(Icons.edit_calendar, size: 16),
                label: const Text(
                  'Cambiar',
                  style: TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: kComprasPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final opcion in const [30, 60, 90, 180, 365])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        opcion >= 365 ? '1 año' : '$opcion días',
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 11.5,
                        ),
                      ),
                      selected: dias == opcion,
                      onSelected: (_) => _aplicarDias(opcion),
                      selectedColor: kComprasPrimary.withValues(alpha: 0.14),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarEliminar(RecepcionDoc r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: _comprasDialogTitle(
          dialogContext,
          'Eliminar recepción',
          icon: Icons.delete_outline,
        ),
        content: Text(
          '¿Eliminar la recepción de "${r.razonSocial}" del ${DateFormat('dd/MM/yyyy').format(r.fecha.toDate())}?\n\nEsta acción no se puede deshacer.',
          style: const TextStyle(fontFamily: _kFont),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kComprasRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await widget.svc.eliminarRecepcion(r.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recepción eliminada'),
              backgroundColor: kComprasGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: kComprasRed,
            ),
          );
        }
      }
    }
  }

  Widget _buildRecepciones(
    EstadoRecepcionCompras estado, {
    required String emptyLabel,
    bool acotadoPorFecha = false,
  }) {
    // Pendientes NO se acota: ocultar trabajo por hacer detrás de un rango de
    // fechas sería peor que el costo de traerlo completo.
    final contenido = StreamBuilder<List<RecepcionDoc>>(
      stream: acotadoPorFecha
          ? _streamRango(estado)
          : widget.svc.streamRecepciones(widget.empresaId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error al cargar: ${snap.error}',
                style: const TextStyle(fontFamily: _kFont, color: Colors.red),
              ),
            ),
          );
        }
        final list = (snap.data ?? [])
            .where(
              (recepcion) =>
                  estadoRecepcionCompras(recepcion) == estado &&
                  (_grupoFiltro.isEmpty ||
                      (_grupoFiltro == '__sin_grupo__'
                          ? recepcion.grupoId.isEmpty
                          : recepcion.grupoId == _grupoFiltro)),
            )
            .toList();
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  estado == EstadoRecepcionCompras.rechazada
                      ? Icons.assignment_late_outlined
                      : Icons.local_shipping_outlined,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                Text(
                  emptyLabel,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    color: Colors.black45,
                  ),
                ),
                if (acotadoPorFecha) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'en el rango de fechas seleccionado',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 11.5,
                      color: Colors.black38,
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        return _comprasResponsiveList<RecepcionDoc>(
          items: list,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
          itemBuilder: (_, recepcion, i) =>
              _buildRecepcionCard(recepcion, estado),
        );
      },
    );

    if (!acotadoPorFecha) return contenido;
    return Column(
      children: [
        _barraRango(),
        const Divider(height: 1),
        Expanded(child: contenido),
      ],
    );
  }

  Widget _buildRecepcionCard(
    RecepcionDoc recepcion,
    EstadoRecepcionCompras estado,
  ) {
    final (estadoLabel, estadoColor) = switch (estado) {
      EstadoRecepcionCompras.pendiente => (
        'Pendiente',
        const Color(0xFFB45309),
      ),
      EstadoRecepcionCompras.historico => (
        'Finalizada',
        const Color(0xFF15803D),
      ),
      EstadoRecepcionCompras.rechazada => ('Rechazada', kComprasRed),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _NuevaRecepcionScreen(
              empresaId: widget.empresaId,
              svc: widget.svc,
              existing: recepcion,
              userId: widget.userId,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      recepcion.razonSocial,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  _Chip(estadoLabel, estadoColor),
                  const SizedBox(width: 8),
                  Text(
                    _fmtFecha(recepcion.fecha),
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text(
                    'NIT: ${recepcion.nit}',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  if (recepcion.ordenCompra.isNotEmpty)
                    Text(
                      'OC: ${recepcion.ordenCompra}',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  if (recepcion.bodega.isNotEmpty)
                    Text(
                      recepcion.bodega,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  if (recepcion.grupoNombre.isNotEmpty)
                    _Chip(recepcion.grupoNombre, const Color(0xFF6D28D9)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Chip(
                    '${recepcion.productos.length} producto${recepcion.productos.length == 1 ? '' : 's'}',
                    kComprasPrimary,
                  ),
                  const Spacer(),
                  if (widget.puedeEliminar)
                    IconButton(
                      onPressed: () => _confirmarEliminar(recepcion),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: kComprasRed,
                      ),
                      tooltip: 'Eliminar recepción',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    )
                  else ...[
                    Icon(
                      estado == EstadoRecepcionCompras.rechazada
                          ? Icons.build_circle_outlined
                          : Icons.lock_outline,
                      size: 16,
                      color: estadoColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      estado == EstadoRecepcionCompras.rechazada
                          ? 'Corregir documentos'
                          : 'Ver detalle',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: estadoColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right, color: estadoColor, size: 18),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: kComprasBg,
        appBar: AppBar(
          title: const Text(
            'Recepciones de mercancía',
            style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold),
          ),
          backgroundColor: kComprasPrimary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFFDBEAFE),
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Pendientes'),
              Tab(text: 'Histórico'),
              Tab(text: 'Rechazadas'),
            ],
          ),
        ),
        body: Column(
          children: [
            _filtroGrupoRecepcion(),
            if (_gruposFiltro.isNotEmpty) const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  _buildRecepciones(
                    EstadoRecepcionCompras.pendiente,
                    emptyLabel: 'No hay recepciones pendientes',
                  ),
                  _buildRecepciones(
                    EstadoRecepcionCompras.historico,
                    emptyLabel: 'No hay recepciones finalizadas',
                    acotadoPorFecha: true,
                  ),
                  _buildRecepciones(
                    EstadoRecepcionCompras.rechazada,
                    emptyLabel: 'No hay recepciones rechazadas',
                    acotadoPorFecha: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: kComprasPrimary,
          foregroundColor: Colors.white,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _NuevaRecepcionScreen(
                empresaId: widget.empresaId,
                svc: widget.svc,
                userId: widget.userId,
              ),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text(
            'Nueva Recepción',
            style: TextStyle(fontFamily: _kFont),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NUEVA RECEPCION SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class _RecepcionEntry {
  ProductoDoc? producto;
  MarcaDoc? marcaSeleccionada;
  String pendingMarcaId = ''; // para restaurar al editar
  Map<String, DocAdjunto> documentos = {};
  List<RecepcionLote> lotes = [];
  bool expandido = false;
  final observacionesCtrl = TextEditingController();

  _RecepcionEntry();

  void dispose() => observacionesCtrl.dispose();
}

class _NuevaRecepcionScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final RecepcionDoc? existing;
  final String userId;
  final String? correccionTaskId;
  final String? correccionDocKey;
  final String? correccionProductoId;

  const _NuevaRecepcionScreen({
    required this.empresaId,
    required this.svc,
    this.existing,
    required this.userId,
    this.correccionTaskId,
    this.correccionDocKey,
    this.correccionProductoId,
  });

  @override
  State<_NuevaRecepcionScreen> createState() => _NuevaRecepcionScreenState();
}

class _NuevaRecepcionScreenState extends State<_NuevaRecepcionScreen> {
  ProveedorDoc? _proveedor;
  final _provCtrl = TextEditingController();
  final _ordenCtrl = TextEditingController();
  List<_RecepcionEntry> _entries = [];
  List<ProveedorDoc> _proveedores = [];
  List<ProductoDoc> _productos = [];
  List<MarcaDoc> _marcas = [];
  List<FichaTecnicaDoc> _fichasTecnicas = [];
  List<String> _bodegas = [];
  List<ComprasGrupoDoc> _grupos = [];
  bool _guardando = false;
  bool _loadingProvs = true;
  bool _loadingBodegas = true;
  String? _bodegaSeleccionada;
  String? _grupoSeleccionado;
  bool _documentoCorreccionCargado = false;
  bool _correccionModificada = false;
  final Set<String> _documentosCorregibles = {};

  bool get isNew => widget.existing == null;
  bool get _esCorreccionDirigida =>
      (widget.correccionTaskId ?? '').trim().isNotEmpty &&
      (widget.correccionDocKey ?? '').trim().isNotEmpty;
  bool get _esRecepcionRechazada =>
      widget.existing != null &&
      estadoRecepcionCompras(widget.existing!) ==
          EstadoRecepcionCompras.rechazada;
  bool get _modoCorreccion =>
      !isNew && (_esRecepcionRechazada || _esCorreccionDirigida);
  bool get _modoLectura => !isNew && !_modoCorreccion;
  bool get _mostrarAccionGuardar =>
      isNew || (!_esCorreccionDirigida && _modoCorreccion);

  bool _esDocumentoCorreccion(int idx, String key) {
    if (!_esCorreccionDirigida || key != widget.correccionDocKey!.trim()) {
      return false;
    }
    final productoId = widget.correccionProductoId?.trim() ?? '';
    return productoId.isEmpty || _entries[idx].producto?.id == productoId;
  }

  bool _puedeEditarDocumento(int idx, String key) {
    if (isNew) return true;
    if (!_modoCorreccion || idx < 0 || idx >= _entries.length) return false;
    final productoId =
        _entries[idx].producto?.id ??
        (idx < (widget.existing?.productos.length ?? 0)
            ? widget.existing!.productos[idx].productoId
            : '');
    final clave = claveDocumentoRecepcion(productoId, key);
    if (!_documentosCorregibles.contains(clave)) return false;
    return !_esCorreccionDirigida || _esDocumentoCorreccion(idx, key);
  }

  Future<void> _enviarCorreccionARevision(RecepcionDoc recepcion) async {
    final taskId = widget.correccionTaskId?.trim() ?? '';
    final docKey = widget.correccionDocKey?.trim() ?? '';
    if (taskId.isEmpty || docKey.isEmpty) return;
    final productoId = widget.correccionProductoId?.trim() ?? '';
    for (final producto in recepcion.productos) {
      if (productoId.isNotEmpty && producto.productoId != productoId) continue;
      final doc = producto.documentos[docKey];
      if (doc?.tieneDoc == true) {
        await widget.svc.enviarTareaCorreccionARevision(
          taskId: taskId,
          subidoPor: widget.userId,
          nombreDocumento: doc!.nombre ?? 'Documento corregido',
          urlDocumento: doc.url,
        );
        return;
      }
    }
    throw StateError(
      'No se encontró el documento corregido para enviar a Calidad.',
    );
  }

  Future<void> _persistirCorreccionRecepcion(
    int idx,
    String key,
    DocAdjunto doc,
  ) async {
    if (!_esDocumentoCorreccion(idx, key) || widget.existing == null) return;
    final productoId =
        _entries[idx].producto?.id ??
        (widget.correccionProductoId?.trim() ?? '');
    if (productoId.isEmpty) {
      throw StateError('No se encontró el producto del documento corregido.');
    }
    await widget.svc.actualizarDocRecepcion(
      recepcionId: widget.existing!.id,
      productoId: productoId,
      docKey: key,
      doc: doc,
    );
    await widget.svc.enviarTareaCorreccionARevision(
      taskId: widget.correccionTaskId!.trim(),
      subidoPor: widget.userId,
      nombreDocumento: doc.nombre ?? 'Documento corregido',
      urlDocumento: doc.url,
    );
    if (!mounted) return;
    setState(() => _documentoCorreccionCargado = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Documento corregido. La recepción volvió a revisión de Calidad.',
        ),
        backgroundColor: kComprasGreen,
      ),
    );
    Navigator.pop(context, true);
  }

  /// Busca una ficha disponible para la entrada. La recepción no se bloquea
  /// mientras Calidad revisa una versión nueva.
  FichaTecnicaDoc? _fichaParaEntry(_RecepcionEntry e) {
    if (_proveedor == null || e.producto == null) return null;
    final ficha = fichaDisponibleParaRecepcion(
      fichas: _fichasTecnicas,
      proveedorId: _proveedor!.id,
      productoId: e.producto!.id,
      marcaId: e.marcaSeleccionada?.id ?? '',
    );
    if (ficha != null) return ficha;

    final marca = e.marcaSeleccionada;
    final docMarca = marca?.documentosAsociados['fichaTecnica'];
    if (marca == null || docMarca?.tieneDoc != true) return null;
    return FichaTecnicaDoc(
      id: 'marca:${marca.id}',
      empresaId: widget.empresaId,
      proveedorId: _proveedor!.id,
      proveedorNombre: _proveedor!.razonSocial,
      productoId: e.producto!.id,
      productoNombre: e.producto!.nombre,
      marcaId: marca.id,
      marcaNombre: marca.descripcion,
      documentoActual: docMarca,
      documentoAprobado: docMarca!.aprobado ? docMarca : null,
      creadoPor: docMarca.subidoPor ?? widget.userId,
      createdAt: marca.createdAt,
    );
  }

  void _sincronizarFichaDisponible(int idx) {
    if (idx < 0 || idx >= _entries.length) return;
    final entry = _entries[idx];
    final ficha = _fichaParaEntry(entry);
    final disponible = ficha?.documentoAprobado ?? ficha?.documentoActual;
    if (disponible?.tieneDoc == true) {
      entry.documentos['fichaTecnica'] = disponible!;
    } else {
      // Evita conservar la ficha de otro proveedor/producto/marca.
      entry.documentos.remove('fichaTecnica');
    }
  }

  @override
  void initState() {
    super.initState();
    if (!isNew) {
      final r = widget.existing!;
      _ordenCtrl.text = r.ordenCompra;
      _bodegaSeleccionada = r.bodega.isEmpty ? null : r.bodega;
      _grupoSeleccionado = r.grupoId.isEmpty ? null : r.grupoId;
      _entries = r.productos.map((rp) {
        final e = _RecepcionEntry();
        e.pendingMarcaId = rp.marcaId;
        e.documentos = Map.from(rp.documentos);
        e.lotes = List.from(rp.lotes);
        e.observacionesCtrl.text = rp.observaciones;
        return e;
      }).toList();
      _documentosCorregibles.addAll(documentosRechazadosRecepcion(r).keys);
    }
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    try {
      final bodegasFuture = widget.svc.getBodegasEmpresa(widget.empresaId);
      final gruposFuture = widget.svc.getGruposCompras(widget.empresaId);
      final usuarioFuture = FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      // Sin orderBy para evitar requerir índice compuesto en Firestore.
      // El ordenamiento se hace en cliente.
      final pSnap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_PROVEEDORES')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      final prSnap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_PRODUCTOS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      final mSnap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_MARCAS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();

      if (!mounted) return;

      final provs =
          pSnap.docs
              .map((d) => ProveedorDoc.fromMap(d.id, d.data()))
              .where(
                (proveedor) =>
                    proveedor.activo ||
                    (!isNew && proveedor.id == widget.existing?.proveedorId),
              )
              .toList()
            ..sort((a, b) => a.razonSocial.compareTo(b.razonSocial));

      final prods =
          prSnap.docs.map((d) => ProductoDoc.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.nombre.compareTo(b.nombre));

      final marcas =
          mSnap.docs.map((d) => MarcaDoc.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.descripcion.compareTo(b.descripcion));

      final fichas = await widget.svc.getFichasTecnicas(widget.empresaId);
      final bodegas = await bodegasFuture;
      final todosLosGrupos = await gruposFuture;
      final usuario = await usuarioFuture;
      final gruposPorEmpresa = usuario.data()?['gruposComprasPorEmpresa'];
      final asignadosRaw = gruposPorEmpresa is Map
          ? gruposPorEmpresa[widget.empresaId]
          : null;
      final gruposAsignados = asignadosRaw is Iterable
          ? asignadosRaw.map((value) => value.toString()).toSet()
          : <String>{};
      var grupos = gruposAsignados.isEmpty
          ? todosLosGrupos
          : todosLosGrupos
                .where(
                  (grupo) =>
                      gruposAsignados.contains(grupo.id) ||
                      gruposAsignados.contains(grupo.nombre),
                )
                .toList();
      if (!isNew &&
          _grupoSeleccionado != null &&
          grupos.every((grupo) => grupo.id != _grupoSeleccionado)) {
        final existente = todosLosGrupos.where(
          (grupo) => grupo.id == _grupoSeleccionado,
        );
        if (existente.isNotEmpty) grupos = [...grupos, existente.first];
      }

      setState(() {
        _proveedores = provs;
        _productos = prods;
        _marcas = marcas;
        _fichasTecnicas = fichas;
        _bodegas = bodegas;
        _grupos = grupos;
        if (isNew && _grupos.length == 1) {
          _grupoSeleccionado = _grupos.first.id;
        }
        _loadingBodegas = false;

        if (!isNew) {
          final r = widget.existing!;
          try {
            _proveedor = _proveedores.firstWhere((p) => p.id == r.proveedorId);
            _provCtrl.text = _proveedor?.razonSocial ?? r.razonSocial;
          } catch (_) {
            _provCtrl.text = r.razonSocial;
          }
          for (int i = 0; i < _entries.length && i < r.productos.length; i++) {
            final rp = r.productos[i];
            // Restaurar producto
            try {
              _entries[i].producto = _productos.firstWhere(
                (p) => p.id == rp.productoId,
              );
            } catch (_) {}
            // Restaurar marca
            if (_entries[i].pendingMarcaId.isNotEmpty) {
              try {
                _entries[i].marcaSeleccionada = _marcas.firstWhere(
                  (m) => m.id == _entries[i].pendingMarcaId,
                );
              } catch (_) {}
            }
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: kComprasRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingProvs = false;
          _loadingBodegas = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _provCtrl.dispose();
    _ordenCtrl.dispose();
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  List<DropdownMenuItem<String>> _buildBodegaDropdownItems() {
    final items = _bodegas
        .map(
          (bodega) => DropdownMenuItem<String>(
            value: bodega,
            child: Text(
              bodega,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        )
        .toList();

    final selected = _bodegaSeleccionada;
    final exists = _bodegas.contains(selected);
    if (selected != null && selected.isNotEmpty && !exists) {
      items.add(
        DropdownMenuItem<String>(
          value: selected,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selected,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Destino existente en esta recepción',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return items;
  }

  Future<void> _guardar() async {
    if (_modoLectura) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta recepción está cerrada. Solo se habilita si Calidad rechaza un documento.',
          ),
        ),
      );
      return;
    }
    if (_modoCorreccion && !_correccionModificada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reemplaza los documentos rechazados antes de reenviar.',
          ),
          backgroundColor: kComprasRed,
        ),
      );
      return;
    }
    if (_proveedor == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seleccione un proveedor')));
      return;
    }
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregue al menos un producto')),
      );
      return;
    }
    if ((_bodegaSeleccionada ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione la bodega de destino')),
      );
      return;
    }
    if (_grupos.isNotEmpty && (_grupoSeleccionado ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione el grupo de la recepción')),
      );
      return;
    }
    final sinProducto = _entries.any((e) => e.producto == null);
    if (sinProducto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione el producto en cada fila')),
      );
      return;
    }

    // Marca obligatoria para TODOS los productos
    final sinMarca = _entries.any(
      (e) => e.producto != null && e.marcaSeleccionada == null,
    );
    if (sinMarca) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cada producto debe tener una marca seleccionada. Seleccione o cree una marca para continuar.',
          ),
          backgroundColor: kComprasRed,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    for (final entry in _entries) {
      final errorLotes = validarLotesRecepcion(entry.lotes);
      if (errorLotes != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${entry.producto?.nombre ?? 'Producto'}: $errorLotes',
            ),
          ),
        );
        return;
      }
      final vigenciasError = validarVigenciasDocumentales(
        entry.documentos,
        labels: kDocRecepcionLabels,
      );
      if (vigenciasError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${entry.producto?.nombre ?? 'Producto'}: $vigenciasError',
            ),
            backgroundColor: kComprasRed,
          ),
        );
        return;
      }
    }
    // Ficha técnica obligatoria por producto
    final sinFicha = _entries.any(
      (e) =>
          e.producto != null && e.documentos['fichaTecnica']?.tieneDoc != true,
    );
    if (sinFicha) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cada producto debe tener una ficha técnica cargada antes de guardar.',
          ),
          backgroundColor: kComprasRed,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      final productos = _entries.map((e) {
        return RecepcionProducto(
          productoId: e.producto!.id,
          nombre: e.producto!.nombre,
          categoria: e.producto!.categoria,
          marcaId: e.marcaSeleccionada?.id ?? '',
          marca: e.marcaSeleccionada?.descripcion ?? '',
          origen: e.producto!.origen,
          documentos: e.documentos,
          lotes: e.lotes,
          observaciones: e.observacionesCtrl.text.trim(),
        );
      }).toList();

      final grupoSeleccionado = _grupos.where(
        (grupo) => grupo.id == _grupoSeleccionado,
      );
      final r = RecepcionDoc(
        id: widget.existing?.id ?? '',
        empresaId: widget.empresaId,
        fecha: widget.existing?.fecha ?? Timestamp.now(),
        proveedorId: _proveedor!.id,
        nit: _proveedor!.nit,
        razonSocial: _proveedor!.razonSocial,
        ordenCompra: _ordenCtrl.text.trim(),
        bodega: _bodegaSeleccionada?.trim() ?? '',
        grupoId: _grupoSeleccionado ?? '',
        grupoNombre: grupoSeleccionado.isNotEmpty
            ? grupoSeleccionado.first.nombre
            : (widget.existing?.grupoNombre ?? ''),
        productos: productos,
        productoIds: productos.map((p) => p.productoId).toList(),
        creadoPor: widget.existing?.creadoPor ?? widget.userId,
        createdAt: widget.existing?.createdAt ?? Timestamp.now(),
      );
      if (isNew) {
        await widget.svc.guardarRecepcion(r);
      } else {
        final correcciones = <String, DocAdjunto>{};
        for (var idx = 0; idx < _entries.length; idx++) {
          final productoId =
              _entries[idx].producto?.id ??
              (idx < widget.existing!.productos.length
                  ? widget.existing!.productos[idx].productoId
                  : '');
          for (final docKey in _entries[idx].documentos.keys) {
            final clave = claveDocumentoRecepcion(productoId, docKey);
            if (_documentosCorregibles.contains(clave)) {
              correcciones[clave] = _entries[idx].documentos[docKey]!;
            }
          }
        }
        await widget.svc.reenviarRecepcionCorregida(
          recepcionId: widget.existing!.id,
          userId: widget.userId,
          correcciones: correcciones,
        );
      }
      if (_documentoCorreccionCargado) {
        await _enviarCorreccionARevision(r);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isNew
                  ? 'Recepción guardada y cerrada. Quedó enviada a Calidad.'
                  : 'Correcciones enviadas. La recepción volvió a revisión de Calidad.',
            ),
            backgroundColor: kComprasGreen,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kComprasRed),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _agregarProducto() {
    setState(() => _entries.add(_RecepcionEntry()));
  }

  void _eliminarEntrada(int idx) {
    setState(() => _entries.removeAt(idx));
  }

  Future<void> _seleccionarProducto(int idx) async {
    // Filtrar productos según las categorías del proveedor seleccionado
    final productosFiltrados =
        (_proveedor == null || _proveedor!.categorias.isEmpty)
        ? _productos
        : _productos
              .where((p) => _proveedor!.categorias.contains(p.categoria))
              .toList();

    final seleccionado = await _showComprasAdaptiveSheet<ProductoDoc>(
      context: context,
      title: 'Seleccionar producto',
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProductoSelectorSheet(
        productos: productosFiltrados,
        categoriasFiltradas: _proveedor?.categorias ?? [],
      ),
    );
    if (seleccionado != null) {
      setState(() {
        _entries[idx].producto = seleccionado;
        _entries[idx].marcaSeleccionada = null;
        _entries[idx].documentos.clear();
        _entries[idx].lotes.clear();
        _entries[idx].expandido = true;
      });
      // Abrir selector de marca inmediatamente
      await _seleccionarMarcaParaEntry(idx);
    }
  }

  Future<void> _seleccionarMarcaParaEntry(int idx) async {
    if (idx >= _entries.length) return;
    final entry = _entries[idx];
    if (entry.producto == null) return;
    final producto = entry.producto!;

    final linkedIds = producto.marcas.map((r) => r.marcaId).toSet();
    final disponibles = _marcas.where((m) => linkedIds.contains(m.id)).toList();

    final result = await showDialog<_MarcaDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MarcaSelectorDialog(
        producto: producto,
        marcasDisponibles: disponibles,
        empresaId: widget.empresaId,
        svc: widget.svc,
      ),
    );

    if (!mounted || result == null) return;

    if (result.nuevaMarca != null) {
      final nuevaMarca = result.nuevaMarca!;
      setState(() {
        _marcas.add(nuevaMarca);
        _marcas.sort((a, b) => a.descripcion.compareTo(b.descripcion));
        // Actualizar el producto localmente para reflejar la nueva marca vinculada
        final ref = MarcaRef(
          marcaId: nuevaMarca.id,
          codigo: nuevaMarca.codigo,
          descripcion: nuevaMarca.descripcion,
        );
        final prodIdx = _productos.indexWhere((p) => p.id == producto.id);
        if (prodIdx >= 0) {
          _productos[prodIdx] = _productos[prodIdx].copyWith(
            marcas: [..._productos[prodIdx].marcas, ref],
          );
          _entries[idx].producto = _productos[prodIdx];
        }
        _entries[idx].marcaSeleccionada = nuevaMarca;
        _sincronizarFichaDisponible(idx);
      });
    } else if (result.seleccionada != null) {
      setState(() {
        _entries[idx].marcaSeleccionada = result.seleccionada;
        _sincronizarFichaDisponible(idx);
      });
    }
  }

  Future<RecepcionLote?> _pedirLote({RecepcionLote? existente}) async {
    final numeroCtrl = TextEditingController(text: existente?.numero ?? '');
    DateTime? fecha = existente?.fecha?.toDate();
    try {
      return await showDialog<RecepcionLote>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: _comprasDialogTitle(
              dialogContext,
              existente == null ? 'Agregar lote' : 'Editar lote',
              icon: Icons.qr_code_2,
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: numeroCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: const [_UpperCaseTextFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Número de lote *',
                      hintText: 'Ej: L-2026-001',
                      prefixIcon: Icon(Icons.qr_code_2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: fecha ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (selected != null) {
                        setDialogState(() => fecha = selected);
                      }
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      fecha == null
                          ? 'Agregar fecha del lote (opcional)'
                          : 'Fecha: ${DateFormat('dd/MM/yyyy').format(fecha!)}',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final numero = numeroCtrl.text.trim().toUpperCase();
                  if (numero.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ingrese el número de lote.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    RecepcionLote(
                      numero: numero,
                      fecha: fecha == null ? null : Timestamp.fromDate(fecha!),
                    ),
                  );
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      );
    } finally {
      numeroCtrl.dispose();
    }
  }

  Future<void> _agregarLote(int idx) async {
    final lote = await _pedirLote();
    if (!mounted || lote == null) return;
    final nuevos = [..._entries[idx].lotes, lote];
    final error = validarLotesRecepcion(nuevos);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _entries[idx].lotes = nuevos);
  }

  Future<void> _editarLote(int idx, int loteIdx) async {
    final lote = await _pedirLote(existente: _entries[idx].lotes[loteIdx]);
    if (!mounted || lote == null) return;
    final nuevos = [..._entries[idx].lotes]..[loteIdx] = lote;
    final error = validarLotesRecepcion(nuevos);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _entries[idx].lotes = nuevos);
  }

  void _eliminarLote(int idx, int loteIdx) {
    setState(() => _entries[idx].lotes.removeAt(loteIdx));
  }

  Future<void> _adjuntarDocProducto(int idx, String key) async {
    if (!_puedeEditarDocumento(idx, key)) return;
    final p = _entries[idx].producto;
    final nombreSug =
        '${_proveedor?.nit ?? ''}_${p?.nombre ?? 'prod'}_${kDocRecepcionLabels[key] ?? key}';
    final doc = await _mostrarEscaneador(
      context,
      empresaId: widget.empresaId,
      carpeta: 'recepciones',
      nombreSugerido: nombreSug,
      svc: widget.svc,
      userId: widget.userId,
    );
    if (doc != null) {
      DateTime? vigencia;
      if (documentoRequiereVigencia(key) && mounted) {
        vigencia = await _solicitarVigenciaDespuesDeCargar(
          context,
          docKey: key,
          labels: kDocRecepcionLabels,
        );
      }
      if (!mounted) return;
      // Registrar quién subió el documento (para mostrar el nombre en la
      // revisión de Calidad y para asignar la tarea de corrección si se rechaza).
      final docFinal = doc.copyWith(
        subidoPor: widget.userId,
        estadoCalidad: estadoInicialDocumentoRecepcion(key),
        observacionCalidad: '',
        observacionActualizacion: _entries[idx].observacionesCtrl.text.trim(),
        fechaVencimiento: vigencia == null
            ? null
            : Timestamp.fromDate(vigencia),
        clearFechaVencimiento: vigencia == null,
      );
      setState(() {
        _entries[idx].documentos[key] = docFinal;
        if (_modoCorreccion) {
          _correccionModificada = true;
        }
        if (_esDocumentoCorreccion(idx, key)) {
          _documentoCorreccionCargado = true;
        }
      });
      try {
        await _persistirCorreccionRecepcion(idx, key, docFinal);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'El documento se cargó, pero falta enviarlo a Calidad: $e',
            ),
            backgroundColor: kComprasRed,
          ),
        );
      }
    }
  }

  void _onDateChangedDoc(int idx, String key, DateTime? date) {
    if (idx < 0 || idx >= _entries.length || !_puedeEditarDocumento(idx, key)) {
      return;
    }
    setState(() {
      final current = _entries[idx].documentos[key] ?? const DocAdjunto();
      _entries[idx].documentos[key] = current.copyWith(
        fechaVencimiento: date != null ? Timestamp.fromDate(date) : null,
        clearFechaVencimiento: date == null,
      );
      if (_modoCorreccion) _correccionModificada = true;
    });
  }

  Widget _buildEstadoFlujoRecepcion() {
    if (isNew) {
      return _RecepcionFlowBanner(
        icon: Icons.edit_note_rounded,
        color: kComprasPrimary,
        title: '1. Registra y revisa la recepción',
        message:
            'Al guardar, la recepción se cerrará y quedará enviada a Calidad. Después no podrás agregar ni cambiar documentos.',
        steps: const ['Captura', 'Revisión de Calidad', 'Finalizada'],
        activeStep: 0,
      );
    }
    if (_modoCorreccion) {
      return _RecepcionFlowBanner(
        icon: Icons.build_circle_outlined,
        color: kComprasRed,
        title: 'Corrección habilitada por Calidad',
        message: _esCorreccionDirigida
            ? 'Reemplaza únicamente el documento señalado en rojo. Al cargarlo, la recepción se cerrará y volverá automáticamente a Calidad.'
            : 'Los datos, productos y lotes están bloqueados. Reemplaza todos los documentos señalados en rojo y envía las correcciones.',
        steps: const ['Recepción cerrada', 'Corrección', 'Nueva revisión'],
        activeStep: 1,
      );
    }
    final historico =
        estadoRecepcionCompras(widget.existing!) ==
        EstadoRecepcionCompras.historico;
    return _RecepcionFlowBanner(
      icon: historico ? Icons.verified_outlined : Icons.lock_outline,
      color: historico ? kComprasGreen : const Color(0xFFB45309),
      title: historico
          ? 'Recepción finalizada · solo lectura'
          : 'Recepción cerrada · en revisión de Calidad',
      message: historico
          ? 'La recepción terminó su ciclo. Puedes consultar los datos y documentos, pero no modificarlos.'
          : 'No se pueden agregar productos ni documentos. Si Calidad rechaza un soporte, se habilitará únicamente su corrección.',
      steps: const ['Captura cerrada', 'Revisión de Calidad', 'Finalizada'],
      activeStep: historico ? 2 : 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fechaDisplay = widget.existing != null
        ? _fmtFechaHora(widget.existing!.fecha)
        : _fmtFechaHora(Timestamp.now());

    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: Text(
          isNew
              ? 'Nueva recepción'
              : _modoCorreccion
              ? 'Corregir recepción'
              : 'Detalle de recepción',
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
        actions: [
          if (_guardando && _mostrarAccionGuardar)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else if (_mostrarAccionGuardar)
            TextButton(
              onPressed: _guardar,
              child: Text(
                isNew ? 'Guardar y cerrar' : 'Enviar correcciones',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: _kFont,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: _loadingProvs
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEstadoFlujoRecepcion(),
                  const SizedBox(height: 16),
                  // ── Encabezado ──────────────────────────
                  _SectionHeader(
                    'Encabezado',
                    Icons.info_outline,
                    kComprasPrimary,
                  ),
                  const SizedBox(height: 12),
                  // Fecha (solo lectura)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Fecha: $fechaDisplay',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Proveedor (typeahead)
                  TypeAheadField<ProveedorDoc>(
                    textFieldConfiguration: TextFieldConfiguration(
                      controller: _provCtrl,
                      enabled: isNew,
                      decoration: _inputDecoration('Proveedor *').copyWith(
                        hintText: 'Buscar proveedor...',
                        prefixIcon: const Icon(Icons.business, size: 18),
                      ),
                      style: const TextStyle(fontFamily: _kFont, fontSize: 14),
                    ),
                    suggestionsCallback: (pattern) => _proveedores
                        .where(
                          (p) =>
                              p.razonSocial.toLowerCase().contains(
                                pattern.toLowerCase(),
                              ) ||
                              p.nit.contains(pattern),
                        )
                        .toList(),
                    itemBuilder: (ctx, p) => ListTile(
                      dense: true,
                      title: Text(
                        p.razonSocial,
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        'NIT: ${p.nit}',
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    onSuggestionSelected: (p) => setState(() {
                      _proveedor = p;
                      _provCtrl.text = p.razonSocial;
                      for (var i = 0; i < _entries.length; i++) {
                        _sincronizarFichaDisponible(i);
                      }
                    }),
                    noItemsFoundBuilder: (_) => const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Sin resultados',
                        style: TextStyle(fontFamily: _kFont),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // NIT (auto)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.badge,
                          size: 16,
                          color: Colors.black38,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'NIT: ${_proveedor?.nit ?? '(Seleccione proveedor)'}',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 13,
                            color: _proveedor != null
                                ? Colors.black87
                                : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ordenCtrl,
                    readOnly: !isNew,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: const [_UpperCaseTextFormatter()],
                    decoration: _inputDecoration(
                      'Orden de Compra',
                    ).copyWith(hintText: 'OC-2024-001'),
                    style: const TextStyle(fontFamily: _kFont, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _bodegaSeleccionada,
                    isExpanded: true,
                    menuMaxHeight: 360,
                    decoration:
                        _inputDecoration(
                          'Bodega / Ubicación de destino',
                        ).copyWith(
                          helperText: _loadingBodegas
                              ? 'Cargando bodegas de la empresa activa...'
                              : _bodegas.isEmpty &&
                                    (_bodegaSeleccionada ?? '').isEmpty
                              ? 'Esta empresa no tiene bodegas configuradas.'
                              : 'Solo se muestran bodegas de la empresa activa.',
                          prefixIcon: _loadingBodegas
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.warehouse, size: 18),
                        ),
                    items: _buildBodegaDropdownItems(),
                    onChanged:
                        !isNew ||
                            _loadingBodegas ||
                            (_bodegas.isEmpty &&
                                (_bodegaSeleccionada ?? '').isEmpty)
                        ? null
                        : (value) =>
                              setState(() => _bodegaSeleccionada = value),
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 13,
                      color: Color(0xFF0F172A),
                    ),
                    hint: const Text(
                      'Selecciona la bodega',
                      style: TextStyle(fontFamily: _kFont, fontSize: 13),
                    ),
                  ),
                  if (_grupos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _grupoSeleccionado,
                      isExpanded: true,
                      decoration: _inputDecoration('Grupo de recepción *').copyWith(
                        prefixIcon: const Icon(
                          Icons.groups_2_outlined,
                          size: 18,
                        ),
                        helperText:
                            'Los grupos disponibles se asignan desde Administración > Membresía.',
                      ),
                      items: _grupos
                          .map(
                            (grupo) => DropdownMenuItem<String>(
                              value: grupo.id,
                              child: Text(
                                grupo.nombre,
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: isNew
                          ? (value) =>
                                setState(() => _grupoSeleccionado = value)
                          : null,
                    ),
                  ],
                  const SizedBox(height: 24),
                  // ── Productos ────────────────────────────
                  _SectionHeader(
                    'Productos recibidos',
                    Icons.inventory,
                    kComprasPrimary,
                  ),
                  const SizedBox(height: 12),
                  ..._entries.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final e = entry.value;
                    return _ProductoEntryCard(
                      idx: idx,
                      entry: e,
                      onSelectProducto: () => _seleccionarProducto(idx),
                      onRemove: () => _eliminarEntrada(idx),
                      onAdjuntarDoc: (key) => _adjuntarDocProducto(idx, key),
                      onVerDoc: (key) =>
                          _abrirUrl(context, e.documentos[key]?.url),
                      onChanged: () => setState(() {}),
                      todasMarcas: _marcas,
                      onMarcaChanged: (m) => setState(() {
                        _entries[idx].marcaSeleccionada = m;
                        _sincronizarFichaDisponible(idx);
                      }),
                      fichaTecnicaDoc: _fichaParaEntry(e),
                      onAgregarLote: () => _agregarLote(idx),
                      onEditarLote: (loteIdx) => _editarLote(idx, loteIdx),
                      onEliminarLote: (loteIdx) => _eliminarLote(idx, loteIdx),
                      onWebUploadDoc: (key, bytes, name) async {
                        if (!_puedeEditarDocumento(idx, key)) return;
                        final messenger = ScaffoldMessenger.of(context);
                        final ext = name.toLowerCase().split('.').last;
                        final ct = ext == 'pdf'
                            ? 'application/pdf'
                            : 'image/$ext';
                        final doc = await widget.svc.subirBytes(
                          bytes: bytes,
                          empresaId: widget.empresaId,
                          carpeta: 'recepciones',
                          nombre: name,
                          contentType: ct,
                        );
                        if (!mounted) return;
                        DateTime? vigencia;
                        if (documentoRequiereVigencia(key)) {
                          vigencia = await _solicitarVigenciaDespuesDeCargar(
                            context,
                            docKey: key,
                            labels: kDocRecepcionLabels,
                          );
                        }
                        if (!mounted) return;
                        // Todo documento reemplazado entra a revisión de Calidad.
                        final docFinal = doc.copyWith(
                          subidoPor: widget.userId,
                          estadoCalidad: estadoInicialDocumentoRecepcion(key),
                          observacionCalidad: '',
                          observacionActualizacion: _entries[idx]
                              .observacionesCtrl
                              .text
                              .trim(),
                          fechaVencimiento: vigencia == null
                              ? null
                              : Timestamp.fromDate(vigencia),
                          clearFechaVencimiento: vigencia == null,
                        );
                        setState(() {
                          _entries[idx].documentos[key] = docFinal;
                          if (_modoCorreccion) {
                            _correccionModificada = true;
                          }
                          if (_esDocumentoCorreccion(idx, key)) {
                            _documentoCorreccionCargado = true;
                          }
                        });
                        try {
                          await _persistirCorreccionRecepcion(
                            idx,
                            key,
                            docFinal,
                          );
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'El documento se cargó, pero falta enviarlo a Calidad: $e',
                              ),
                              backgroundColor: kComprasRed,
                            ),
                          );
                        }
                      },
                      onRequirementUploadDoc: !isNew
                          ? (key, bytes, name) async {
                              final productId =
                                  e.producto?.id ??
                                  (idx <
                                          (widget.existing?.productos.length ??
                                              0)
                                      ? widget
                                            .existing!
                                            .productos[idx]
                                            .productoId
                                      : '');
                              if (productId.isEmpty) {
                                throw StateError(
                                  'No se encontró el producto del requerimiento.',
                                );
                              }
                              final ext = name.toLowerCase().split('.').last;
                              final actualizado = await widget.svc
                                  .agregarSoporteRequerimiento(
                                    empresaId: widget.empresaId,
                                    tipo: 'recepcion',
                                    entidadId: widget.existing!.id,
                                    productoId: productId,
                                    docKey: key,
                                    userId: widget.userId,
                                    bytes: bytes,
                                    nombre: name,
                                    contentType: ext == 'pdf'
                                        ? 'application/pdf'
                                        : 'image/$ext',
                                  );
                              if (mounted) {
                                setState(
                                  () => _entries[idx].documentos[key] =
                                      actualizado,
                                );
                              }
                            }
                          : null,
                      onWebDeleteDoc: isNew
                          ? (key) => setState(
                              () => _entries[idx].documentos.remove(key),
                            )
                          : null,
                      onDateChangedDoc: (key, date) =>
                          _onDateChangedDoc(idx, key, date),
                      readOnlyStructure: !isNew,
                      canEditDocument: (key) => _puedeEditarDocumento(idx, key),
                    );
                  }),
                  if (isNew) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _agregarProducto,
                        icon: const Icon(Icons.add, color: kComprasPrimary),
                        label: const Text(
                          'Agregar producto',
                          style: TextStyle(
                            fontFamily: _kFont,
                            color: kComprasPrimary,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: kComprasPrimary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                  if (_mostrarAccionGuardar) ...[
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _guardando ? null : _guardar,
                        icon: _guardando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                isNew ? Icons.lock_outline : Icons.send_rounded,
                              ),
                        label: Text(
                          _guardando
                              ? 'Procesando...'
                              : isNew
                              ? 'Guardar, cerrar y enviar a Calidad'
                              : 'Enviar correcciones a Calidad',
                          style: const TextStyle(fontFamily: _kFont),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: isNew
                              ? kComprasPrimary
                              : kComprasRed,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}

class _RecepcionFlowBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final List<String> steps;
  final int activeStep;

  const _RecepcionFlowBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.steps,
    required this.activeStep,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      message,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final children = <Widget>[];
              for (var i = 0; i < steps.length; i++) {
                final completed = i < activeStep;
                final active = i == activeStep;
                children.add(
                  _RecepcionFlowStep(
                    label: steps[i],
                    color: color,
                    completed: completed,
                    active: active,
                  ),
                );
                if (i < steps.length - 1) {
                  children.add(
                    Icon(
                      compact ? Icons.keyboard_arrow_down : Icons.chevron_right,
                      size: 18,
                      color: const Color(0xFFCBD5E1),
                    ),
                  );
                }
              }
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    )
                  : Row(children: children);
            },
          ),
        ],
      ),
    );
  }
}

class _RecepcionFlowStep extends StatelessWidget {
  final String label;
  final Color color;
  final bool completed;
  final bool active;

  const _RecepcionFlowStep({
    required this.label,
    required this.color,
    required this.completed,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final stepColor = completed || active ? color : const Color(0xFF94A3B8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.11) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            completed
                ? Icons.check_circle
                : active
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 14,
            color: stepColor,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 10,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              color: stepColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductoEntryCard extends StatelessWidget {
  final int idx;
  final _RecepcionEntry entry;
  final VoidCallback onSelectProducto;
  final VoidCallback onRemove;
  final void Function(String key) onAdjuntarDoc;
  final void Function(String key) onVerDoc;
  final VoidCallback onChanged;
  final List<MarcaDoc> todasMarcas;
  final void Function(MarcaDoc?) onMarcaChanged;
  final VoidCallback onAgregarLote;
  final void Function(int loteIdx) onEditarLote;
  final void Function(int loteIdx) onEliminarLote;
  final bool readOnlyStructure;
  final bool Function(String key)? canEditDocument;

  /// Ficha técnica encontrada en la colección TBL_COMPRAS_FICHAS_TECNICAS para
  /// este proveedor + producto + marca. Null si no existe todavía.
  final FichaTecnicaDoc? fichaTecnicaDoc;

  /// Solo web: recibe (key, bytes, name) y sube el archivo directamente.
  final Future<void> Function(String key, Uint8List bytes, String name)?
  onWebUploadDoc;

  final Future<void> Function(String key, Uint8List bytes, String name)?
  onRequirementUploadDoc;

  /// Solo web: elimina el documento ya adjunto para la clave indicada.
  final void Function(String key)? onWebDeleteDoc;

  final void Function(String key, DateTime? date)? onDateChangedDoc;

  const _ProductoEntryCard({
    required this.idx,
    required this.entry,
    required this.onSelectProducto,
    required this.onRemove,
    required this.onAdjuntarDoc,
    required this.onVerDoc,
    required this.onChanged,
    required this.todasMarcas,
    required this.onMarcaChanged,
    required this.onAgregarLote,
    required this.onEditarLote,
    required this.onEliminarLote,
    this.fichaTecnicaDoc,
    this.onWebUploadDoc,
    this.onRequirementUploadDoc,
    this.onWebDeleteDoc,
    this.onDateChangedDoc,
    this.readOnlyStructure = false,
    this.canEditDocument,
  });

  @override
  Widget build(BuildContext context) {
    final producto = entry.producto;
    final esImportado = producto?.origen == 'IMPORTADO';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () {
              entry.expandido = !entry.expandido;
              onChanged();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: kComprasPrimary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${idx + 1}',
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: kComprasPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: producto == null
                        ? GestureDetector(
                            onTap: readOnlyStructure ? null : onSelectProducto,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: kComprasPrimary.withOpacity(0.4),
                                  style: BorderStyle.solid,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.search,
                                    size: 16,
                                    color: kComprasPrimary,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Seleccionar producto...',
                                    style: TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 13,
                                      color: kComprasPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: readOnlyStructure
                                    ? null
                                    : onSelectProducto,
                                child: Text(
                                  producto.nombre,
                                  style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Wrap(
                                spacing: 4,
                                children: [
                                  _Chip(producto.categoria, kComprasPrimary),
                                  _Chip(producto.unidadMedida, Colors.blueGrey),
                                  _Chip(
                                    esImportado ? 'Importado' : 'Nacional',
                                    esImportado
                                        ? Colors.purple.shade700
                                        : Colors.green.shade700,
                                  ),
                                ],
                              ),
                              // ─ Resumen de documentación cargada ─
                              Builder(
                                builder: (context) {
                                  final docs = entry.documentos;
                                  final docKeys = docsParaCategoria(
                                    producto.categoria,
                                  );
                                  final cargados = docKeys
                                      .where((k) => docs[k]?.tieneDoc == true)
                                      .length;
                                  final tieneFicha =
                                      docs['fichaTecnica']?.tieneDoc == true;
                                  final marcaNombre =
                                      entry.marcaSeleccionada?.descripcion;
                                  if (marcaNombre == null && cargados == 0)
                                    return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 2,
                                      children: [
                                        if (marcaNombre != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFF283593,
                                              ).withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: const Color(
                                                  0xFF283593,
                                                ).withOpacity(0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.local_offer,
                                                  size: 10,
                                                  color: Color(0xFF283593),
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  marcaNombre,
                                                  style: const TextStyle(
                                                    fontFamily: _kFont,
                                                    fontSize: 10,
                                                    color: Color(0xFF283593),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cargados == docKeys.length
                                                ? kComprasGreen.withOpacity(
                                                    0.08,
                                                  )
                                                : Colors.amber.shade50,
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                            border: Border.all(
                                              color: cargados == docKeys.length
                                                  ? kComprasGreen.withOpacity(
                                                      0.4,
                                                    )
                                                  : Colors.amber.shade300,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.description,
                                                size: 10,
                                                color:
                                                    cargados == docKeys.length
                                                    ? kComprasGreen
                                                    : Colors.amber.shade700,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                '$cargados/${docKeys.length} docs',
                                                style: TextStyle(
                                                  fontFamily: _kFont,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      cargados == docKeys.length
                                                      ? kComprasGreen
                                                      : Colors.amber.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: tieneFicha
                                                ? kComprasGreen.withOpacity(
                                                    0.08,
                                                  )
                                                : kComprasRed.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                            border: Border.all(
                                              color: tieneFicha
                                                  ? kComprasGreen.withOpacity(
                                                      0.4,
                                                    )
                                                  : kComprasRed.withOpacity(
                                                      0.4,
                                                    ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                tieneFicha
                                                    ? Icons.check_circle
                                                    : Icons.warning_amber,
                                                size: 10,
                                                color: tieneFicha
                                                    ? kComprasGreen
                                                    : kComprasRed,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                'Ficha',
                                                style: TextStyle(
                                                  fontFamily: _kFont,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: tieneFicha
                                                      ? kComprasGreen
                                                      : kComprasRed,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                  ),
                  if (!readOnlyStructure)
                    IconButton(
                      onPressed: onRemove,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  Icon(
                    entry.expandido ? Icons.expand_less : Icons.expand_more,
                    color: Colors.black38,
                  ),
                ],
              ),
            ),
          ),
          // Expanded section
          if (entry.expandido)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 16),
                  // ─ Selector de Marca ─
                  Builder(
                    builder: (context) {
                      if (producto == null) return const SizedBox.shrink();
                      final linkedIds = producto.marcas
                          .map((r) => r.marcaId)
                          .toSet();
                      final disponibles = todasMarcas
                          .where((m) => linkedIds.contains(m.id))
                          .toList();
                      if (disponibles.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 15,
                                color: Colors.black45,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Sin marcas configuradas para este producto',
                                style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12,
                                  color: Colors.black45,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final currentId = entry.marcaSeleccionada?.id;
                      final validId = disponibles.any((m) => m.id == currentId)
                          ? currentId
                          : null;
                      return DropdownButtonFormField<String>(
                        value: validId,
                        decoration: _inputDecoration('Marca').copyWith(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text(
                              '— Sin selección —',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 13,
                                color: Colors.black45,
                              ),
                            ),
                          ),
                          ...disponibles.map(
                            (m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(
                                '${m.codigo} – ${m.descripcion}',
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                        onChanged: readOnlyStructure
                            ? null
                            : (id) {
                                if (id == null) {
                                  onMarcaChanged(null);
                                } else {
                                  try {
                                    onMarcaChanged(
                                      disponibles.firstWhere((m) => m.id == id),
                                    );
                                  } catch (_) {}
                                }
                                onChanged();
                              },
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // ─ Ficha técnica (nueva colección primero, fallback producto) ─
                  Builder(
                    builder: (context) {
                      if (producto == null) return const SizedBox.shrink();

                      // 1. Ficha de la nueva colección (pasada como parámetro)
                      final fichaDoc = fichaTecnicaDoc;

                      // 2. Fallback: fichasTecnicasPorMarca / fichaTecnica del producto
                      final fichaMarcaLegacy = entry.marcaSeleccionada != null
                          ? producto.fichasTecnicasPorMarca[entry
                                .marcaSeleccionada!
                                .id]
                          : null;
                      final fichaLegacy = (fichaMarcaLegacy?.tieneDoc == true)
                          ? fichaMarcaLegacy
                          : producto.fichaTecnica;

                      // Sin ninguna fuente: ANTES no se mostraba nada y era
                      // imposible saber si el producto tenía ficha o no
                      // (reunión 29/07/2026). Ahora se advierte explícitamente.
                      if (fichaDoc == null && fichaLegacy?.tieneDoc != true) {
                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB45309).withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFB45309).withAlpha(90),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: Color(0xFFB45309),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Ficha técnica',
                                          style: TextStyle(
                                            fontFamily: _kFont,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'Este producto no tiene ficha técnica cargada '
                                          'para el proveedor y la marca seleccionados.',
                                          style: TextStyle(
                                            fontFamily: _kFont,
                                            fontSize: 11,
                                            color: Color(0xFFB45309),
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFB45309,
                                      ).withAlpha(30),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFFB45309),
                                      ),
                                    ),
                                    child: const Text(
                                      'Sin ficha',
                                      style: TextStyle(
                                        fontFamily: _kFont,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFB45309),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        );
                      }

                      // Determinar fuente y estado
                      final doc =
                          fichaDoc?.documentoAprobado ??
                          fichaDoc?.documentoActual ??
                          fichaLegacy;
                      final url = doc?.url;

                      Color badgeColor;
                      String badgeLabel;
                      String badgeTip;
                      if (fichaDoc != null) {
                        final d =
                            fichaDoc.documentoAprobado ??
                            fichaDoc.documentoActual;
                        if (d == null || !d.tieneDoc) {
                          badgeColor = Colors.grey;
                          badgeLabel = 'Sin ficha';
                          badgeTip = 'No hay ficha técnica registrada';
                        } else if (d.aprobadoConRequerimientos) {
                          badgeColor = const Color(0xFFD97706);
                          badgeLabel = 'Con requerimientos';
                          badgeTip =
                              'La ficha está aprobada para uso, con un requerimiento de Calidad todavía abierto.';
                        } else if (d.aprobado) {
                          badgeColor = kComprasGreen;
                          badgeLabel = 'Aprobada vigente';
                          badgeTip = fichaDoc.documentoActual?.pendiente == true
                              ? 'Se asoció la última aprobada; hay una versión nueva pendiente.'
                              : fichaDoc.documentoActual?.rechazado == true
                              ? 'Se asoció la última aprobada; la versión nueva fue rechazada.'
                              : 'Ficha asociada automáticamente por proveedor, producto y marca.';
                        } else if (d.rechazado) {
                          badgeColor = kComprasRed;
                          badgeLabel = 'Rechazada';
                          badgeTip =
                              'La ficha debe reemplazarse; la recepción puede guardarse para continuar la gestión.';
                        } else {
                          badgeColor = Colors.orange.shade800;
                          badgeLabel = 'Pendiente Calidad';
                          badgeTip =
                              'La ficha está asociada y pendiente de revisión; puedes guardar la recepción.';
                        }
                      } else {
                        badgeColor = Colors.blue;
                        badgeLabel = 'Disponible';
                        badgeTip = 'Ficha técnica del producto';
                      }

                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: badgeColor.withAlpha(80),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.description,
                                  size: 16,
                                  color: badgeColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Ficha técnica',
                                        style: TextStyle(
                                          fontFamily: _kFont,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        badgeTip,
                                        style: TextStyle(
                                          fontFamily: _kFont,
                                          fontSize: 11,
                                          color: badgeColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withAlpha(30),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: badgeColor),
                                  ),
                                  child: Text(
                                    badgeLabel,
                                    style: TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: badgeColor,
                                    ),
                                  ),
                                ),
                                if (url != null && url.isNotEmpty)
                                  IconButton(
                                    onPressed: () => _abrirUrl(context, url),
                                    icon: const Icon(
                                      Icons.open_in_new,
                                      size: 16,
                                    ),
                                    tooltip: 'Ver ficha técnica',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      );
                    },
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 16,
                        color: Color(0xFF475569),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Lotes recibidos',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                      if (!readOnlyStructure)
                        TextButton.icon(
                          onPressed: onAgregarLote,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Agregar lote'),
                        ),
                    ],
                  ),
                  if (entry.lotes.isEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Text(
                        'Sin lotes registrados. Puedes agregar uno o varios.',
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (
                            var loteIdx = 0;
                            loteIdx < entry.lotes.length;
                            loteIdx++
                          )
                            InputChip(
                              avatar: const Icon(Icons.tag, size: 15),
                              label: Text(
                                entry.lotes[loteIdx].fecha == null
                                    ? entry.lotes[loteIdx].numero
                                    : '${entry.lotes[loteIdx].numero} · ${DateFormat('dd/MM/yyyy').format(entry.lotes[loteIdx].fecha!.toDate())}',
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: readOnlyStructure
                                  ? null
                                  : () => onEditarLote(loteIdx),
                              onDeleted: readOnlyStructure
                                  ? null
                                  : () => onEliminarLote(loteIdx),
                              deleteIcon: const Icon(Icons.close, size: 15),
                            ),
                        ],
                      ),
                    ),
                  // ─ Documentos requeridos ─
                  Row(
                    children: [
                      const Text(
                        'Documentos requeridos',
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      if (producto?.categoria != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: kComprasPrimary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            producto!.categoria,
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 10,
                              color: kComprasPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...docsParaCategoria(producto?.categoria).map((key) {
                    final editable =
                        canEditDocument?.call(key) ?? !readOnlyStructure;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _DocAttachButton(
                        label: kDocRecepcionLabels[key] ?? key,
                        doc: entry.documentos[key],
                        editable: editable,
                        onAttach: () => onAdjuntarDoc(key),
                        onView: entry.documentos[key]?.tieneDoc == true
                            ? () => onVerDoc(key)
                            : null,
                        onDelete:
                            editable &&
                                entry.documentos[key]?.tieneDoc == true &&
                                onWebDeleteDoc != null
                            ? () => onWebDeleteDoc!(key)
                            : null,
                        onWebUpload: editable && onWebUploadDoc != null
                            ? (bytes, name) => onWebUploadDoc!(key, bytes, name)
                            : null,
                        onRequirementUpload:
                            onRequirementUploadDoc != null &&
                                entry
                                        .documentos[key]
                                        ?.aprobadoConRequerimientos ==
                                    true
                            ? (bytes, name) =>
                                  onRequirementUploadDoc!(key, bytes, name)
                            : null,
                        showCalendar: documentoRequiereVigencia(key),
                        onDateChanged: editable
                            ? (date) => onDateChangedDoc?.call(key, date)
                            : null,
                      ),
                    );
                  }),
                  // ─ Observaciones: solo visible cuando la ficha técnica está cargada ─
                  if (entry.documentos['fichaTecnica']?.tieneDoc == true) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: entry.observacionesCtrl,
                      readOnly: readOnlyStructure,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: const [_UpperCaseTextFormatter()],
                      decoration:
                          _inputDecoration(
                            'Observaciones de la ficha técnica',
                          ).copyWith(
                            hintText:
                                'Explique por qué se actualiza la ficha técnica...',
                            prefixIcon: const Icon(
                              Icons.note_alt_outlined,
                              size: 18,
                            ),
                          ),
                      maxLines: 2,
                      style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                      onChanged: (_) => onChanged(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Selector de producto para recepción
class _ProductoSelectorSheet extends StatefulWidget {
  final List<ProductoDoc> productos;

  /// Categorías del proveedor para mostrar una nota de filtro (vacío = sin filtro)
  final List<String> categoriasFiltradas;

  const _ProductoSelectorSheet({
    required this.productos,
    this.categoriasFiltradas = const [],
  });

  @override
  State<_ProductoSelectorSheet> createState() => _ProductoSelectorSheetState();
}

class _ProductoSelectorSheetState extends State<_ProductoSelectorSheet> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.productos
        : widget.productos
              .where(
                (p) =>
                    p.nombre.toLowerCase().contains(_q) ||
                    p.codigo.toLowerCase().contains(_q) ||
                    p.categoria.toLowerCase().contains(_q),
              )
              .toList();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Buscar producto...',
              prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            style: const TextStyle(fontFamily: _kFont, fontSize: 13),
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
          ),
        ),
        // Nota de filtro por categoría del proveedor
        if (widget.categoriasFiltradas.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: kComprasPrimary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kComprasPrimary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.filter_list, size: 14, color: kComprasPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Filtrado por categorías del proveedor: ${widget.categoriasFiltradas.join(', ')}',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 11,
                      color: kComprasPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final p = filtered[i];
              return ListTile(
                dense: true,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0277BD).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2,
                    size: 18,
                    color: Color(0xFF0277BD),
                  ),
                ),
                title: Text(
                  p.nombre,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  '${p.codigo} · ${p.categoria}',
                  style: const TextStyle(fontFamily: _kFont, fontSize: 11),
                ),
                trailing: _Chip(p.unidadMedida, Colors.blueGrey),
                onTap: () => Navigator.pop(context, p),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARCA SELECTOR DIALOG
// ══════════════════════════════════════════════════════════════════════════════

class _MarcaDialogResult {
  final MarcaDoc? seleccionada;
  final MarcaDoc? nuevaMarca;
  const _MarcaDialogResult.marcaExistente(this.seleccionada)
    : nuevaMarca = null;
  const _MarcaDialogResult.marcaCreada(this.nuevaMarca) : seleccionada = null;
}

class _MarcaSelectorDialog extends StatefulWidget {
  final ProductoDoc producto;
  final List<MarcaDoc> marcasDisponibles;
  final String empresaId;
  final ComprasService svc;

  const _MarcaSelectorDialog({
    required this.producto,
    required this.marcasDisponibles,
    required this.empresaId,
    required this.svc,
  });

  @override
  State<_MarcaSelectorDialog> createState() => _MarcaSelectorDialogState();
}

class _MarcaSelectorDialogState extends State<_MarcaSelectorDialog> {
  bool _creandoNueva = false;
  final _nombreCtrl = TextEditingController();
  bool _guardando = false;
  bool _generandoCodigo = false;
  String _codigoGenerado = '';

  @override
  void initState() {
    super.initState();
    if (widget.marcasDisponibles.isEmpty) {
      // Si no hay marcas disponibles, mostrar directamente el form de creación
      _creandoNueva = true;
      _generarCodigo();
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _generarCodigo() async {
    setState(() => _generandoCodigo = true);
    try {
      final codigo = await widget.svc.generarCodigoMarca(widget.empresaId);
      if (mounted)
        setState(() {
          _codigoGenerado = codigo;
          _generandoCodigo = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _codigoGenerado = 'MRC-???';
          _generandoCodigo = false;
        });
    }
  }

  Future<void> _crearYSeleccionar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) return;
    setState(() => _guardando = true);
    try {
      final codigo = _codigoGenerado.isNotEmpty ? _codigoGenerado : 'MRC-NEW';
      final nuevaMarca = MarcaDoc(
        id: '',
        empresaId: widget.empresaId,
        codigo: codigo.toUpperCase(),
        descripcion: _normalizarNombre(nombre),
        createdAt: Timestamp.now(),
      );
      final id = await widget.svc.guardarMarca(nuevaMarca, isNew: true);
      // Vincular la marca al producto
      final ref = MarcaRef(
        marcaId: id,
        codigo: nuevaMarca.codigo,
        descripcion: nuevaMarca.descripcion,
      );
      await widget.svc.guardarProducto(
        widget.producto.copyWith(marcas: [...widget.producto.marcas, ref]),
        isNew: false,
      );
      final creada = MarcaDoc(
        id: id,
        empresaId: nuevaMarca.empresaId,
        codigo: nuevaMarca.codigo,
        descripcion: nuevaMarca.descripcion,
        createdAt: nuevaMarca.createdAt,
      );
      if (mounted)
        Navigator.pop(context, _MarcaDialogResult.marcaCreada(creada));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear marca: $e'),
            backgroundColor: kComprasRed,
          ),
        );
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: kComprasPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_offer,
                  size: 18,
                  color: kComprasPrimary,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Seleccionar Marca',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.producto.nombre,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              color: Colors.black54,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.marcasDisponibles.isNotEmpty && !_creandoNueva) ...[
                const Text(
                  'Marcas disponibles',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                ...widget.marcasDisponibles.map(
                  (m) => InkWell(
                    onTap: () => Navigator.pop(
                      context,
                      _MarcaDialogResult.marcaExistente(m),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: kComprasPrimary.withOpacity(0.3),
                        ),
                        borderRadius: BorderRadius.circular(10),
                        color: kComprasPrimary.withOpacity(0.04),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.local_offer_outlined,
                            size: 16,
                            color: kComprasPrimary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.descripcion,
                                  style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  m.codigo,
                                  style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 11,
                                    color: Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                            color: kComprasPrimary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _creandoNueva = true);
                    _generarCodigo();
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text(
                    'Crear nueva marca',
                    style: TextStyle(fontFamily: _kFont, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kComprasPrimary,
                    side: const BorderSide(color: kComprasPrimary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ] else ...[
                // Formulario nueva marca
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kComprasPrimary.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: kComprasPrimary.withOpacity(0.15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.add_circle_outline,
                            size: 15,
                            color: kComprasPrimary,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Nueva marca para este producto',
                            style: TextStyle(
                              fontFamily: _kFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kComprasPrimary,
                            ),
                          ),
                        ],
                      ),
                      if (_generandoCodigo) ...[
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Generando código...',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ] else if (_codigoGenerado.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Código: $_codigoGenerado',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 11,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nombreCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: const [_UpperCaseTextFormatter()],
                  decoration:
                      _inputDecoration(
                        'Nombre / Descripción de la marca',
                      ).copyWith(
                        hintText: 'Ej: Nike, Zenú, Colanta...',
                        prefixIcon: const Icon(Icons.label_outline, size: 18),
                      ),
                  style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (widget.marcasDisponibles.isNotEmpty)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _guardando
                              ? null
                              : () => setState(() => _creandoNueva = false),
                          child: const Text(
                            'Volver',
                            style: TextStyle(fontFamily: _kFont),
                          ),
                        ),
                      ),
                    if (widget.marcasDisponibles.isNotEmpty)
                      const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: (_guardando || _generandoCodigo)
                            ? null
                            : _crearYSeleccionar,
                        style: FilledButton.styleFrom(
                          backgroundColor: kComprasPrimary,
                        ),
                        child: _guardando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Crear y Seleccionar',
                                style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancelar',
            style: TextStyle(fontFamily: _kFont, color: Colors.black54),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CONSULTAS SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class _ConsultaDocEstado {
  final String label;
  final Color color;
  final IconData icon;

  const _ConsultaDocEstado({
    required this.label,
    required this.color,
    required this.icon,
  });
}

_ConsultaDocEstado _estadoDocumentoConsulta(
  String key,
  DocAdjunto? doc, {
  bool requerido = true,
}) {
  if (doc?.tieneDoc != true) {
    return requerido
        ? const _ConsultaDocEstado(
            label: 'Falta',
            color: kComprasRed,
            icon: Icons.cancel,
          )
        : const _ConsultaDocEstado(
            label: 'Sin cargar',
            color: Color(0xFF64748B),
            icon: Icons.radio_button_unchecked,
          );
  }
  if (doc!.rechazado) {
    return const _ConsultaDocEstado(
      label: 'Rechazado',
      color: kComprasRed,
      icon: Icons.cancel,
    );
  }
  final vencimiento = doc.fechaVencimiento?.toDate();
  if (vencimiento != null && vencimiento.isBefore(DateTime.now())) {
    return const _ConsultaDocEstado(
      label: 'Vencido',
      color: kComprasRed,
      icon: Icons.event_busy,
    );
  }
  if (documentoRequiereVigencia(key) && vencimiento == null) {
    return _ConsultaDocEstado(
      label: 'Sin vigencia',
      color: Colors.orange.shade700,
      icon: Icons.schedule,
    );
  }
  if (doc.aprobadoConRequerimientos) {
    return const _ConsultaDocEstado(
      label: 'Aprobado con requerimientos',
      color: Color(0xFFB45309),
      icon: Icons.rule_folder_outlined,
    );
  }
  if (doc.pendienteRevisionCalidad) {
    return _ConsultaDocEstado(
      label: 'Pendiente',
      color: Colors.orange.shade700,
      icon: Icons.schedule,
    );
  }
  return const _ConsultaDocEstado(
    label: 'Completo',
    color: kComprasGreen,
    icon: Icons.check_circle,
  );
}

Widget _consultaDocumentoChip(
  String key,
  String label,
  DocAdjunto? doc, {
  bool requerido = true,
}) {
  final estado = _estadoDocumentoConsulta(key, doc, requerido: requerido);
  final chip = Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: estado.color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: estado.color.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(estado.icon, size: 13, color: estado.color),
        const SizedBox(width: 5),
        Text(
          '$label: ${estado.label}',
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: estado.color,
          ),
        ),
      ],
    ),
  );
  if (doc?.aprobadoConRequerimientos != true) return chip;
  final fecha = doc!.requerimientoFechaLimite?.toDate();
  final detalle = <String>[
    if (doc.requerimientoNota?.trim().isNotEmpty == true)
      doc.requerimientoNota!.trim(),
    if (fecha != null)
      'Fecha límite: ${DateFormat('dd/MM/yyyy').format(fecha)}',
    'Soportes enviados: ${doc.soportesRequerimiento.length}',
  ].join('\n');
  return Tooltip(message: detalle, child: chip);
}

Widget _consultaFichasProveedorChip(
  List<FichaTecnicaDoc> fichas, {
  DocAdjunto? respaldoMarca,
  bool compacto = false,
}) {
  final porProveedor = <String, FichaTecnicaDoc>{};
  for (final ficha in fichas) {
    if (documentoVisibleFichaTecnica(ficha) == null) continue;
    final key = ficha.proveedorId.trim().isNotEmpty
        ? ficha.proveedorId.trim()
        : normalizarClaveCatalogoCompras(ficha.proveedorNombre);
    porProveedor.putIfAbsent(key, () => ficha);
  }
  if (porProveedor.isEmpty) {
    return _consultaDocumentoChip('fichaTecnica', 'Ficha', respaldoMarca);
  }

  int prioridad(_ConsultaDocEstado estado) {
    switch (estado.label) {
      case 'Rechazado':
        return 6;
      case 'Vencido':
        return 5;
      case 'Sin vigencia':
        return 4;
      case 'Pendiente':
        return 3;
      case 'Aprobado con requerimientos':
        return 2;
      default:
        return 1;
    }
  }

  final estados = porProveedor.values.map((ficha) {
    final documento = documentoVisibleFichaTecnica(ficha);
    return MapEntry(ficha, _estadoDocumentoConsulta('fichaTecnica', documento));
  }).toList();
  estados.sort((a, b) => prioridad(b.value).compareTo(prioridad(a.value)));
  final estado = estados.first.value;
  final cantidad = porProveedor.length;
  final proveedorUnico = porProveedor.values.first.proveedorNombre.trim();
  final proveedorCorto = proveedorUnico.length > 24
      ? '${proveedorUnico.substring(0, 24)}…'
      : proveedorUnico;
  final descripcion = cantidad == 1 && !compacto
      ? '${proveedorCorto.isEmpty ? '1 proveedor' : proveedorCorto}: ${estado.label}'
      : '$cantidad ${cantidad == 1 ? 'proveedor' : 'proveedores'} · ${estado.label}';
  final detalle = estados
      .map((entry) {
        final nombre = entry.key.proveedorNombre.trim().isEmpty
            ? 'Proveedor sin nombre'
            : entry.key.proveedorNombre.trim();
        return '$nombre: ${entry.value.label}';
      })
      .join('\n');

  return Tooltip(
    message: detalle,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: estado.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: estado.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(estado.icon, size: 13, color: estado.color),
          const SizedBox(width: 5),
          Text(
            'Ficha · $descripcion',
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: estado.color,
            ),
          ),
        ],
      ),
    ),
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Helper: genera y descarga un archivo Excel
// ──────────────────────────────────────────────────────────────────────────
Future<void> _exportarExcel({
  required String nombreArchivo,
  required List<String> columnas,
  required List<List<String>> filas,
}) async {
  final bytes = construirExcelConsultas(
    nombreHoja: nombreArchivo,
    columnas: columnas,
    filas: filas,
  );
  await descargarExcelCompras(
    nombreArchivo:
        '${nombreArchivo}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
    bytes: bytes,
  );
}

class _ConsultaTabMeta {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ConsultaTabMeta({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class _ConsultasOverviewCounts {
  final int proveedores;
  final int productos;
  final int marcas;
  final int recepciones;
  final int fichas;

  const _ConsultasOverviewCounts({
    required this.proveedores,
    required this.productos,
    required this.marcas,
    required this.recepciones,
    required this.fichas,
  });

  int get total => proveedores + productos + marcas + recepciones + fichas;

  int countFor(int index) {
    switch (index) {
      case 0:
        return proveedores;
      case 1:
        return productos;
      case 2:
        return marcas;
      case 3:
        return recepciones;
      case 4:
        return fichas;
      default:
        return total;
    }
  }
}

class _ConsultasScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final bool esAdmin;

  /// Si el usuario puede descargar/exportar (solo Calidad o Admin).
  final bool canExport;

  const _ConsultasScreen({
    required this.empresaId,
    required this.svc,
    this.esAdmin = false,
    this.canExport = false,
  });

  @override
  State<_ConsultasScreen> createState() => _ConsultasScreenState();
}

class _ConsultasScreenState extends State<_ConsultasScreen>
    with SingleTickerProviderStateMixin {
  static const Color _accentColor = Color(0xFF283593);
  static const List<_ConsultaTabMeta> _tabs = [
    _ConsultaTabMeta(
      title: 'Proveedores',
      subtitle:
          'Cobertura documental, categorías activas y lectura rápida del maestro de proveedores.',
      icon: Icons.business,
    ),
    _ConsultaTabMeta(
      title: 'Productos',
      subtitle:
          'Catálogo consolidado con marcas y fichas técnicas asociadas por proveedor.',
      icon: Icons.inventory_2,
    ),
    _ConsultaTabMeta(
      title: 'Marcas',
      subtitle:
          'Consulta simple del universo de marcas habilitadas para operación y recepción.',
      icon: Icons.local_offer,
    ),
    _ConsultaTabMeta(
      title: 'Recepciones',
      subtitle:
          'Trazabilidad por proveedor, producto, orden de compra y bodega de destino.',
      icon: Icons.receipt_long,
    ),
    _ConsultaTabMeta(
      title: 'Fichas técnicas',
      subtitle:
          'Documentos específicos por producto, marca y proveedor con su estado de Calidad.',
      icon: Icons.description_outlined,
    ),
  ];

  late TabController _tabCtrl;
  late final Future<_ConsultasOverviewCounts> _overviewFuture;
  int _selectedTabIndex = 0;

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1180;
  _ConsultaTabMeta get _activeTab => _tabs[_selectedTabIndex];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(_handleTabChange);
    _overviewFuture = _loadOverviewCounts();
  }

  void _handleTabChange() {
    if (!mounted || _tabCtrl.indexIsChanging) return;
    if (_selectedTabIndex == _tabCtrl.index) return;
    setState(() => _selectedTabIndex = _tabCtrl.index);
  }

  void _changeTab(int index) {
    if (_selectedTabIndex == index) return;
    setState(() => _selectedTabIndex = index);
    _tabCtrl.animateTo(index);
  }

  Future<_ConsultasOverviewCounts> _loadOverviewCounts() async {
    final db = FirebaseFirestore.instance;
    final providers = await db
        .collection('TBL_COMPRAS_PROVEEDORES')
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    final products = await db
        .collection('TBL_COMPRAS_PRODUCTOS')
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    final brands = await db
        .collection('TBL_COMPRAS_MARCAS')
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    final receipts = await db
        .collection('TBL_COMPRAS_RECEPCIONES')
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    final technicalSheets = await db
        .collection('TBL_COMPRAS_FICHAS_TECNICAS')
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();

    return _ConsultasOverviewCounts(
      proveedores: providers.docs.length,
      productos: products.docs.length,
      marcas: brands.docs.length,
      recepciones: receipts.docs.length,
      fichas: technicalSheets.docs.length,
    );
  }

  List<Widget> _buildTabViews() {
    return [
      _ConsultaProveedoresTab(
        empresaId: widget.empresaId,
        svc: widget.svc,
        canExport: widget.canExport,
      ),
      _ConsultaProductosTab(
        empresaId: widget.empresaId,
        svc: widget.svc,
        canExport: widget.canExport,
      ),
      _ConsultaMarcasTab(
        empresaId: widget.empresaId,
        svc: widget.svc,
        canExport: widget.canExport,
      ),
      _ConsultaRecepcionesTab(
        empresaId: widget.empresaId,
        svc: widget.svc,
        canExport: widget.canExport,
      ),
      _ConsultaFichasTab(
        empresaId: widget.empresaId,
        svc: widget.svc,
        esAdmin: widget.esAdmin,
        canExport: widget.canExport,
      ),
    ];
  }

  // Vista amplia conservada como referencia visual mientras termina la
  // migración de Consultas al encabezado compacto y adaptable.
  // ignore: unused_element
  Widget _buildDesktopOverview() {
    return ModuleCard(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 1040;
          final leading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _accentColor.withOpacity(0.18)),
                ),
                child: const Text(
                  'Centro de consultas',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _accentColor,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _activeTab.title,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _activeTab.subtitle,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 14,
                  color: Color(0xFF475569),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _ConsultasFeatureChip(
                    icon: Icons.search_rounded,
                    label: 'Búsqueda rápida',
                  ),
                  _ConsultasFeatureChip(
                    icon: Icons.tune_rounded,
                    label: 'Filtros persistentes',
                  ),
                  _ConsultasFeatureChip(
                    icon: Icons.download_rounded,
                    label: 'Exportación a Excel',
                  ),
                  _ConsultasFeatureChip(
                    icon: Icons.visibility_outlined,
                    label: 'Lectura operativa',
                  ),
                ],
              ),
            ],
          );

          final trailing = FutureBuilder<_ConsultasOverviewCounts>(
            future: _overviewFuture,
            builder: (context, snapshot) {
              final counts = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _accentColor.withOpacity(0.14)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _accentColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            _activeTab.icon,
                            color: _accentColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Foco actual',
                                style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF475569),
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _activeTab.title,
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          counts == null
                              ? '...'
                              : counts.countFor(_selectedTabIndex).toString(),
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: _accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: List.generate(_tabs.length, (index) {
                      final tab = _tabs[index];
                      final selected = index == _selectedTabIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: stacked ? double.infinity : 164,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? _accentColor.withOpacity(0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? _accentColor.withOpacity(0.28)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              tab.icon,
                              size: 18,
                              color: selected
                                  ? _accentColor
                                  : const Color(0xFF64748B),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              tab.title,
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? _accentColor
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              counts == null
                                  ? 'Cargando...'
                                  : '${counts.countFor(index)} registros',
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [leading, const SizedBox(height: 18), trailing],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: leading),
              const SizedBox(width: 20),
              Expanded(flex: 5, child: trailing),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompactOverview() {
    return ModuleCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 860;
          final activeSummary = FutureBuilder<_ConsultasOverviewCounts>(
            future: _overviewFuture,
            builder: (context, snapshot) {
              final count = snapshot.data?.countFor(_selectedTabIndex);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_activeTab.icon, color: _accentColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _activeTab.title,
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            if (count != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '$count registros',
                                  style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _accentColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _activeTab.subtitle,
                          maxLines: stack ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            height: 1.35,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );

          final legend = Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              const _ConsultaLegendChip(
                color: kComprasGreen,
                label: 'Completo / vigente',
              ),
              _ConsultaLegendChip(
                color: Colors.orange.shade700,
                label: 'Pendiente',
              ),
              const _ConsultaLegendChip(
                color: kComprasRed,
                label: 'Falta / rechazado / vencido',
              ),
              const _ConsultaLegendChip(
                color: Color(0xFF64748B),
                label: 'Sin información',
              ),
              if (widget.canExport)
                const _ConsultaLegendChip(
                  color: _accentColor,
                  label: 'Excel disponible',
                  icon: Icons.download_rounded,
                ),
            ],
          );

          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [activeSummary, const SizedBox(height: 12), legend],
            );
          }
          return Row(
            children: [
              Expanded(flex: 6, child: activeSummary),
              const SizedBox(width: 18),
              Flexible(flex: 5, child: legend),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDesktopBody() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            children: [
              _buildCompactOverview(),
              const SizedBox(height: 16),
              InternalModuleTabs(
                items: _tabs
                    .map(
                      (tab) => InternalModuleTabItem(
                        label: tab.title,
                        icon: tab.icon,
                      ),
                    )
                    .toList(),
                selectedIndex: _selectedTabIndex,
                onSelected: _changeTab,
                accentColor: _accentColor,
                trailing: MediaQuery.of(context).size.width >= 1320
                    ? FutureBuilder<_ConsultasOverviewCounts>(
                        future: _overviewFuture,
                        builder: (context, snapshot) {
                          final total = snapshot.data?.countFor(
                            _selectedTabIndex,
                          );
                          return Text(
                            total == null
                                ? 'Preparando...'
                                : '$total registros visibles',
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155),
                            ),
                          );
                        },
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ModuleCard(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: TabBarView(
                      controller: _tabCtrl,
                      physics: const NeverScrollableScrollPhysics(),
                      children: _buildTabViews(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_handleTabChange);
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text(
          'Consultas',
          style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        bottom: _isDesktop
            ? null
            : TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                indicator: UnderlineTabIndicator(
                  borderSide: const BorderSide(width: 3, color: kComprasAccent),
                  borderRadius: BorderRadius.circular(999),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFFB3E5FC),
                labelStyle: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                tabs: _tabs
                    .map(
                      (tab) =>
                          Tab(icon: Icon(tab.icon, size: 16), text: tab.title),
                    )
                    .toList(),
              ),
      ),
      body: _isDesktop
          ? _buildDesktopBody()
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                children: [
                  _buildCompactOverview(),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ModuleCard(
                      padding: EdgeInsets.zero,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: TabBarView(
                          controller: _tabCtrl,
                          children: _buildTabViews(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ConsultaLegendChip extends StatelessWidget {
  final Color color;
  final String label;
  final IconData? icon;

  const _ConsultaLegendChip({
    required this.color,
    required this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.circle, size: icon == null ? 8 : 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsultasFeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ConsultasFeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _ConsultasScreenState._accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB: PROVEEDORES
// ══════════════════════════════════════════════════════════════════════════════
class _ConsultaProveedoresTab extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final bool canExport;
  const _ConsultaProveedoresTab({
    required this.empresaId,
    required this.svc,
    this.canExport = false,
  });
  @override
  State<_ConsultaProveedoresTab> createState() =>
      _ConsultaProveedoresTabState();
}

class _ConsultaProveedoresTabState extends State<_ConsultaProveedoresTab> {
  final _searchCtrl = TextEditingController();
  List<ProveedorDoc>? _todos;
  bool _loading = false;
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() {
      _loading = true;
      _todos = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_PROVEEDORES')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      if (!mounted) return;
      final lista =
          snap.docs.map((d) => ProveedorDoc.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.razonSocial.compareTo(b.razonSocial));
      setState(() {
        _todos = lista;
        _loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _todos = [];
          _loading = false;
        });
    }
  }

  Future<void> _exportar() async {
    if (_todos == null) return;
    setState(() => _exportando = true);
    try {
      final q = _searchCtrl.text.toLowerCase();
      final exportados = _todos!
          .where(
            (p) =>
                q.isEmpty ||
                p.razonSocial.toLowerCase().contains(q) ||
                p.nit.contains(q) ||
                p.ciudad.toLowerCase().contains(q),
          )
          .toList();
      final docKeys = kDocProveedorLabels.keys.toList();
      final columnas = [
        'NIT',
        'Razón Social',
        'Dirección',
        'Teléfono',
        'Email',
        'Departamento',
        'Ciudad',
        'Es Local',
        'Categorías',
        ...docKeys.expand(
          (k) => [
            '${kDocProveedorLabels[k]} · Estado',
            '${kDocProveedorLabels[k]} · Vigente hasta',
            '${kDocProveedorLabels[k]} · Requerimiento',
            '${kDocProveedorLabels[k]} · Fecha límite requerimiento',
            '${kDocProveedorLabels[k]} · Soportes',
            '${kDocProveedorLabels[k]} · URL',
          ],
        ),
      ];
      final filas = exportados
          .map(
            (p) => [
              p.nit,
              p.razonSocial,
              p.direccion,
              p.telefono,
              p.email,
              p.departamento,
              p.ciudad,
              p.esLocal ? 'Sí' : 'No',
              p.categorias.join(', '),
              ...docKeys.expand((k) {
                final doc = p.documentos[k];
                final estado = _estadoDocumentoConsulta(
                  k,
                  doc,
                  requerido: kDocumentosProveedorObligatorios.contains(k),
                );
                return [
                  estado.label,
                  doc?.fechaVencimiento == null
                      ? '—'
                      : DateFormat(
                          'dd/MM/yyyy',
                        ).format(doc!.fechaVencimiento!.toDate()),
                  doc?.requerimientoNota ?? '—',
                  doc?.requerimientoFechaLimite == null
                      ? '—'
                      : DateFormat(
                          'dd/MM/yyyy',
                        ).format(doc!.requerimientoFechaLimite!.toDate()),
                  '${doc?.soportesRequerimiento.length ?? 0}',
                  doc?.url ?? 'Sin cargar',
                ];
              }),
            ],
          )
          .toList();
      await _exportarExcel(
        nombreArchivo: 'consulta_proveedores',
        columnas: columnas,
        filas: filas,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: kComprasRed,
          ),
        );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.toLowerCase();
    final lista = (_todos ?? [])
        .where(
          (p) =>
              q.isEmpty ||
              p.razonSocial.toLowerCase().contains(q) ||
              p.nit.contains(q) ||
              p.ciudad.toLowerCase().contains(q),
        )
        .toList();

    return Column(
      children: [
        if (_todos != null)
          _ConsultasToolbar(
            searchCtrl: _searchCtrl,
            hint: 'Buscar por nombre, NIT o ciudad...',
            onSearchChanged: () => setState(() {}),
            total: lista.length,
            exportando: _exportando,
            onExportar: _exportar,
            canExport: widget.canExport,
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : lista.isEmpty
              ? const Center(
                  child: Text(
                    'Sin resultados',
                    style: TextStyle(fontFamily: _kFont, color: Colors.black45),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: lista.length,
                  itemBuilder: (_, i) {
                    final p = lista[i];
                    final docsSubidos = kDocProveedorLabels.keys
                        .where((k) => p.documentos[k]?.tieneDoc == true)
                        .length;
                    final totalDocs = kDocProveedorLabels.length;
                    final requeridosCompletos = kDocumentosProveedorObligatorios
                        .every(
                          (key) =>
                              _estadoDocumentoConsulta(
                                key,
                                p.documentos[key],
                              ).label ==
                              'Completo',
                        );
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          14,
                          0,
                          14,
                          14,
                        ),
                        title: Text(
                          p.razonSocial,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'NIT: ${p.nit}  •  ${p.ciudad}',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: requeridosCompletos
                                    ? kComprasGreen.withOpacity(0.1)
                                    : kComprasRed.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: requeridosCompletos
                                      ? kComprasGreen
                                      : kComprasRed,
                                ),
                              ),
                              child: Text(
                                '$docsSubidos/$totalDocs docs',
                                style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: requeridosCompletos
                                      ? kComprasGreen
                                      : kComprasRed,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.expand_more,
                              size: 18,
                              color: Colors.black38,
                            ),
                          ],
                        ),
                        children: [
                          // Info general
                          _InfoRow(
                            Icons.phone,
                            'Teléfono',
                            p.telefono.isEmpty ? '—' : p.telefono,
                          ),
                          _InfoRow(
                            Icons.email,
                            'Email',
                            p.email.isEmpty ? '—' : p.email,
                          ),
                          _InfoRow(
                            Icons.location_on,
                            'Dirección',
                            p.direccion.isEmpty ? '—' : p.direccion,
                          ),
                          _InfoRow(
                            Icons.home_work,
                            'Tipo',
                            p.esLocal ? 'Local' : 'No local',
                          ),
                          if (p.categorias.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: p.categorias
                                  .map((c) => _Chip(c, kComprasPrimary))
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 10),
                          const Text(
                            'Documentos',
                            style: TextStyle(
                              fontFamily: _kFont,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...kDocProveedorLabels.entries.map((e) {
                            final doc = p.documentos[e.key];
                            final tiene = doc?.tieneDoc == true;
                            final estado = _estadoDocumentoConsulta(
                              e.key,
                              doc,
                              requerido: kDocumentosProveedorObligatorios
                                  .contains(e.key),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    estado.icon,
                                    size: 14,
                                    color: estado.color,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      e.value,
                                      style: TextStyle(
                                        fontFamily: _kFont,
                                        fontSize: 12,
                                        color: tiene
                                            ? Colors.black87
                                            : Colors.black45,
                                      ),
                                    ),
                                  ),
                                  _ConsultaLegendChip(
                                    color: estado.color,
                                    label: estado.label,
                                  ),
                                  if (tiene)
                                    IconButton(
                                      onPressed: () =>
                                          _abrirUrl(context, doc!.url),
                                      icon: const Icon(
                                        Icons.open_in_new,
                                        size: 14,
                                        color: kComprasPrimary,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      tooltip: 'Ver documento',
                                    ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB: PRODUCTOS
// ══════════════════════════════════════════════════════════════════════════════
class _ConsultaProductosTab extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final bool canExport;
  const _ConsultaProductosTab({
    required this.empresaId,
    required this.svc,
    this.canExport = false,
  });
  @override
  State<_ConsultaProductosTab> createState() => _ConsultaProductosTabState();
}

class _ConsultaProductosTabState extends State<_ConsultaProductosTab> {
  final _searchCtrl = TextEditingController();
  List<ProductoDoc>? _todos;
  Map<String, MarcaDoc> _marcasPorId = {};
  List<FichaTecnicaDoc> _fichasTecnicas = [];
  bool _loading = false;
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() {
      _loading = true;
      _todos = null;
    });
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db
          .collection('TBL_COMPRAS_PRODUCTOS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      final marcasSnap = await db
          .collection('TBL_COMPRAS_MARCAS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      final fichasSnap = await db
          .collection('TBL_COMPRAS_FICHAS_TECNICAS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      if (!mounted) return;
      final lista =
          snap.docs.map((d) => ProductoDoc.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.nombre.compareTo(b.nombre));
      final fichas =
          fichasSnap.docs
              .map((doc) => FichaTecnicaDoc.fromMap(doc.id, doc.data()))
              .toList()
            ..sort((a, b) {
              final proveedor = a.proveedorNombre.compareTo(b.proveedorNombre);
              return proveedor != 0
                  ? proveedor
                  : a.marcaNombre.compareTo(b.marcaNombre);
            });
      setState(() {
        _todos = lista;
        _marcasPorId = {
          for (final doc in marcasSnap.docs)
            doc.id: MarcaDoc.fromMap(doc.id, doc.data()),
        };
        _fichasTecnicas = fichas;
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _todos = [];
          _marcasPorId = {};
          _fichasTecnicas = [];
          _loading = false;
        });
    }
  }

  List<FichaTecnicaDoc> _fichasDe(ProductoDoc producto) => _fichasTecnicas
      .where(
        (ficha) =>
            fichaTecnicaCorrespondeProducto(
              ficha,
              productoId: producto.id,
              productoNombre: producto.nombre,
            ) &&
            documentoVisibleFichaTecnica(ficha) != null,
      )
      .toList();

  List<FichaTecnicaDoc> _fichasDeMarca(ProductoDoc producto, MarcaRef marca) =>
      fichasCargadasProductoMarca(
        productoId: producto.id,
        productoNombre: producto.nombre,
        marcaId: marca.marcaId,
        marcaNombre: marca.descripcion,
        fichasTecnicas: _fichasTecnicas,
      );

  bool _coincideProducto(ProductoDoc producto, String consulta) {
    if (consulta.isEmpty) return true;
    return producto.nombre.toLowerCase().contains(consulta) ||
        producto.codigo.toLowerCase().contains(consulta) ||
        producto.categoria.toLowerCase().contains(consulta) ||
        _fichasDe(producto).any(
          (ficha) =>
              ficha.proveedorNombre.toLowerCase().contains(consulta) ||
              ficha.marcaNombre.toLowerCase().contains(consulta),
        );
  }

  String _resumenFichasProveedor(ProductoDoc producto) {
    final fichas = _fichasDe(producto);
    if (fichas.isEmpty) return 'Sin fichas técnicas asociadas';
    return fichas
        .map((ficha) {
          final estado = _estadoDocumentoConsulta(
            'fichaTecnica',
            documentoVisibleFichaTecnica(ficha),
          );
          return '${ficha.proveedorNombre} / ${ficha.marcaNombre}: ${estado.label}';
        })
        .join(' | ');
  }

  bool _marcaCompleta(ProductoDoc producto, MarcaRef ref) {
    final marca = _marcasPorId[ref.marcaId];
    if (marca == null) return false;
    final fichaGeneral = marca.documentosAsociados['fichaTecnica'];
    final fichaGeneralCompleta =
        _estadoDocumentoConsulta('fichaTecnica', fichaGeneral).label ==
        'Completo';
    final fichaProveedorCompleta = _fichasDeMarca(producto, ref).any(
      (ficha) =>
          _estadoDocumentoConsulta(
            'fichaTecnica',
            documentoVisibleFichaTecnica(ficha),
          ).label ==
          'Completo',
    );
    final registroCompleto =
        _estadoDocumentoConsulta(
          'registroSanitario',
          marca.documentosAsociados['registroSanitario'],
        ).label ==
        'Completo';
    return (fichaGeneralCompleta || fichaProveedorCompleta) && registroCompleto;
  }

  String _resumenDocumentoPorMarca(ProductoDoc producto, String key) {
    if (producto.marcas.isEmpty) return 'Sin marcas vinculadas';
    return producto.marcas
        .map((ref) {
          final marca = _marcasPorId[ref.marcaId];
          if (key == 'fichaTecnica') {
            final fichas = _fichasDeMarca(producto, ref);
            if (fichas.isNotEmpty) {
              return fichas
                  .map((ficha) {
                    final documento = documentoVisibleFichaTecnica(ficha);
                    final estado = _estadoDocumentoConsulta(key, documento);
                    final proveedor = ficha.proveedorNombre.trim().isEmpty
                        ? 'Proveedor sin nombre'
                        : ficha.proveedorNombre.trim();
                    return '${ref.descripcion} / $proveedor: ${estado.label}';
                  })
                  .join(' · ');
            }
          }
          final doc = marca?.documentosAsociados[key];
          final estado = _estadoDocumentoConsulta(key, doc);
          final vence = doc?.fechaVencimiento == null
              ? ''
              : ' · vence ${DateFormat('dd/MM/yyyy').format(doc!.fechaVencimiento!.toDate())}';
          return '${ref.descripcion}: ${estado.label}$vence';
        })
        .join(' | ');
  }

  Future<void> _exportar() async {
    if (_todos == null) return;
    setState(() => _exportando = true);
    try {
      final q = _searchCtrl.text.toLowerCase();
      final exportados = _todos!.where((p) => _coincideProducto(p, q)).toList();
      final columnas = [
        'Código',
        'Nombre',
        'Unidad de Medida',
        'Categoría',
        'Perecedero',
        'Origen',
        'Marcas',
        'Estado documental por marca',
        'Ficha técnica por marca',
        'Registro sanitario por marca',
        'Fichas técnicas por proveedor',
      ];
      final filas = exportados
          .map(
            (p) => [
              p.codigo,
              p.nombre,
              p.unidadMedida,
              p.categoria,
              p.esPerecedero ? 'Sí' : 'No',
              p.origen,
              p.marcas.map((m) => m.descripcion).join(', '),
              p.marcas.isNotEmpty &&
                      p.marcas.every((ref) => _marcaCompleta(p, ref))
                  ? 'Completo'
                  : 'Pendiente',
              _resumenDocumentoPorMarca(p, 'fichaTecnica'),
              _resumenDocumentoPorMarca(p, 'registroSanitario'),
              _resumenFichasProveedor(p),
            ],
          )
          .toList();
      await _exportarExcel(
        nombreArchivo: 'consulta_productos',
        columnas: columnas,
        filas: filas,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: kComprasRed,
          ),
        );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.toLowerCase();
    final lista = (_todos ?? []).where((p) => _coincideProducto(p, q)).toList();

    return Column(
      children: [
        if (_todos != null)
          _ConsultasToolbar(
            searchCtrl: _searchCtrl,
            hint: 'Buscar producto, código, categoría, marca o proveedor...',
            onSearchChanged: () => setState(() {}),
            total: lista.length,
            exportando: _exportando,
            onExportar: _exportar,
            canExport: widget.canExport,
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : lista.isEmpty
              ? const Center(
                  child: Text(
                    'Sin resultados',
                    style: TextStyle(fontFamily: _kFont, color: Colors.black45),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: lista.length,
                  itemBuilder: (_, i) {
                    final p = lista[i];
                    final fichasProducto = _fichasDe(p);
                    final marcasCompletas = p.marcas
                        .where((ref) => _marcaCompleta(p, ref))
                        .length;
                    final productoCompleto =
                        p.marcas.isNotEmpty &&
                        marcasCompletas == p.marcas.length;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          14,
                          0,
                          14,
                          14,
                        ),
                        title: Text(
                          p.nombre,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${p.codigo}  •  ${p.categoria}',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ConsultaLegendChip(
                              color: productoCompleto
                                  ? kComprasGreen
                                  : kComprasRed,
                              label: productoCompleto
                                  ? 'Marcas completas'
                                  : '$marcasCompletas/${p.marcas.length} marcas',
                            ),
                            const Icon(
                              Icons.expand_more,
                              size: 18,
                              color: Colors.black38,
                            ),
                          ],
                        ),
                        children: [
                          _InfoRow(Icons.straighten, 'Unidad', p.unidadMedida),
                          _InfoRow(Icons.public, 'Origen', p.origen),
                          _InfoRow(
                            Icons.eco,
                            'Perecedero',
                            p.esPerecedero ? 'Sí' : 'No',
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.description_outlined,
                                size: 16,
                                color: kComprasPrimary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Fichas técnicas por proveedor (${fichasProducto.length})',
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: kComprasPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (fichasProducto.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: const Text(
                                'No hay fichas técnicas asociadas a este producto.',
                                style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 11,
                                  color: Colors.black45,
                                ),
                              ),
                            )
                          else
                            ...fichasProducto.map((ficha) {
                              final doc = documentoVisibleFichaTecnica(ficha);
                              final estado = _estadoDocumentoConsulta(
                                'fichaTecnica',
                                doc,
                              );
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: estado.color.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: estado.color.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ficha.proveedorNombre.isEmpty
                                                ? 'Proveedor sin nombre'
                                                : ficha.proveedorNombre,
                                            style: const TextStyle(
                                              fontFamily: _kFont,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            ficha.marcaNombre.isEmpty
                                                ? 'Marca sin identificar'
                                                : ficha.marcaNombre,
                                            style: const TextStyle(
                                              fontFamily: _kFont,
                                              fontSize: 11,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _ConsultaLegendChip(
                                      color: estado.color,
                                      label: estado.label,
                                    ),
                                    if (doc?.tieneDoc == true)
                                      IconButton(
                                        onPressed: () =>
                                            _abrirUrl(context, doc!.url),
                                        icon: const Icon(
                                          Icons.open_in_new,
                                          size: 16,
                                        ),
                                        tooltip: 'Ver ficha técnica',
                                        color: kComprasPrimary,
                                      ),
                                  ],
                                ),
                              );
                            }),
                          if (p.marcas.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Marcas',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 8,
                              children: p.marcas.expand((ref) {
                                final marca = _marcasPorId[ref.marcaId];
                                final fichasMarca = _fichasDeMarca(p, ref);
                                return [
                                  _Chip(ref.descripcion, kComprasPrimary),
                                  _consultaFichasProveedorChip(
                                    fichasMarca,
                                    respaldoMarca: marca
                                        ?.documentosAsociados['fichaTecnica'],
                                  ),
                                  _consultaDocumentoChip(
                                    'registroSanitario',
                                    'Registro',
                                    marca
                                        ?.documentosAsociados['registroSanitario'],
                                  ),
                                ];
                              }).toList(),
                            ),
                          ],
                          // Productos cárnicos (Proteína): documentación semanal
                          // con historial de las últimas 4 semanas.
                          if (_esCarnico(p.categoria)) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _mostrarHistorialCarnico(
                                  context,
                                  empresaId: widget.empresaId,
                                  svc: widget.svc,
                                  producto: p,
                                ),
                                icon: const Icon(Icons.history, size: 16),
                                label: const Text(
                                  'Historial documental (4 semanas)',
                                  style: TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kComprasPrimary,
                                  side: const BorderSide(
                                    color: kComprasPrimary,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB: MARCAS
// ══════════════════════════════════════════════════════════════════════════════
class _ConsultaMarcasTab extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final bool canExport;
  const _ConsultaMarcasTab({
    required this.empresaId,
    required this.svc,
    this.canExport = false,
  });
  @override
  State<_ConsultaMarcasTab> createState() => _ConsultaMarcasTabState();
}

class _ConsultaMarcasTabState extends State<_ConsultaMarcasTab> {
  final _searchCtrl = TextEditingController();
  List<MarcaDoc>? _todos;
  List<FichaTecnicaDoc> _fichasTecnicas = [];
  bool _loading = false;
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() {
      _loading = true;
      _todos = null;
    });
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db
          .collection('TBL_COMPRAS_MARCAS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      final fichasSnap = await db
          .collection('TBL_COMPRAS_FICHAS_TECNICAS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      if (!mounted) return;
      final lista =
          snap.docs.map((d) => MarcaDoc.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.descripcion.compareTo(b.descripcion));
      setState(() {
        _todos = lista;
        _fichasTecnicas = fichasSnap.docs
            .map((doc) => FichaTecnicaDoc.fromMap(doc.id, doc.data()))
            .where((ficha) => documentoVisibleFichaTecnica(ficha) != null)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _todos = [];
          _fichasTecnicas = [];
          _loading = false;
        });
    }
  }

  List<FichaTecnicaDoc> _fichasDeMarca(MarcaDoc marca) =>
      _fichasTecnicas
          .where(
            (ficha) => fichaTecnicaCorrespondeMarca(
              ficha,
              marcaId: marca.id,
              marcaNombre: marca.descripcion,
            ),
          )
          .toList()
        ..sort((a, b) => a.proveedorNombre.compareTo(b.proveedorNombre));

  String _resumenFichasMarca(MarcaDoc marca) {
    final fichas = _fichasDeMarca(marca);
    if (fichas.isEmpty) {
      final general = marca.documentosAsociados['fichaTecnica'];
      return _estadoDocumentoConsulta('fichaTecnica', general).label;
    }
    return fichas
        .map((ficha) {
          final proveedor = ficha.proveedorNombre.trim().isEmpty
              ? 'Proveedor sin nombre'
              : ficha.proveedorNombre.trim();
          final estado = _estadoDocumentoConsulta(
            'fichaTecnica',
            documentoVisibleFichaTecnica(ficha),
          );
          return '$proveedor: ${estado.label}';
        })
        .join(' | ');
  }

  Future<void> _exportar() async {
    if (_todos == null) return;
    setState(() => _exportando = true);
    try {
      final q = _searchCtrl.text.toLowerCase();
      final exportadas = _todos!
          .where(
            (m) =>
                q.isEmpty ||
                m.descripcion.toLowerCase().contains(q) ||
                m.codigo.toLowerCase().contains(q) ||
                _fichasDeMarca(m).any(
                  (ficha) =>
                      ficha.proveedorNombre.toLowerCase().contains(q) ||
                      ficha.productoNombre.toLowerCase().contains(q),
                ),
          )
          .toList();
      final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es');
      String vence(DocAdjunto? doc) => doc?.fechaVencimiento == null
          ? '—'
          : DateFormat('dd/MM/yyyy').format(doc!.fechaVencimiento!.toDate());
      final columnas = [
        'Código',
        'Descripción',
        'Fecha Creación',
        'Estado ficha técnica',
        'Vigencia ficha técnica',
        'Requerimiento ficha técnica',
        'Fecha límite requerimiento ficha técnica',
        'Soportes ficha técnica',
        'URL ficha técnica',
        'Estado registro sanitario',
        'Vigencia registro sanitario',
        'Requerimiento registro sanitario',
        'Fecha límite requerimiento registro sanitario',
        'Soportes registro sanitario',
        'URL registro sanitario',
      ];
      final filas = exportadas.map((m) {
        final fichas = _fichasDeMarca(m);
        final fichaGeneral = m.documentosAsociados['fichaTecnica'];
        final registro = m.documentosAsociados['registroSanitario'];
        final fichasVisibles = fichas
            .map(documentoVisibleFichaTecnica)
            .whereType<DocAdjunto>()
            .toList();
        return [
          m.codigo,
          m.descripcion,
          fmt.format(m.createdAt.toDate()),
          _resumenFichasMarca(m),
          fichasVisibles.isEmpty ? vence(fichaGeneral) : '—',
          fichasVisibles.isEmpty
              ? fichaGeneral?.requerimientoNota ?? '—'
              : fichasVisibles
                    .where(
                      (doc) => doc.requerimientoNota?.trim().isNotEmpty == true,
                    )
                    .map((doc) => doc.requerimientoNota!.trim())
                    .join(' | '),
          fichasVisibles.isEmpty &&
                  fichaGeneral?.requerimientoFechaLimite != null
              ? DateFormat(
                  'dd/MM/yyyy',
                ).format(fichaGeneral!.requerimientoFechaLimite!.toDate())
              : '—',
          '${fichasVisibles.isEmpty ? fichaGeneral?.soportesRequerimiento.length ?? 0 : fichasVisibles.fold<int>(0, (total, doc) => total + doc.soportesRequerimiento.length)}',
          fichasVisibles.isEmpty
              ? fichaGeneral?.url ?? 'Sin cargar'
              : fichasVisibles.map((doc) => doc.url).join(' | '),
          _estadoDocumentoConsulta('registroSanitario', registro).label,
          vence(registro),
          registro?.requerimientoNota ?? '—',
          registro?.requerimientoFechaLimite == null
              ? '—'
              : DateFormat(
                  'dd/MM/yyyy',
                ).format(registro!.requerimientoFechaLimite!.toDate()),
          '${registro?.soportesRequerimiento.length ?? 0}',
          registro?.url ?? 'Sin cargar',
        ];
      }).toList();
      await _exportarExcel(
        nombreArchivo: 'consulta_marcas',
        columnas: columnas,
        filas: filas,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: kComprasRed,
          ),
        );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.toLowerCase();
    final lista = (_todos ?? [])
        .where(
          (m) =>
              q.isEmpty ||
              m.descripcion.toLowerCase().contains(q) ||
              m.codigo.toLowerCase().contains(q) ||
              _fichasDeMarca(m).any(
                (ficha) =>
                    ficha.proveedorNombre.toLowerCase().contains(q) ||
                    ficha.productoNombre.toLowerCase().contains(q),
              ),
        )
        .toList();

    return Column(
      children: [
        if (_todos != null)
          _ConsultasToolbar(
            searchCtrl: _searchCtrl,
            hint: 'Buscar marca...',
            onSearchChanged: () => setState(() {}),
            total: lista.length,
            exportando: _exportando,
            onExportar: _exportar,
            canExport: widget.canExport,
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : lista.isEmpty
              ? const Center(
                  child: Text(
                    'Sin resultados',
                    style: TextStyle(fontFamily: _kFont, color: Colors.black45),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: lista.length,
                  itemBuilder: (_, i) {
                    final m = lista[i];
                    final fichasMarca = _fichasDeMarca(m);
                    final proveedores = fichasMarca
                        .map((ficha) => ficha.proveedorNombre.trim())
                        .where((nombre) => nombre.isNotEmpty)
                        .toSet()
                        .join(', ');
                    final fichaCompleta =
                        fichasMarca.any(
                          (ficha) =>
                              _estadoDocumentoConsulta(
                                'fichaTecnica',
                                documentoVisibleFichaTecnica(ficha),
                              ).label ==
                              'Completo',
                        ) ||
                        _estadoDocumentoConsulta(
                              'fichaTecnica',
                              m.documentosAsociados['fichaTecnica'],
                            ).label ==
                            'Completo';
                    final registroCompleto =
                        _estadoDocumentoConsulta(
                          'registroSanitario',
                          m.documentosAsociados['registroSanitario'],
                        ).label ==
                        'Completo';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF283593),
                          child: Icon(
                            Icons.local_offer,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          m.descripcion,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${m.codigo}  •  ${DateFormat('dd/MM/yyyy', 'es').format(m.createdAt.toDate())}'
                          '${proveedores.isEmpty ? '' : '\nFicha cargada por: $proveedores'}',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 11,
                            color: Colors.black45,
                          ),
                        ),
                        trailing: MediaQuery.of(context).size.width >= 720
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _consultaFichasProveedorChip(
                                    fichasMarca,
                                    respaldoMarca:
                                        m.documentosAsociados['fichaTecnica'],
                                    compacto: true,
                                  ),
                                  const SizedBox(width: 6),
                                  _consultaDocumentoChip(
                                    'registroSanitario',
                                    'Registro',
                                    m.documentosAsociados['registroSanitario'],
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Colors.black38,
                                  ),
                                ],
                              )
                            : Icon(
                                Icons.circle,
                                size: 14,
                                color: fichaCompleta && registroCompleto
                                    ? kComprasGreen
                                    : kComprasRed,
                              ),
                        onTap: () => _mostrarDetalleMarca(
                          context,
                          m,
                          widget.empresaId,
                          widget.svc,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DETALLE DE MARCA (Consultas)
// ══════════════════════════════════════════════════════════════════════════════

void _mostrarDetalleMarca(
  BuildContext context,
  MarcaDoc marca,
  String empresaId,
  ComprasService svc,
) {
  _showComprasAdaptiveSheet(
    context: context,
    title: 'Detalle de marca',
    desktopHeader: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _MarcaDetailSheet(marca: marca, empresaId: empresaId, svc: svc),
  );
}

class _MarcaDetailSheet extends StatefulWidget {
  final MarcaDoc marca;
  final String empresaId;
  final ComprasService svc;
  const _MarcaDetailSheet({
    required this.marca,
    required this.empresaId,
    required this.svc,
  });
  @override
  State<_MarcaDetailSheet> createState() => _MarcaDetailSheetState();
}

class _MarcaDetailSheetState extends State<_MarcaDetailSheet> {
  List<FichaTecnicaDoc>? _fichas;
  List<ProductoDoc>? _productos;
  List<RecepcionDoc>? _recepciones;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final results = await Future.wait([
        widget.svc.getFichasTecnicas(widget.empresaId),
        widget.svc.getProductosPorMarca(widget.empresaId, widget.marca.id),
        widget.svc.getRecepcionesPorMarca(widget.empresaId, widget.marca.id),
      ]);
      if (!mounted) return;
      setState(() {
        _fichas =
            (results[0] as List<FichaTecnicaDoc>)
                .where(
                  (ficha) =>
                      fichaTecnicaCorrespondeMarca(
                        ficha,
                        marcaId: widget.marca.id,
                        marcaNombre: widget.marca.descripcion,
                      ) &&
                      documentoVisibleFichaTecnica(ficha) != null,
                )
                .toList()
              ..sort((a, b) => a.productoNombre.compareTo(b.productoNombre));
        _productos = results[1] as List<ProductoDoc>;
        _recepciones = results[2] as List<RecepcionDoc>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _sectionHeader(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
    child: Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF283593)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: Color(0xFF283593),
          ),
        ),
      ],
    ),
  );

  Widget _estadoChip(String estado) {
    Color bg;
    Color fg;
    String label;
    switch (estado) {
      case 'aprobado_con_requerimientos':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        label = 'Con requerimientos';
        break;
      case 'aprobado':
        bg = const Color(0xFFDCFCE7);
        fg = kComprasGreen;
        label = 'Aprobado';
        break;
      case 'rechazado':
        bg = const Color(0xFFFEE2E2);
        fg = kComprasRed;
        label = 'Rechazado';
        break;
      case 'pendiente':
      case 'pendiente_revision_calidad':
        bg = const Color(0xFFFEF3C7);
        fg = Colors.orange.shade800;
        label = 'Pendiente';
        break;
      default:
        bg = const Color(0xFFF3F4F6);
        fg = Colors.black54;
        label = 'Sin subir';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: _kFont,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF283593),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.white24,
                    radius: 24,
                    child: Icon(
                      Icons.local_offer,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.marca.descripcion,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.marca.codigo,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat(
                      'dd/MM/yyyy',
                      'es',
                    ).format(widget.marca.createdAt.toDate()),
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 11,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        'Error al cargar: $_error',
                        style: const TextStyle(
                          fontFamily: _kFont,
                          color: kComprasRed,
                        ),
                      ),
                    )
                  : ListView(
                      controller: sc,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      children: [
                        // ── Proveedores ──────────────────────────────────
                        _sectionHeader(
                          'Proveedores que abastecen esta marca',
                          Icons.store,
                        ),
                        Builder(
                          builder: (_) {
                            final provMap = <String, String>{};
                            for (final f in _fichas!) {
                              if (f.proveedorId.isNotEmpty) {
                                provMap[f.proveedorId] = f.proveedorNombre;
                              }
                            }
                            if (provMap.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'Sin proveedores registrados en fichas técnicas.',
                                  style: TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 12,
                                    color: Colors.black45,
                                  ),
                                ),
                              );
                            }
                            return Column(
                              children: provMap.entries.map((e) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0F4FF),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFBBCCF0),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.store,
                                        size: 16,
                                        color: Color(0xFF283593),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          e.value,
                                          style: const TextStyle(
                                            fontFamily: _kFont,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                        // ── Fichas Técnicas ──────────────────────────────
                        _sectionHeader(
                          'Fichas técnicas (${_fichas!.length})',
                          Icons.description,
                        ),
                        if (_fichas!.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              'Sin fichas técnicas registradas para esta marca.',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                color: Colors.black45,
                              ),
                            ),
                          ),
                        ..._fichas!.map((f) {
                          final doc = documentoVisibleFichaTecnica(f);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        f.productoNombre,
                                        style: const TextStyle(
                                          fontFamily: _kFont,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    if (doc != null && doc.tieneDoc)
                                      _estadoChip(doc.estadoCalidad),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  f.proveedorNombre,
                                  style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                                if (doc != null && doc.tieneDoc) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      if (doc.fechaVencimiento != null) ...[
                                        Icon(
                                          Icons.event,
                                          size: 12,
                                          color:
                                              doc.fechaVencimiento!
                                                  .toDate()
                                                  .isBefore(DateTime.now())
                                              ? kComprasRed
                                              : Colors.black45,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Vence: ${DateFormat('dd/MM/yyyy').format(doc.fechaVencimiento!.toDate())}',
                                          style: TextStyle(
                                            fontFamily: _kFont,
                                            fontSize: 10,
                                            color:
                                                doc.fechaVencimiento!
                                                    .toDate()
                                                    .isBefore(DateTime.now())
                                                ? kComprasRed
                                                : Colors.black45,
                                          ),
                                        ),
                                        const Spacer(),
                                      ] else
                                        const Spacer(),
                                      TextButton.icon(
                                        onPressed: () =>
                                            _abrirUrl(context, doc.url),
                                        icon: const Icon(
                                          Icons.open_in_new,
                                          size: 13,
                                        ),
                                        label: const Text(
                                          'Ver documento',
                                          style: TextStyle(
                                            fontFamily: _kFont,
                                            fontSize: 11,
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: kComprasPrimary,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      'Sin documento cargado',
                                      style: TextStyle(
                                        fontFamily: _kFont,
                                        fontSize: 11,
                                        color: Colors.orange.shade600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                        // ── Productos ────────────────────────────────────
                        _sectionHeader(
                          'Productos asociados (${_productos!.length})',
                          Icons.inventory_2,
                        ),
                        if (_productos!.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              'Sin productos vinculados a esta marca.',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                color: Colors.black45,
                              ),
                            ),
                          ),
                        ..._productos!.map((p) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.nombre,
                                        style: const TextStyle(
                                          fontFamily: _kFont,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        '${p.categoria} · ${p.unidadMedida}',
                                        style: const TextStyle(
                                          fontFamily: _kFont,
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: p.origen == 'IMPORTADO'
                                        ? const Color(0xFFFEF3C7)
                                        : const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    p.origen == 'IMPORTADO'
                                        ? 'Importado'
                                        : 'Nacional',
                                    style: TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: p.origen == 'IMPORTADO'
                                          ? Colors.orange.shade800
                                          : kComprasGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        // ── Recepciones recientes ────────────────────────
                        _sectionHeader(
                          'Recepciones recientes (${_recepciones!.take(10).length})',
                          Icons.local_shipping,
                        ),
                        if (_recepciones!.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              'Sin recepciones registradas con esta marca.',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                color: Colors.black45,
                              ),
                            ),
                          ),
                        ..._recepciones!.take(10).map((r) {
                          final prods = r.productos
                              .where((p) => p.marcaId == widget.marca.id)
                              .toList();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0F4FF),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    DateFormat(
                                      'dd/MM\nyyyy',
                                      'es',
                                    ).format(r.fecha.toDate()),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF283593),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.razonSocial,
                                        style: const TextStyle(
                                          fontFamily: _kFont,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      ...prods.map(
                                        (p) => Text(
                                          '· ${p.nombre}',
                                          style: const TextStyle(
                                            fontFamily: _kFont,
                                            fontSize: 11,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ),
                                      if (r.ordenCompra.isNotEmpty)
                                        Text(
                                          'OC: ${r.ordenCompra}',
                                          style: const TextStyle(
                                            fontFamily: _kFont,
                                            fontSize: 10,
                                            color: Colors.black38,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (_recepciones!.length > 10)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '... y ${_recepciones!.length - 10} recepciones más.',
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB: RECEPCIONES
// ══════════════════════════════════════════════════════════════════════════════
class _ConsultaRecepcionesTab extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final bool canExport;
  const _ConsultaRecepcionesTab({
    required this.empresaId,
    required this.svc,
    this.canExport = false,
  });
  @override
  State<_ConsultaRecepcionesTab> createState() =>
      _ConsultaRecepcionesTabState();
}

class _ConsultaRecepcionesTabState extends State<_ConsultaRecepcionesTab> {
  final _searchCtrl = TextEditingController();
  final _ordenCtrl = TextEditingController(); // búsqueda por OC
  List<RecepcionDoc>? _todos;
  bool _loading = false;
  bool _exportando = false;
  DateTime? _desde;
  DateTime? _hasta;
  List<ComprasGrupoDoc> _grupos = [];
  String _grupoFiltro = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _ordenCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final rangoError = validarRangoFechasCompras(_desde, _hasta);
    if (rangoError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(rangoError)));
      return;
    }
    setState(() {
      _loading = true;
      _todos = null;
    });
    try {
      final gruposFuture = widget.svc.getGruposCompras(widget.empresaId);
      final snap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_RECEPCIONES')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      final grupos = await gruposFuture;
      if (!mounted) return;
      final desdeTs = Timestamp.fromDate(_desde!);
      final hastaTs = Timestamp.fromDate(
        DateTime(_hasta!.year, _hasta!.month, _hasta!.day, 23, 59, 59),
      );
      final lista =
          snap.docs
              .map((d) => RecepcionDoc.fromMap(d.id, d.data()))
              .where(
                (r) =>
                    r.fecha.compareTo(desdeTs) >= 0 &&
                    r.fecha.compareTo(hastaTs) <= 0,
              )
              .toList()
            ..sort((a, b) => b.fecha.compareTo(a.fecha));
      setState(() {
        _todos = lista;
        _grupos = grupos;
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _todos = [];
          _loading = false;
        });
    }
  }

  Future<void> _exportar() async {
    if (_todos == null) return;
    setState(() => _exportando = true);
    try {
      final fmt = DateFormat('dd/MM/yyyy', 'es');
      final q = _searchCtrl.text.toLowerCase();
      final oc = _ordenCtrl.text.toLowerCase();
      final exportadas = _todos!.where((r) {
        final qMatch =
            q.isEmpty ||
            r.razonSocial.toLowerCase().contains(q) ||
            r.nit.contains(q) ||
            r.bodega.toLowerCase().contains(q) ||
            r.productos.any((p) => p.nombre.toLowerCase().contains(q));
        final ocMatch = oc.isEmpty || r.ordenCompra.toLowerCase().contains(oc);
        final grupoMatch =
            _grupoFiltro.isEmpty ||
            (_grupoFiltro == '__sin_grupo__'
                ? r.grupoId.isEmpty
                : r.grupoId == _grupoFiltro);
        return qMatch && ocMatch && grupoMatch;
      }).toList();
      final docKeys = [
        'certCalidad',
        'fichaTecnica',
        'evidenciaEtiqueta',
        'fechaVencimientoEtiqueta',
        'guiaTransporte',
        'docTransporte',
        'guiaSacrificio',
        'permisoZoo',
        'vistoInvima',
        'declImport',
      ];
      final columnas = [
        'Fecha',
        'Estado',
        'Orden de Compra',
        'Bodega',
        'Grupo de Compras',
        'Proveedor',
        'NIT',
        'Producto',
        'Categoría',
        'Marca',
        'Origen',
        'Lotes',
        'Observaciones',
        ...docKeys.expand(
          (k) => [
            '${kDocRecepcionLabels[k] ?? k} · Estado',
            '${kDocRecepcionLabels[k] ?? k} · Vigente hasta',
            '${kDocRecepcionLabels[k] ?? k} · Requerimiento',
            '${kDocRecepcionLabels[k] ?? k} · Fecha límite requerimiento',
            '${kDocRecepcionLabels[k] ?? k} · Soportes',
            '${kDocRecepcionLabels[k] ?? k} · URL',
          ],
        ),
      ];
      final filas = <List<String>>[];
      for (final r in exportadas) {
        for (final rp in r.productos) {
          final requeridos = docsParaCategoria(rp.categoria).toSet();
          filas.add([
            fmt.format(r.fecha.toDate()),
            switch (estadoRecepcionCompras(r)) {
              EstadoRecepcionCompras.pendiente => 'Pendiente',
              EstadoRecepcionCompras.historico => 'Histórico',
              EstadoRecepcionCompras.rechazada => 'Rechazado',
            },
            r.ordenCompra,
            r.bodega,
            r.grupoNombre,
            r.razonSocial,
            r.nit,
            rp.nombre,
            rp.categoria,
            rp.marca,
            rp.origen,
            rp.lotes
                .map(
                  (lote) => lote.fecha == null
                      ? lote.numero
                      : '${lote.numero} (${fmt.format(lote.fecha!.toDate())})',
                )
                .join(', '),
            rp.observaciones,
            ...docKeys.expand((k) {
              final doc = rp.documentos[k];
              final estado = _estadoDocumentoConsulta(
                k,
                doc,
                requerido: requeridos.contains(k),
              );
              return [
                estado.label,
                doc?.fechaVencimiento == null
                    ? '—'
                    : fmt.format(doc!.fechaVencimiento!.toDate()),
                doc?.requerimientoNota ?? '—',
                doc?.requerimientoFechaLimite == null
                    ? '—'
                    : fmt.format(doc!.requerimientoFechaLimite!.toDate()),
                '${doc?.soportesRequerimiento.length ?? 0}',
                doc?.url ?? 'Sin cargar',
              ];
            }),
          ]);
        }
      }
      await _exportarExcel(
        nombreArchivo: 'consulta_recepciones',
        columnas: columnas,
        filas: filas,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: kComprasRed,
          ),
        );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.toLowerCase();
    final oc = _ordenCtrl.text.toLowerCase();
    final lista = (_todos ?? []).where((r) {
      final qMatch =
          q.isEmpty ||
          r.razonSocial.toLowerCase().contains(q) ||
          r.nit.contains(q) ||
          r.bodega.toLowerCase().contains(q) ||
          r.productos.any((p) => p.nombre.toLowerCase().contains(q));
      final ocMatch = oc.isEmpty || r.ordenCompra.toLowerCase().contains(oc);
      final grupoMatch =
          _grupoFiltro.isEmpty ||
          (_grupoFiltro == '__sin_grupo__'
              ? r.grupoId.isEmpty
              : r.grupoId == _grupoFiltro);
      return qMatch && ocMatch && grupoMatch;
    }).toList();

    return Column(
      children: [
        _ConsultasFechaBar(
          desde: _desde,
          hasta: _hasta,
          onDesdeCambiado: (d) => setState(() => _desde = d),
          onHastaCambiado: (h) => setState(() => _hasta = h),
          onBuscar: _buscar,
          cargando: _loading,
        ),
        if (_todos != null) ...[
          // Barra búsqueda general
          _ConsultasToolbar(
            searchCtrl: _searchCtrl,
            hint: 'Buscar por proveedor, producto o bodega...',
            onSearchChanged: () => setState(() {}),
            total: lista.length,
            exportando: _exportando,
            onExportar: _exportar,
            canExport: widget.canExport,
          ),
          // Búsqueda por Orden de Compra
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _ordenCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por Orden de Compra...',
                prefixIcon: const Icon(Icons.receipt_long, size: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                hintStyle: const TextStyle(fontFamily: _kFont, fontSize: 12),
              ),
              style: const TextStyle(fontFamily: _kFont, fontSize: 13),
            ),
          ),
          if (_grupos.isNotEmpty)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: DropdownButtonFormField<String>(
                value: _grupoFiltro,
                decoration: InputDecoration(
                  labelText: 'Grupo de Compras',
                  prefixIcon: const Icon(Icons.groups_2_outlined, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Todos los grupos'),
                  ),
                  const DropdownMenuItem(
                    value: '__sin_grupo__',
                    child: Text('Recepciones anteriores sin grupo'),
                  ),
                  ..._grupos.map(
                    (grupo) => DropdownMenuItem(
                      value: grupo.id,
                      child: Text(grupo.nombre),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _grupoFiltro = value ?? ''),
              ),
            ),
        ],
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _todos == null
              ? const Center(
                  child: Text(
                    'Seleccione un rango de fechas y presione Buscar',
                    style: TextStyle(fontFamily: _kFont, color: Colors.black45),
                    textAlign: TextAlign.center,
                  ),
                )
              : lista.isEmpty
              ? const Center(
                  child: Text(
                    'Sin resultados',
                    style: TextStyle(fontFamily: _kFont, color: Colors.black45),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: lista.length,
                  itemBuilder: (_, i) {
                    final r = lista[i];
                    final estadoRecepcion = estadoRecepcionCompras(r);
                    final estadoLabel = switch (estadoRecepcion) {
                      EstadoRecepcionCompras.pendiente => 'Pendiente',
                      EstadoRecepcionCompras.historico => 'Histórico',
                      EstadoRecepcionCompras.rechazada => 'Rechazado',
                    };
                    final estadoColor = switch (estadoRecepcion) {
                      EstadoRecepcionCompras.pendiente =>
                        Colors.orange.shade700,
                      EstadoRecepcionCompras.historico => kComprasGreen,
                      EstadoRecepcionCompras.rechazada => kComprasRed,
                    };
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          14,
                          0,
                          14,
                          14,
                        ),
                        title: Text(
                          r.razonSocial,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${DateFormat('dd/MM/yyyy', 'es').format(r.fecha.toDate())}  •  OC: ${r.ordenCompra.isEmpty ? '—' : r.ordenCompra}${r.bodega.isNotEmpty ? '  •  ${r.bodega}' : ''}${r.grupoNombre.isNotEmpty ? '  •  ${r.grupoNombre}' : ''}  •  ${r.productos.length} producto(s)',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ConsultaLegendChip(
                              color: estadoColor,
                              label: estadoLabel,
                            ),
                            const Icon(
                              Icons.expand_more,
                              size: 18,
                              color: Colors.black38,
                            ),
                          ],
                        ),
                        children: r.productos.map((rp) {
                          final docsSubidos = rp.documentos.values
                              .where((d) => d.tieneDoc)
                              .length;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F4FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: kComprasPrimary.withOpacity(0.15),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        rp.nombre,
                                        style: const TextStyle(
                                          fontFamily: _kFont,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    if (rp.marca.isNotEmpty)
                                      _Chip(rp.marca, kComprasPrimary),
                                    const SizedBox(width: 4),
                                    _Chip(
                                      rp.origen,
                                      rp.origen == 'IMPORTADO'
                                          ? Colors.purple.shade700
                                          : Colors.green.shade700,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$docsSubidos doc(s) cargado(s)',
                                  style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 11,
                                    color: Colors.black45,
                                  ),
                                ),
                                if (rp.lotes.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Lotes: ${rp.lotes.map((lote) => lote.numero).join(', ')}',
                                    style: const TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 11,
                                      color: Color(0xFF475569),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                if (rp.observaciones.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Obs: ${rp.observaciones}',
                                    style: const TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                ...rp.documentos.entries
                                    .where((e) => e.value.tieneDoc)
                                    .map((e) {
                                      final doc = e.value;
                                      final label =
                                          kDocRecepcionLabels[e.key] ?? e.key;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              doc.aprobado
                                                  ? Icons.check_circle
                                                  : (doc.rechazado
                                                        ? Icons.cancel
                                                        : Icons
                                                              .hourglass_empty),
                                              size: 13,
                                              color: doc.aprobado
                                                  ? kComprasGreen
                                                  : (doc.rechazado
                                                        ? kComprasRed
                                                        : Colors.orange),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    label,
                                                    style: const TextStyle(
                                                      fontFamily: _kFont,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  if (doc.fechaVencimiento !=
                                                      null)
                                                    Text(
                                                      'Vence: ${DateFormat('dd/MM/yyyy').format(doc.fechaVencimiento!.toDate())}',
                                                      style: TextStyle(
                                                        fontFamily: _kFont,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            (doc.fechaVencimiento!
                                                                .toDate()
                                                                .isBefore(
                                                                  DateTime.now(),
                                                                ))
                                                            ? Colors.red
                                                            : Colors
                                                                  .orange
                                                                  .shade800,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () =>
                                                  _abrirUrl(context, doc.url),
                                              icon: const Icon(
                                                Icons.open_in_new,
                                                size: 13,
                                                color: kComprasPrimary,
                                              ),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 26,
                                                minHeight: 26,
                                              ),
                                              tooltip: 'Ver documento',
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB: FICHAS TÉCNICAS
// ══════════════════════════════════════════════════════════════════════════════
class _ConsultaFichasTab extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final bool esAdmin;
  final bool canExport;
  const _ConsultaFichasTab({
    required this.empresaId,
    required this.svc,
    this.esAdmin = false,
    this.canExport = false,
  });
  @override
  State<_ConsultaFichasTab> createState() => _ConsultaFichasTabState();
}

class _ConsultaFichasTabState extends State<_ConsultaFichasTab> {
  final _searchCtrl = TextEditingController();
  List<FichaTecnicaDoc>? _todos;
  bool _loading = false;
  bool _exportando = false;
  DateTime? _desde;
  DateTime? _hasta;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmarEliminarFicha(FichaTecnicaDoc f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: _comprasDialogTitle(
          dialogContext,
          'Eliminar ficha técnica',
          icon: Icons.delete_outline,
        ),
        content: Text(
          '¿Eliminar la ficha de "${f.productoNombre}" (${f.marcaNombre}) de ${f.proveedorNombre}?\n\nEsta acción eliminará el documento y su historial. No se puede deshacer.',
          style: const TextStyle(fontFamily: _kFont),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kComprasRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await widget.svc.eliminarFichaTecnica(f);
        setState(() => _todos?.removeWhere((x) => x.id == f.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ficha técnica eliminada'),
              backgroundColor: kComprasGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: kComprasRed,
            ),
          );
        }
      }
    }
  }

  Future<void> _buscar() async {
    final rangoError = validarRangoFechasCompras(_desde, _hasta);
    if (rangoError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(rangoError)));
      return;
    }
    setState(() {
      _loading = true;
      _todos = null;
    });
    try {
      final lista = await widget.svc.getFichasTecnicas(widget.empresaId);
      final desde = DateTime(_desde!.year, _desde!.month, _desde!.day);
      final hasta = DateTime(
        _hasta!.year,
        _hasta!.month,
        _hasta!.day,
        23,
        59,
        59,
      );
      final filtradas =
          lista.where((f) {
            final fecha = f.documentoActual?.fechaSubida?.toDate();
            if (fecha == null) return false;
            return !fecha.isBefore(desde) && !fecha.isAfter(hasta);
          }).toList()..sort((a, b) {
            final fa = a.documentoActual?.fechaSubida;
            final fb = b.documentoActual?.fechaSubida;
            if (fa == null && fb == null) return 0;
            if (fa == null) return 1;
            if (fb == null) return -1;
            return fb.compareTo(fa);
          });
      if (!mounted) return;
      setState(() {
        _todos = filtradas;
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _todos = [];
          _loading = false;
        });
    }
  }

  Future<void> _exportar() async {
    if (_todos == null) return;
    setState(() => _exportando = true);
    try {
      final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es');
      final columnas = [
        'Producto',
        'Categoría',
        'Marca',
        'Proveedor',
        'Estado Calidad',
        'Requerimiento de Calidad',
        'Fecha límite requerimiento',
        'Soportes del requerimiento',
        'Estado documental',
        'Vigente hasta',
        'Observación Actualización',
        'Link Documento Actual',
        'Fecha Subida',
        'Versiones en Historial',
      ];
      final q = _searchCtrl.text.toLowerCase();
      final lista = q.isEmpty
          ? _todos!
          : _todos!
                .where(
                  (f) =>
                      f.productoNombre.toLowerCase().contains(q) ||
                      f.marcaNombre.toLowerCase().contains(q) ||
                      f.proveedorNombre.toLowerCase().contains(q),
                )
                .toList();
      final filas = lista.map((f) {
        final doc = f.documentoActual;
        String estado = '—';
        if (doc != null) {
          if (doc.aprobadoConRequerimientos)
            estado = 'Aprobado con requerimientos';
          else if (doc.aprobado)
            estado = 'Aprobado';
          else if (doc.rechazado)
            estado = 'Rechazado';
          else if (doc.pendienteRevisionCalidad)
            estado = 'Pendiente revisión';
          else if (doc.tieneDoc)
            estado = 'Cargado';
        }
        return [
          f.productoNombre,
          f.productoCategoria,
          f.marcaNombre,
          f.proveedorNombre,
          estado,
          doc?.requerimientoNota ?? '—',
          doc?.requerimientoFechaLimite == null
              ? '—'
              : DateFormat(
                  'dd/MM/yyyy',
                ).format(doc!.requerimientoFechaLimite!.toDate()),
          '${doc?.soportesRequerimiento.length ?? 0}',
          _estadoDocumentoConsulta('fichaTecnica', doc).label,
          doc?.fechaVencimiento == null
              ? '—'
              : DateFormat(
                  'dd/MM/yyyy',
                ).format(doc!.fechaVencimiento!.toDate()),
          doc?.observacionActualizacion ?? '—',
          doc?.url ?? 'Sin cargar',
          doc?.fechaSubida != null
              ? fmt.format(doc!.fechaSubida!.toDate())
              : '—',
          '${f.historial.length}',
        ];
      }).toList();
      await _exportarExcel(
        nombreArchivo: 'consulta_fichas_tecnicas',
        columnas: columnas,
        filas: filas,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: kComprasRed,
          ),
        );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.toLowerCase();
    // Ordenar por fecha de última actualización de la ficha (más reciente primero)
    final lista =
        (_todos ?? [])
            .where(
              (f) =>
                  q.isEmpty ||
                  f.productoNombre.toLowerCase().contains(q) ||
                  f.marcaNombre.toLowerCase().contains(q) ||
                  f.proveedorNombre.toLowerCase().contains(q),
            )
            .toList()
          ..sort((a, b) {
            final fa = a.documentoActual?.fechaSubida;
            final fb = b.documentoActual?.fechaSubida;
            if (fa == null && fb == null) return 0;
            if (fa == null) return 1;
            if (fb == null) return -1;
            return fb.compareTo(fa);
          });

    // Últimas actualizadas (fichas con doc cargado ordenadas por fecha, top 5)
    final ultimasActualizadas =
        (_todos ?? [])
            .where(
              (f) =>
                  f.documentoActual?.fechaSubida != null &&
                  f.documentoActual?.tieneDoc == true,
            )
            .toList()
          ..sort(
            (a, b) => b.documentoActual!.fechaSubida!.compareTo(
              a.documentoActual!.fechaSubida!,
            ),
          );
    final topActualizadas = ultimasActualizadas.take(5).toList();

    return Column(
      children: [
        _ConsultasFechaBar(
          desde: _desde,
          hasta: _hasta,
          onDesdeCambiado: (d) => setState(() => _desde = d),
          onHastaCambiado: (h) => setState(() => _hasta = h),
          onBuscar: _buscar,
          cargando: _loading,
        ),
        if (_todos != null) ...[
          _ConsultasToolbar(
            searchCtrl: _searchCtrl,
            hint: 'Buscar por producto, marca o proveedor...',
            onSearchChanged: () => setState(() {}),
            total: lista.length,
            exportando: _exportando,
            onExportar: _exportar,
            canExport: widget.canExport,
          ),
          if (topActualizadas.isNotEmpty && q.isEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF1565C0).withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.update,
                        size: 14,
                        color: Color(0xFF1565C0),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Últimas fichas actualizadas',
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...topActualizadas.map((f) {
                    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es');
                    final fecha = fmt.format(
                      f.documentoActual!.fechaSubida!.toDate(),
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.circle,
                            size: 6,
                            color: Color(0xFF1565C0),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${f.productoNombre} — ${f.marcaNombre}',
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            fecha,
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 10,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _todos == null
              ? const Center(
                  child: Text(
                    'Seleccione un rango de fechas y presione Buscar',
                    style: TextStyle(fontFamily: _kFont, color: Colors.black45),
                    textAlign: TextAlign.center,
                  ),
                )
              : lista.isEmpty
              ? const Center(
                  child: Text(
                    'Sin resultados',
                    style: TextStyle(fontFamily: _kFont, color: Colors.black45),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: lista.length,
                  itemBuilder: (_, i) {
                    final f = lista[i];
                    final doc = f.documentoActual;
                    final fmtDt = DateFormat('dd/MM/yyyy HH:mm', 'es');
                    // Marcar como reciente si fue actualizada en los últimos 7 días
                    final esReciente =
                        doc?.fechaSubida != null &&
                        DateTime.now()
                                .difference(doc!.fechaSubida!.toDate())
                                .inDays <=
                            7;
                    Color badgeColor = Colors.grey;
                    String badgeLabel = 'Sin cargar';
                    if (doc != null && doc.tieneDoc) {
                      if (doc.aprobadoConRequerimientos) {
                        badgeColor = const Color(0xFFD97706);
                        badgeLabel = 'Con requerimientos';
                      } else if (doc.aprobado) {
                        badgeColor = kComprasGreen;
                        badgeLabel = 'Aprobado';
                      } else if (doc.rechazado) {
                        badgeColor = kComprasRed;
                        badgeLabel = 'Rechazado';
                      } else if (doc.pendienteRevisionCalidad) {
                        badgeColor = Colors.orange;
                        badgeLabel = 'Pendiente';
                      } else {
                        badgeColor = Colors.blueGrey;
                        badgeLabel = 'Cargado';
                      }
                    }
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          14,
                          0,
                          14,
                          14,
                        ),
                        title: Text(
                          f.productoNombre,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${f.marcaNombre}  •  ${f.proveedorNombre}',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.esAdmin)
                              IconButton(
                                onPressed: () => _confirmarEliminarFicha(f),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 17,
                                  color: kComprasRed,
                                ),
                                tooltip: 'Eliminar ficha',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 30,
                                  minHeight: 30,
                                ),
                              ),
                            if (esReciente)
                              Container(
                                margin: const EdgeInsets.only(right: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.green.shade400,
                                  ),
                                ),
                                child: const Text(
                                  'Reciente',
                                  style: TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: badgeColor),
                              ),
                              child: Text(
                                badgeLabel,
                                style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: badgeColor,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.expand_more,
                              size: 18,
                              color: Colors.black38,
                            ),
                          ],
                        ),
                        children: [
                          if (doc != null && doc.tieneDoc) ...[
                            _InfoRow(Icons.link, 'Documento actual', ''),
                            Row(
                              children: [
                                const SizedBox(width: 22),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        doc.nombre ?? '—',
                                        style: const TextStyle(
                                          fontFamily: _kFont,
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (doc.fechaVencimiento != null)
                                        Text(
                                          'Vence: ${DateFormat('dd/MM/yyyy').format(doc.fechaVencimiento!.toDate())}',
                                          style: TextStyle(
                                            fontFamily: _kFont,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                (doc.fechaVencimiento!
                                                    .toDate()
                                                    .isBefore(DateTime.now()))
                                                ? Colors.red
                                                : Colors.orange.shade800,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _abrirUrl(context, doc.url),
                                  icon: const Icon(
                                    Icons.open_in_new,
                                    size: 14,
                                    color: kComprasPrimary,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                  tooltip: 'Ver documento',
                                ),
                              ],
                            ),
                            if (doc.fechaSubida != null)
                              _InfoRow(
                                Icons.calendar_today,
                                'Fecha cargado',
                                fmtDt.format(doc.fechaSubida!.toDate()),
                              ),
                            if (doc.observacionActualizacion?.isNotEmpty ==
                                true)
                              _InfoRow(
                                Icons.note_alt_outlined,
                                'Observación',
                                doc.observacionActualizacion!,
                              ),
                          ],
                          if (f.historial.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Historial (${f.historial.length} versiones)',
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...f.historial.map(
                              (h) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.history,
                                      size: 13,
                                      color: Colors.black38,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            h.observacion.isEmpty
                                                ? (h.nombre.isEmpty
                                                      ? '—'
                                                      : h.nombre)
                                                : h.observacion,
                                            style: const TextStyle(
                                              fontFamily: _kFont,
                                              fontSize: 11,
                                              color: Colors.black54,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            fmtDt.format(h.fecha.toDate()),
                                            style: const TextStyle(
                                              fontFamily: _kFont,
                                              fontSize: 10,
                                              color: Colors.black38,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (h.url.isNotEmpty)
                                      IconButton(
                                        onPressed: () =>
                                            _abrirUrl(context, h.url),
                                        icon: const Icon(
                                          Icons.open_in_new,
                                          size: 12,
                                          color: kComprasPrimary,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 24,
                                          minHeight: 24,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Widget reutilizable: selector de fechas + botón Buscar
// ──────────────────────────────────────────────────────────────────────────
class _ConsultasFechaBar extends StatelessWidget {
  final DateTime? desde;
  final DateTime? hasta;
  final void Function(DateTime) onDesdeCambiado;
  final void Function(DateTime) onHastaCambiado;
  final VoidCallback onBuscar;
  final bool cargando;

  const _ConsultasFechaBar({
    required this.desde,
    required this.hasta,
    required this.onDesdeCambiado,
    required this.onHastaCambiado,
    required this.onBuscar,
    required this.cargando,
  });

  Future<void> _pickDate(
    BuildContext context,
    DateTime? initial,
    void Function(DateTime) onPicked,
    DateTime firstDate,
    DateTime lastDate,
  ) async {
    final suggested = initial ?? DateTime.now();
    final safeInitial = suggested.isBefore(firstDate)
        ? firstDate
        : suggested.isAfter(lastDate)
        ? lastDate
        : suggested;
    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('es'),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy', 'es');
    final now = DateTime.now();
    final rangoError = desde != null && hasta != null
        ? validarRangoFechasCompras(desde, hasta)
        : null;
    final listo = desde != null && hasta != null && rangoError == null;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Desde
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(
                    context,
                    desde,
                    onDesdeCambiado,
                    DateTime(2020),
                    hasta ?? now,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          desde != null ? fmt.format(desde!) : 'Desde',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: desde != null
                                ? Colors.black87
                                : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('—', style: TextStyle(color: Colors.black38)),
              ),
              // Hasta
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(
                    context,
                    hasta,
                    onHastaCambiado,
                    desde ?? DateTime(2020),
                    now,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          hasta != null ? fmt.format(hasta!) : 'Hasta',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: hasta != null
                                ? Colors.black87
                                : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Buscar
              cargando
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: listo ? onBuscar : null,
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text(
                        'Buscar',
                        style: TextStyle(fontFamily: _kFont, fontSize: 12),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: kComprasPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 36),
                      ),
                    ),
            ],
          ),
          if (rangoError != null) ...[
            const SizedBox(height: 6),
            Text(
              rangoError,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 11,
                color: kComprasRed,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Widget reutilizable: barra de búsqueda + contador + botón exportar
// ──────────────────────────────────────────────────────────────────────────
class _ConsultasToolbar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String hint;
  final VoidCallback onSearchChanged;
  final int total;
  final bool exportando;
  final VoidCallback onExportar;

  /// Solo Calidad/Admin pueden descargar (exportar a Excel). Para el resto de
  /// roles el botón no se muestra: consulta en modo solo-lectura.
  final bool canExport;

  const _ConsultasToolbar({
    required this.searchCtrl,
    required this.hint,
    required this.onSearchChanged,
    required this.total,
    required this.exportando,
    required this.onExportar,
    this.canExport = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final search = TextField(
      controller: searchCtrl,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: searchCtrl.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  searchCtrl.clear();
                  onSearchChanged();
                },
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Limpiar búsqueda',
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        filled: true,
        fillColor: Colors.grey.shade50,
        hintStyle: const TextStyle(fontFamily: _kFont, fontSize: 12),
      ),
      style: const TextStyle(fontFamily: _kFont, fontSize: 13),
      onChanged: (_) => onSearchChanged(),
    );
    final count = Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 12 : 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        '$total registros',
        style: const TextStyle(
          fontFamily: _kFont,
          fontSize: 12,
          color: Color(0xFF475569),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final export = !canExport
        ? null
        : exportando
        ? const SizedBox(
            width: 40,
            height: 40,
            child: Padding(
              padding: EdgeInsets.all(9),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : OutlinedButton.icon(
            onPressed: total == 0 ? null : onExportar,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text(
              'Descargar Excel',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF283593),
              side: const BorderSide(color: Color(0xFF283593)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );

    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 16 : 12,
        vertical: isDesktop ? 12 : 8,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 660) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 8),
                Row(
                  children: [count, const Spacer(), if (export != null) export],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              count,
              if (export != null) ...[const SizedBox(width: 8), export],
            ],
          );
        },
      ),
    );
  }
}

class _RecepcionResumenCard extends StatefulWidget {
  final RecepcionDoc recepcion;
  final RecepcionProducto? highlight;
  final ComprasService? svc;
  final String? empresaId;

  const _RecepcionResumenCard(
    this.recepcion, {
    this.highlight,
    this.svc,
    this.empresaId,
  });

  @override
  State<_RecepcionResumenCard> createState() => _RecepcionResumenCardState();
}

class _RecepcionResumenCardState extends State<_RecepcionResumenCard> {
  bool _expandido = false;
  late RecepcionDoc _r;
  final Map<String, bool> _subiendo = {};

  @override
  void initState() {
    super.initState();
    _r = widget.recepcion;
  }

  /// Sube o reemplaza un documento de un producto en una recepción existente
  Future<void> _subirDocProducto(int productoIdx, String docKey) async {
    if (widget.svc == null || widget.empresaId == null) return;
    final p = _r.productos[productoIdx];
    final nombreSug =
        '${_r.nit}_${p.nombre}_${kDocRecepcionLabels[docKey] ?? docKey}';

    final doc = await _mostrarEscaneador(
      context,
      empresaId: widget.empresaId!,
      carpeta: 'recepciones',
      nombreSugerido: nombreSug,
      svc: widget.svc!,
    );
    if (doc == null || !mounted) return;

    final subiendoKey = '${productoIdx}_$docKey';
    setState(() => _subiendo[subiendoKey] = true);
    try {
      // Construir productos actualizados con el nuevo doc
      final nuevosProductos = List<RecepcionProducto>.from(_r.productos);
      // Solo la ficha técnica entra a revisión de calidad
      final docFinal = docKey == 'fichaTecnica'
          ? doc.copyWith(
              estadoCalidad: 'pendiente_revision_calidad',
              observacionActualizacion: p.observaciones,
            )
          : doc;
      nuevosProductos[productoIdx] = RecepcionProducto(
        productoId: p.productoId,
        nombre: p.nombre,
        categoria: p.categoria,
        marcaId: p.marcaId,
        marca: p.marca,
        origen: p.origen,
        documentos: {...p.documentos, docKey: docFinal},
        lotes: p.lotes,
        observaciones: p.observaciones,
      );
      final nuevaRecepcion = RecepcionDoc(
        id: _r.id,
        empresaId: _r.empresaId,
        fecha: _r.fecha,
        proveedorId: _r.proveedorId,
        nit: _r.nit,
        razonSocial: _r.razonSocial,
        ordenCompra: _r.ordenCompra,
        bodega: _r.bodega,
        grupoId: _r.grupoId,
        grupoNombre: _r.grupoNombre,
        productos: nuevosProductos,
        productoIds: _r.productoIds,
        creadoPor: _r.creadoPor,
        createdAt: _r.createdAt,
      );
      await widget.svc!.guardarRecepcion(nuevaRecepcion);
      if (mounted) {
        setState(() => _r = nuevaRecepcion);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento guardado correctamente'),
            backgroundColor: kComprasGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: kComprasRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendo.remove(subiendoKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final hl = widget.highlight != null
        ? r.productos.firstWhere(
            (p) => p.productoId == widget.highlight!.productoId,
            orElse: () => widget.highlight!,
          )
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Column(
        children: [
          // ── Encabezado ───────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(14),
              bottom: Radius.circular(_expandido ? 0 : 14),
            ),
            onTap: () => setState(() => _expandido = !_expandido),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: kComprasPrimary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.local_shipping,
                          size: 18,
                          color: kComprasPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.razonSocial,
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.badge,
                                  size: 12,
                                  color: Colors.black38,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'NIT: ${r.nit}',
                                  style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _fmtFecha(r.fecha),
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kComprasPrimary,
                            ),
                          ),
                          if (r.ordenCompra.isNotEmpty)
                            Text(
                              'OC: ${r.ordenCompra}',
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 10,
                                color: Colors.black45,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Chip(
                        '${r.productos.length} producto${r.productos.length == 1 ? '' : 's'}',
                        kComprasPrimary,
                      ),
                      const Spacer(),
                      // Indicador de docs del highlight
                      if (hl != null) ...[
                        ...docsParaCategoria(hl.categoria).map((key) {
                          final tiene = hl.documentos[key]?.tieneDoc == true;
                          return Tooltip(
                            message: kDocRecepcionLabels[key] ?? key,
                            child: Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: tiene ? kComprasGreen : kComprasRed,
                                shape: BoxShape.circle,
                              ),
                            ),
                          );
                        }),
                        const SizedBox(width: 6),
                      ],
                      Icon(
                        _expandido ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: Colors.black38,
                      ),
                    ],
                  ),
                  if (hl != null && hl.marca.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_offer,
                          size: 13,
                          color: Colors.black38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Marca: ${hl.marca}',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Colors.black54,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // ── Productos expandidos ─────────────────────────
          if (_expandido) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Productos recibidos',
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      if (widget.svc != null)
                        const Tooltip(
                          message: 'Toca un documento para cargarlo',
                          child: Row(
                            children: [
                              Icon(
                                Icons.upload_file,
                                size: 13,
                                color: kComprasPrimary,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Editable',
                                style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 10,
                                  color: kComprasPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: r.productos.asMap().entries.map((entry) {
                      final productoIdx = entry.key;
                      final rp = entry.value;
                      final docsKeys = docsParaCategoria(rp.categoria);
                      return ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 200,
                          maxWidth: 320,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: kComprasPrimary.withOpacity(0.15),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Nombre + categoría
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      rp.nombre,
                                      style: const TextStyle(
                                        fontFamily: _kFont,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  _Chip(rp.categoria, kComprasPrimary),
                                ],
                              ),
                              // Marca
                              if (rp.marca.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.local_offer,
                                      size: 12,
                                      color: Colors.black38,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Marca: ${rp.marca}',
                                      style: const TextStyle(
                                        fontFamily: _kFont,
                                        fontSize: 11,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 8),
                              // Documentos — interactivos si hay svc
                              ...docsKeys.map((key) {
                                final doc = rp.documentos[key];
                                final tiene = doc?.tieneDoc == true;
                                final subiendo =
                                    _subiendo['${productoIdx}_$key'] == true;
                                if (widget.svc != null) {
                                  // Modo editable — botones con carga/ver
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: _DocAttachButton(
                                      label: kDocRecepcionLabels[key] ?? key,
                                      doc: doc,
                                      uploading: subiendo,
                                      onAttach: () =>
                                          _subirDocProducto(productoIdx, key),
                                      onView: tiene
                                          ? () => _abrirUrl(context, doc!.url)
                                          : null,
                                      onWebUpload: (bytes, name) async {
                                        final ext = name
                                            .toLowerCase()
                                            .split('.')
                                            .last;
                                        final ct = ext == 'pdf'
                                            ? 'application/pdf'
                                            : 'image/$ext';
                                        final uploadedDoc = await widget.svc!
                                            .subirBytes(
                                              bytes: bytes,
                                              empresaId: widget.empresaId!,
                                              carpeta: 'recepciones',
                                              nombre: name,
                                              contentType: ct,
                                            );
                                        final p = _r.productos[productoIdx];
                                        // Solo la ficha técnica entra a revisión de calidad
                                        final docFinal = key == 'fichaTecnica'
                                            ? uploadedDoc.copyWith(
                                                estadoCalidad:
                                                    'pendiente_revision_calidad',
                                                observacionActualizacion:
                                                    p.observaciones,
                                              )
                                            : uploadedDoc;
                                        final nuevosProductos =
                                            List<RecepcionProducto>.from(
                                              _r.productos,
                                            );
                                        nuevosProductos[productoIdx] =
                                            RecepcionProducto(
                                              productoId: p.productoId,
                                              nombre: p.nombre,
                                              categoria: p.categoria,
                                              marcaId: p.marcaId,
                                              marca: p.marca,
                                              origen: p.origen,
                                              documentos: {
                                                ...p.documentos,
                                                key: docFinal,
                                              },
                                              lotes: p.lotes,
                                              observaciones: p.observaciones,
                                            );
                                        final nuevaRecepcion = RecepcionDoc(
                                          id: _r.id,
                                          empresaId: _r.empresaId,
                                          fecha: _r.fecha,
                                          proveedorId: _r.proveedorId,
                                          nit: _r.nit,
                                          razonSocial: _r.razonSocial,
                                          ordenCompra: _r.ordenCompra,
                                          bodega: _r.bodega,
                                          grupoId: _r.grupoId,
                                          grupoNombre: _r.grupoNombre,
                                          productos: nuevosProductos,
                                          productoIds: _r.productoIds,
                                          creadoPor: _r.creadoPor,
                                          createdAt: _r.createdAt,
                                        );
                                        await widget.svc!.guardarRecepcion(
                                          nuevaRecepcion,
                                        );
                                        if (mounted) {
                                          setState(() => _r = nuevaRecepcion);
                                        }
                                      },
                                      onDelete: tiene
                                          ? () async {
                                              final p =
                                                  _r.productos[productoIdx];
                                              final nuevaDocs =
                                                  Map<String, DocAdjunto>.from(
                                                    p.documentos,
                                                  )..remove(key);
                                              final nuevosProductos =
                                                  List<RecepcionProducto>.from(
                                                    _r.productos,
                                                  );
                                              nuevosProductos[productoIdx] =
                                                  RecepcionProducto(
                                                    productoId: p.productoId,
                                                    nombre: p.nombre,
                                                    categoria: p.categoria,
                                                    marcaId: p.marcaId,
                                                    marca: p.marca,
                                                    origen: p.origen,
                                                    documentos: nuevaDocs,
                                                    lotes: p.lotes,
                                                    observaciones:
                                                        p.observaciones,
                                                  );
                                              final nuevaRecepcion =
                                                  RecepcionDoc(
                                                    id: _r.id,
                                                    empresaId: _r.empresaId,
                                                    fecha: _r.fecha,
                                                    proveedorId: _r.proveedorId,
                                                    nit: _r.nit,
                                                    razonSocial: _r.razonSocial,
                                                    ordenCompra: _r.ordenCompra,
                                                    bodega: _r.bodega,
                                                    grupoId: _r.grupoId,
                                                    grupoNombre: _r.grupoNombre,
                                                    productos: nuevosProductos,
                                                    productoIds: _r.productoIds,
                                                    creadoPor: _r.creadoPor,
                                                    createdAt: _r.createdAt,
                                                  );
                                              await widget.svc!
                                                  .guardarRecepcion(
                                                    nuevaRecepcion,
                                                  );
                                              if (mounted) {
                                                setState(
                                                  () => _r = nuevaRecepcion,
                                                );
                                              }
                                            }
                                          : null,
                                    ),
                                  );
                                } else {
                                  // Modo solo lectura — chips de estado
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          tiene
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          size: 14,
                                          color: tiene
                                              ? kComprasGreen
                                              : Colors.grey.shade400,
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            kDocRecepcionLabels[key] ?? key,
                                            style: TextStyle(
                                              fontFamily: _kFont,
                                              fontSize: 11,
                                              color: tiene
                                                  ? kComprasGreen
                                                  : Colors.grey.shade500,
                                            ),
                                          ),
                                        ),
                                        if (tiene)
                                          InkWell(
                                            onTap: () =>
                                                _abrirUrl(context, doc!.url),
                                            child: const Text(
                                              'Ver',
                                              style: TextStyle(
                                                fontFamily: _kFont,
                                                fontSize: 11,
                                                color: kComprasPrimary,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }
                              }),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARCAS SCREEN — listado de marcas
// ══════════════════════════════════════════════════════════════════════════════

class _MarcasScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final String userId;

  const _MarcasScreen({
    required this.empresaId,
    required this.svc,
    required this.userId,
  });

  @override
  State<_MarcasScreen> createState() => _MarcasScreenState();
}

class _MarcasScreenState extends State<_MarcasScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _abrirForm({MarcaDoc? existing}) async {
    await _showComprasAdaptiveSheet(
      context: context,
      title: existing == null ? 'Nueva marca' : 'Editar marca',
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _MarcaFormSheet(
          empresaId: widget.empresaId,
          svc: widget.svc,
          existing: existing,
        ),
      ),
    );
  }

  Future<void> _eliminar(MarcaDoc m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: _comprasDialogTitle(
          dialogContext,
          'Eliminar marca',
          icon: Icons.delete_outline,
        ),
        content: Text(
          '¿Eliminar "${m.descripcion}"? Esta acción no se puede deshacer.',
          style: const TextStyle(fontFamily: _kFont),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kComprasRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await widget.svc.eliminarMarca(m.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Marca eliminada'),
              backgroundColor: kComprasGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: kComprasRed),
          );
        }
      }
    }
  }

  Future<void> _abrirDocumentos(MarcaDoc marca) async {
    await _showComprasAdaptiveSheet(
      context: context,
      title: 'Documentos asociados · ${marca.descripcion}',
      desktopHeader: false,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DocumentosAsociadosSheet(
        titulo: marca.descripcion,
        marcaId: marca.id,
        empresaId: widget.empresaId,
        userId: widget.userId,
        svc: widget.svc,
        documentos: marca.documentosAsociados,
        onSave: (documentos) => widget.svc.actualizarDocumentosAsociadosMarca(
          marcaId: marca.id,
          documentos: documentos,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text(
          'Marcas',
          style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirForm(),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nueva Marca', style: TextStyle(fontFamily: _kFont)),
      ),
      body: Column(
        children: [
          // Buscador
          Container(
            color: const Color(0xFF1976D2),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontFamily: _kFont, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar marca...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          // Lista
          Expanded(
            child: StreamBuilder<List<MarcaDoc>>(
              stream: widget.svc.streamMarcas(widget.empresaId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snap.error}',
                      style: const TextStyle(fontFamily: _kFont),
                    ),
                  );
                }
                final todas = snap.data ?? [];
                final list = _query.isEmpty
                    ? todas
                    : todas
                          .where(
                            (m) =>
                                m.descripcion.toLowerCase().contains(_query) ||
                                m.codigo.toLowerCase().contains(_query),
                          )
                          .toList();
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.label_off,
                          size: 60,
                          color: Colors.blueGrey.shade200,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _query.isEmpty
                              ? 'No hay marcas registradas'
                              : 'Sin resultados para "$_query"',
                          style: TextStyle(
                            fontFamily: _kFont,
                            color: Colors.blueGrey.shade400,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return _comprasResponsiveList<MarcaDoc>(
                  padding: const EdgeInsets.all(16),
                  items: list,
                  itemBuilder: (_, m, i) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1976D2).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.label,
                            color: Color(0xFF1976D2),
                            size: 22,
                          ),
                        ),
                        title: Text(
                          m.descripcion,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          m.codigo,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.folder_copy_outlined,
                                size: 20,
                                color:
                                    _documentosAsociadosCompletos(
                                      m.documentosAsociados,
                                    )
                                    ? kComprasGreen
                                    : const Color(0xFF1976D2),
                              ),
                              tooltip:
                                  'Expediente documental (incluye modelo anterior)',
                              onPressed: () => _abrirDocumentos(m),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 20,
                                color: Color(0xFF1976D2),
                              ),
                              onPressed: () => _abrirForm(existing: m),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _eliminar(m),
                            ),
                          ],
                        ),
                        onTap: () => _abrirForm(existing: m),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARCA FORM SHEET — crear / editar marca (bottom sheet)
// ══════════════════════════════════════════════════════════════════════════════

class _MarcaFormSheet extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final MarcaDoc? existing;

  const _MarcaFormSheet({
    required this.empresaId,
    required this.svc,
    this.existing,
  });

  @override
  State<_MarcaFormSheet> createState() => _MarcaFormSheetState();
}

class _MarcaFormSheetState extends State<_MarcaFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codigoCtrl;
  late final TextEditingController _descCtrl;
  bool _guardando = false;
  bool _generandoCodigo = false;

  bool get isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _codigoCtrl = TextEditingController(text: widget.existing?.codigo ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.descripcion ?? '');
    if (isNew) {
      _generarCodigo();
    }
  }

  Future<void> _generarCodigo() async {
    setState(() => _generandoCodigo = true);
    try {
      final codigo = await widget.svc.generarCodigoMarca(widget.empresaId);
      if (mounted) setState(() => _codigoCtrl.text = codigo);
    } catch (_) {
      // Si falla la generación, el usuario puede escribirlo manualmente
    } finally {
      if (mounted) setState(() => _generandoCodigo = false);
    }
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final m = MarcaDoc(
        id: widget.existing?.id ?? '',
        empresaId: widget.empresaId,
        codigo: _codigoCtrl.text.trim().toUpperCase(),
        descripcion: _normalizarNombre(_descCtrl.text),
        documentosAsociados: widget.existing?.documentosAsociados ?? const {},
        createdAt: widget.existing?.createdAt ?? Timestamp.now(),
      );
      final marcaId = await widget.svc.guardarMarca(m, isNew: isNew);
      final marcaGuardada = MarcaDoc(
        id: marcaId,
        empresaId: m.empresaId,
        codigo: m.codigo,
        descripcion: m.descripcion,
        documentosAsociados: m.documentosAsociados,
        createdAt: m.createdAt,
        updatedAt: Timestamp.now(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNew ? 'Marca creada' : 'Marca actualizada'),
            backgroundColor: kComprasGreen,
          ),
        );
        Navigator.pop(context, marcaGuardada);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kComprasRed),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.label_important, color: Color(0xFF1976D2)),
                const SizedBox(width: 8),
                Text(
                  isNew ? 'Nueva Marca' : 'Editar Marca',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Código
            TextFormField(
              controller: _codigoCtrl,
              inputFormatters: const [_UpperCaseTextFormatter()],
              decoration: _inputDecoration('Código *').copyWith(
                hintText: 'MRC-0001',
                prefixIcon: _generandoCodigo
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.tag, size: 18),
                helperText: 'Auto-generado, editable si es necesario',
              ),
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
            ),
            const SizedBox(height: 14),
            // Descripción
            TextFormField(
              controller: _descCtrl,
              inputFormatters: const [_UpperCaseTextFormatter()],
              decoration: _inputDecoration(
                'Descripción / Nombre *',
              ).copyWith(hintText: 'Ej: Nike, Zenú, Colanta'),
              style: const TextStyle(fontFamily: _kFont, fontSize: 14),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _guardando ? 'Guardando...' : 'Guardar',
                  style: const TextStyle(fontFamily: _kFont),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════════════════════
// ORIGEN BUTTON — selector Nacional / Importado
// ══════════════════════════════════════════════════════════════════════════════

class _OrigenButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _OrigenButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? color : Colors.black45),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? color : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CALIDAD SCREEN — revisión y aprobación de documentos
// ══════════════════════════════════════════════════════════════════════════════

class _CalidadScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final String userId;

  /// Solo el Admin Documental puede revertir aprobaciones dadas por error.
  final bool esAdmin;

  const _CalidadScreen({
    required this.empresaId,
    required this.svc,
    required this.userId,
    this.esAdmin = false,
  });

  @override
  State<_CalidadScreen> createState() => _CalidadScreenState();
}

class _CalidadScreenState extends State<_CalidadScreen> {
  int _diasRetencionRechazados = ComprasService.kDiasCorreccionPredeterminado;
  String _filtroProducto = '';
  DateTime? _filtroFecha;
  final _searchCtrl = TextEditingController();
  ReqEngine? _reqEngine;
  bool _cargandoReq = true;
  bool _depurandoRechazados = false;

  @override
  void initState() {
    super.initState();
    _cargarReqEngine();
    _cargarPoliticaRechazados();
  }

  Future<void> _cargarPoliticaRechazados() async {
    final days = await widget.svc.obtenerDiasPlazoRechazados(widget.empresaId);
    if (mounted) setState(() => _diasRetencionRechazados = days);
    await _depurarRechazadosExpirados();
  }

  void _cargarReqEngine() {
    widget.svc
        .cargarReqEngine(widget.empresaId)
        .then((engine) {
          if (mounted) {
            setState(() {
              _reqEngine = engine;
              _cargandoReq = false;
            });
          }
        })
        .catchError((_) {
          if (mounted) {
            setState(() {
              _cargandoReq = false;
            });
          }
        });
  }

  Future<void> _depurarRechazadosExpirados() async {
    if (mounted) setState(() => _depurandoRechazados = true);
    try {
      final eliminados = await widget.svc.limpiarRechazadosExpirados(
        widget.empresaId,
        maxAge: Duration(days: _diasRetencionRechazados),
      );
      if (!mounted || eliminados <= 0) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Se limpiaron $eliminados rechazados vencidos de Calidad.',
            style: const TextStyle(fontFamily: _kFont),
          ),
          backgroundColor: const Color(0xFF0F766E),
        ),
      );
    } catch (_) {
      // Si la limpieza falla, no interrumpimos la revisión manual.
    } finally {
      if (mounted) setState(() => _depurandoRechazados = false);
    }
  }

  DateTime get _limiteRechazados =>
      DateTime.now().subtract(Duration(days: _diasRetencionRechazados));

  bool _docPendiente(DocAdjunto? doc) =>
      doc != null &&
      doc.tieneDoc &&
      (doc.aprobadoConRequerimientos || (!doc.aprobado && !doc.rechazado));

  bool _docRechazadoVisible(DocAdjunto? doc) {
    if (doc == null || !doc.tieneDoc || !doc.rechazado) return false;
    final fechaRevision = doc.fechaRevision?.toDate();
    if (fechaRevision == null) return true;
    return !fechaRevision.isBefore(_limiteRechazados);
  }

  bool _recepcionTieneDocumentosTransitorios(RecepcionDoc recepcion) {
    for (final producto in recepcion.productos) {
      final tiene = producto.documentos.entries.any(
        (entry) =>
            esDocumentoTransitorioRecepcion(entry.key) && entry.value.tieneDoc,
      );
      if (tiene) return true;
    }
    return false;
  }

  bool _proveedorTieneDocsPorEstado(
    ProveedorDoc proveedor, {
    required bool showRejectedOnly,
  }) {
    return proveedor.documentos.entries.any(
      (entry) =>
          !kDocProveedorOcultos.contains(entry.key) &&
          (showRejectedOnly
              ? _docRechazadoVisible(entry.value)
              : _docPendiente(entry.value)),
    );
  }

  bool _fichaTieneDocPorEstado(
    FichaTecnicaDoc ficha, {
    required bool showRejectedOnly,
  }) {
    final doc = ficha.documentoActual;
    return showRejectedOnly ? _docRechazadoVisible(doc) : _docPendiente(doc);
  }

  bool _marcaTieneDocsPorEstado(
    MarcaDoc marca, {
    required bool showRejectedOnly,
  }) {
    return marca.documentosAsociados.entries.any(
      (entry) => showRejectedOnly
          ? _docRechazadoVisible(entry.value)
          : _docPendiente(entry.value),
    );
  }

  bool _textoContiene(String value) {
    final filtro = _filtroProducto.trim().toLowerCase();
    if (filtro.isEmpty) return true;
    return value.toLowerCase().contains(filtro);
  }

  bool _coincideRecepcion(RecepcionDoc recepcion) {
    if (_filtroProducto.trim().isEmpty) return true;
    return _textoContiene(recepcion.razonSocial) ||
        _textoContiene(recepcion.nit) ||
        _textoContiene(recepcion.ordenCompra) ||
        recepcion.productos.any(
          (producto) =>
              _textoContiene(producto.nombre) || _textoContiene(producto.marca),
        );
  }

  bool _coincideProveedor(ProveedorDoc proveedor) {
    if (_filtroProducto.trim().isEmpty) return true;
    return _textoContiene(proveedor.razonSocial) ||
        _textoContiene(proveedor.nit) ||
        proveedor.categorias.any(_textoContiene);
  }

  bool _coincideFicha(FichaTecnicaDoc ficha) {
    if (_filtroProducto.trim().isEmpty) return true;
    return _textoContiene(ficha.productoNombre) ||
        _textoContiene(ficha.proveedorNombre) ||
        _textoContiene(ficha.marcaNombre);
  }

  bool _coincideMarca(MarcaDoc marca) {
    if (_filtroProducto.trim().isEmpty) return true;
    return _textoContiene(marca.descripcion) || _textoContiene(marca.codigo);
  }

  Widget _buildFiltros() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 420;
          final search = TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Filtrar por proveedor, producto, marca o NIT...',
              prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            style: const TextStyle(fontFamily: _kFont, fontSize: 13),
            onChanged: (v) => setState(() => _filtroProducto = v.toLowerCase()),
          );
          final dateActions = Wrap(
            spacing: 4,
            children: [
              IconButton(
                icon: Icon(
                  Icons.calendar_today,
                  color: _filtroFecha != null
                      ? const Color(0xFF15803D)
                      : Colors.black45,
                ),
                tooltip: 'Filtrar por fecha de recepción',
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _filtroFecha ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _filtroFecha = picked);
                  }
                },
              ),
              if (_filtroFecha != null)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.red),
                  tooltip: 'Limpiar fecha',
                  onPressed: () => setState(() => _filtroFecha = null),
                ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: dateActions),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              dateActions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildFechaFiltradaBanner() {
    if (_filtroFecha == null) return const SizedBox.shrink();
    return Container(
      color: Colors.green.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 14, color: Color(0xFF15803D)),
          const SizedBox(width: 4),
          Text(
            'Fecha de recepción: ${DateFormat('dd/MM/yyyy', 'es').format(_filtroFecha!)}',
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              color: Color(0xFF15803D),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendientesTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildProveedoresSection(showRejectedOnly: false),
        const SizedBox(height: 14),
        _buildFichasSection(showRejectedOnly: false),
        const SizedBox(height: 14),
        _buildMarcasSection(showRejectedOnly: false),
        const SizedBox(height: 14),
        _buildRecepcionesRevisionSection(),
      ],
    );
  }

  bool _recepcionTienePermanentesPendientes(RecepcionDoc recepcion) {
    for (final producto in recepcion.productos) {
      final tiene = producto.documentos.entries.any(
        (entry) =>
            esDocumentoPermanenteRecepcion(entry.key) &&
            entry.value.tieneDoc &&
            (entry.value.aprobadoConRequerimientos ||
                (!entry.value.aprobado && !entry.value.rechazado)),
      );
      if (tiene) return true;
    }
    return false;
  }

  /// Documentos permanentes de recepción por aprobar. Antes no se mostraban en
  /// ninguna pestaña: el Resumen los contaba pero no había dónde revisarlos.
  Widget _buildRecepcionesRevisionSection() {
    Widget child;
    if (_cargandoReq) {
      child = const _CalidadLoadingState(
        message: 'Cargando reglas de recepciones...',
      );
    } else {
      child = StreamBuilder<List<RecepcionDoc>>(
        stream: widget.svc.streamRecepciones(widget.empresaId),
        builder: (_, snap) {
          var recepciones = (snap.data ?? [])
              .where(_recepcionTienePermanentesPendientes)
              .where(_coincideRecepcion)
              .toList();

          if (_filtroFecha != null) {
            recepciones = recepciones.where((r) {
              final fecha = r.fecha.toDate();
              return fecha.year == _filtroFecha!.year &&
                  fecha.month == _filtroFecha!.month &&
                  fecha.day == _filtroFecha!.day;
            }).toList();
          }

          if (recepciones.isEmpty) {
            return const _CalidadEmptyState(
              icon: Icons.inventory_2_outlined,
              message:
                  'No hay documentos de recepción pendientes de aprobación.',
            );
          }

          return Column(
            children: [
              for (var i = 0; i < recepciones.length; i++) ...[
                _RecepcionCalidadCard(
                  recepcion: recepciones[i],
                  svc: widget.svc,
                  userId: widget.userId,
                  filtroProducto: _filtroProducto,
                  reqEngine: _reqEngine,
                  soloPermanentes: true,
                  retentionDays: _diasRetencionRechazados,
                ),
                if (i < recepciones.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        },
      );
    }

    return _CalidadSectionPanel(
      titulo: 'Recepciones en revisión',
      subtitulo:
          'Documentos permanentes de recepción pendientes de aprobación.',
      icon: Icons.inventory_2_outlined,
      color: const Color(0xFF1D4ED8),
      child: child,
    );
  }

  Widget _buildRechazadosTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.schedule, color: Color(0xFFB45309), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Los documentos rechazados se muestran aparte y se eliminan automáticamente después de $_diasRetencionRechazados días.',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildProveedoresSection(showRejectedOnly: true),
        const SizedBox(height: 14),
        _buildFichasSection(showRejectedOnly: true),
        const SizedBox(height: 14),
        _buildMarcasSection(showRejectedOnly: true),
      ],
    );
  }

  Widget _buildMarcasSection({required bool showRejectedOnly}) {
    const color = Color(0xFF6D28D9);
    return StreamBuilder<List<MarcaDoc>>(
      stream: widget.svc.streamMarcas(widget.empresaId),
      builder: (_, snap) {
        final marcas = (snap.data ?? [])
            .where(
              (marca) => _marcaTieneDocsPorEstado(
                marca,
                showRejectedOnly: showRejectedOnly,
              ),
            )
            .where(_coincideMarca)
            .toList();
        final child = marcas.isEmpty
            ? _CalidadEmptyState(
                icon: Icons.local_offer_outlined,
                message: showRejectedOnly
                    ? 'No hay documentos de marca rechazados vigentes.'
                    : 'No hay fichas o registros sanitarios pendientes.',
              )
            : Column(
                children: [
                  for (var i = 0; i < marcas.length; i++) ...[
                    _MarcaCalidadCard(
                      marca: marcas[i],
                      svc: widget.svc,
                      userId: widget.userId,
                      showRejectedOnly: showRejectedOnly,
                      retentionDays: _diasRetencionRechazados,
                    ),
                    if (i < marcas.length - 1) const SizedBox(height: 10),
                  ],
                ],
              );
        return _CalidadSectionPanel(
          titulo: showRejectedOnly
              ? 'Documentos de marca rechazados'
              : 'Documentos de marca en revisión',
          subtitulo: showRejectedOnly
              ? 'Fichas técnicas y registros sanitarios que deben reemplazarse.'
              : 'Los archivos nuevos o reemplazados esperan decisión de Calidad.',
          icon: Icons.local_offer_outlined,
          color: color,
          count: marcas.length,
          child: child,
        );
      },
    );
  }

  Widget _buildProveedoresSection({required bool showRejectedOnly}) {
    final color = const Color(0xFF7B3F00);
    return StreamBuilder<List<ProveedorDoc>>(
      stream: widget.svc.streamProveedores(widget.empresaId),
      builder: (_, snap) {
        final proveedores = (snap.data ?? [])
            .where(
              (p) => _proveedorTieneDocsPorEstado(
                p,
                showRejectedOnly: showRejectedOnly,
              ),
            )
            .where(_coincideProveedor)
            .toList();

        Widget child;
        if (_cargandoReq) {
          child = const _CalidadLoadingState(
            message: 'Cargando reglas de proveedores...',
          );
        } else if (proveedores.isEmpty) {
          child = _CalidadEmptyState(
            icon: Icons.business_center_outlined,
            message: showRejectedOnly
                ? 'No hay rechazados vigentes de proveedores.'
                : 'No hay documentos de proveedores pendientes.',
          );
        } else {
          child = Column(
            children: [
              for (var i = 0; i < proveedores.length; i++) ...[
                _ProveedorCalidadCard(
                  proveedor: proveedores[i],
                  svc: widget.svc,
                  userId: widget.userId,
                  reqEngine: _reqEngine,
                  showRejectedOnly: showRejectedOnly,
                  retentionDays: _diasRetencionRechazados,
                ),
                if (i < proveedores.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return _CalidadSectionPanel(
          titulo: showRejectedOnly
              ? 'Proveedores rechazados'
              : 'Proveedores en revisión',
          subtitulo: showRejectedOnly
              ? 'Los archivos rechazados se mantienen aparte para no mezclar la revisión activa.'
              : 'Todo lo que suben los proveedores queda agrupado aquí en un solo bloque.',
          icon: Icons.business,
          color: color,
          count: proveedores.length,
          child: child,
        );
      },
    );
  }

  Widget _buildFichasSection({required bool showRejectedOnly}) {
    final color = const Color(0xFF0277BD);
    final stream = showRejectedOnly
        ? widget.svc.streamFichasTecnicas(widget.empresaId)
        : widget.svc.streamFichasTecnicasPendientes(widget.empresaId);

    return StreamBuilder<List<FichaTecnicaDoc>>(
      stream: stream,
      builder: (_, snap) {
        final fichas = (snap.data ?? [])
            .where(
              (f) => _fichaTieneDocPorEstado(
                f,
                showRejectedOnly: showRejectedOnly,
              ),
            )
            .where(_coincideFicha)
            .toList();

        final child = fichas.isEmpty
            ? _CalidadEmptyState(
                icon: Icons.description_outlined,
                message: showRejectedOnly
                    ? 'No hay fichas técnicas rechazadas vigentes.'
                    : 'No hay fichas técnicas pendientes.',
              )
            : Column(
                children: [
                  for (var i = 0; i < fichas.length; i++) ...[
                    _FichaCalidadCard(
                      ficha: fichas[i],
                      svc: widget.svc,
                      userId: widget.userId,
                      showRejectedOnly: showRejectedOnly,
                      retentionDays: _diasRetencionRechazados,
                    ),
                    if (i < fichas.length - 1) const SizedBox(height: 10),
                  ],
                ],
              );

        return _CalidadSectionPanel(
          titulo: showRejectedOnly
              ? 'Fichas rechazadas'
              : 'Fichas técnicas pendientes',
          subtitulo: showRejectedOnly
              ? 'Se muestran separadas hasta que sean reemplazadas o se eliminen solas.'
              : 'Fichas cargadas para revisión de Calidad.',
          icon: Icons.description,
          color: color,
          count: fichas.length,
          child: child,
        );
      },
    );
  }

  Widget _buildRecepcionesConsultaTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF93C5FD)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Color(0xFF1D4ED8), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Consulta de documentos que cambian en cada recepción o lote. Calidad puede revisarlos y rechazarlos, pero no aprobarlos.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Color(0xFF1E3A8A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildRecepcionesConsultaSection(),
      ],
    );
  }

  Widget _buildRecepcionesConsultaSection() {
    Widget child;
    if (_cargandoReq) {
      child = const _CalidadLoadingState(
        message: 'Cargando reglas de recepciones...',
      );
    } else {
      child = StreamBuilder<List<RecepcionDoc>>(
        stream: widget.svc.streamRecepciones(widget.empresaId),
        builder: (_, snap) {
          var recepciones = (snap.data ?? [])
              .where(_recepcionTieneDocumentosTransitorios)
              .where(_coincideRecepcion)
              .toList();

          if (_filtroFecha != null) {
            recepciones = recepciones.where((r) {
              final fecha = r.fecha.toDate();
              return fecha.year == _filtroFecha!.year &&
                  fecha.month == _filtroFecha!.month &&
                  fecha.day == _filtroFecha!.day;
            }).toList();
          }

          if (recepciones.isEmpty) {
            return const _CalidadEmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'No hay documentos transitorios para consultar.',
            );
          }

          return Column(
            children: [
              for (var i = 0; i < recepciones.length; i++) ...[
                _RecepcionCalidadCard(
                  recepcion: recepciones[i],
                  svc: widget.svc,
                  userId: widget.userId,
                  filtroProducto: _filtroProducto,
                  reqEngine: _reqEngine,
                  consultaTransitorios: true,
                  retentionDays: _diasRetencionRechazados,
                ),
                if (i < recepciones.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        },
      );
    }

    return _CalidadSectionPanel(
      titulo: 'Documentos de recepción',
      subtitulo:
          'Guías, certificados, declaraciones y evidencias por lote o entrada.',
      icon: Icons.local_shipping_outlined,
      color: const Color(0xFF1D4ED8),
      child: child,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Resumen" es el dashboard documental del módulo (todos los roles con
    // acceso a esta pantalla). "Aprobados" existe solo para el Admin
    // Documental: es el único lugar donde los documentos ya aprobados vuelven
    // a ser visibles, para poder corregir una aprobación dada por error.
    final esAdmin = widget.esAdmin;
    final tabBarScrollable = MediaQuery.of(context).size.width < 700;
    return DefaultTabController(
      length: esAdmin ? 5 : 4,
      child: Scaffold(
        backgroundColor: kComprasBg,
        appBar: AppBar(
          title: const Text(
            'Documentos pendientes',
            style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF15803D),
          foregroundColor: Colors.white,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(54),
            child: Container(
              decoration: const BoxDecoration(color: Color(0xFF126E35)),
              child: TabBar(
                isScrollable: tabBarScrollable,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  border: const Border(
                    bottom: BorderSide(color: Colors.white, width: 3),
                  ),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFFD7F2DE),
                labelPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
                labelStyle: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  const Tab(text: 'Resumen'),
                  const Tab(text: 'Pendientes'),
                  const Tab(text: 'Recepción'),
                  const Tab(text: 'Rechazados'),
                  if (esAdmin) const Tab(text: 'Aprobados'),
                ],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            _buildFiltros(),
            _buildFechaFiltradaBanner(),
            if (_depurandoRechazados)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: TabBarView(
                children: [
                  _ResumenCalidadTab(
                    svc: widget.svc,
                    empresaId: widget.empresaId,
                    esAdmin: esAdmin,
                    reqEngine: _reqEngine,
                    cargandoReq: _cargandoReq,
                  ),
                  _buildPendientesTab(),
                  _buildRecepcionesConsultaTab(),
                  _buildRechazadosTab(),
                  if (esAdmin)
                    _AprobadosAdminTab(
                      svc: widget.svc,
                      empresaId: widget.empresaId,
                      userId: widget.userId,
                      filtro: _filtroProducto,
                      filtroFecha: _filtroFecha,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RESUMEN — dashboard documental del módulo de Compras
//
// Responde de un vistazo: qué falta por subir, cuánto hay por revisar, cuánto
// se aprobó, cuánto se rechazó y cómo van las vigencias. Los números salen de
// las mismas colecciones que alimentan las otras pestañas.
// ══════════════════════════════════════════════════════════════════════════════

/// Números agregados del estado documental. Cálculo puro sobre las listas ya
/// cargadas — sin lecturas extra a Firestore.
class _ResumenDocumental {
  final int provPendientes, provAprobados, provRechazados;
  final int recPendientes, recAprobados, recRechazados, recTransitorios;
  final int fichasPendientes, fichasAprobadas, fichasRechazadas;
  final int vigVencidos, vigProximos, vigSinFecha;
  final int faltanDocs;
  final int conRequerimientos;

  /// razonSocial → etiquetas de los documentos requeridos que faltan.
  final List<MapEntry<String, List<String>>> incompletos;

  /// descripción de la marca → cuál de sus dos documentos falta
  /// (ficha técnica / registro sanitario).
  final List<MapEntry<String, List<String>>> marcasIncompletas;

  // Detalle de cada indicador, para los tooltips ("cuáles son").
  final List<String> provPendientesItems;
  final List<String> recPendientesItems;
  final List<String> recTransitoriosItems;
  final List<String> fichasPendientesItems;
  final List<String> vigVencidosItems;
  final List<String> vigProximosItems;
  final List<String> vigSinFechaItems;
  final List<String> conRequerimientosItems;

  const _ResumenDocumental({
    required this.provPendientes,
    required this.provAprobados,
    required this.provRechazados,
    required this.recPendientes,
    required this.recAprobados,
    required this.recRechazados,
    required this.recTransitorios,
    required this.fichasPendientes,
    required this.fichasAprobadas,
    required this.fichasRechazadas,
    required this.vigVencidos,
    required this.vigProximos,
    required this.vigSinFecha,
    required this.faltanDocs,
    required this.conRequerimientos,
    required this.incompletos,
    required this.marcasIncompletas,
    required this.provPendientesItems,
    required this.recPendientesItems,
    required this.recTransitoriosItems,
    required this.fichasPendientesItems,
    required this.vigVencidosItems,
    required this.vigProximosItems,
    required this.vigSinFechaItems,
    required this.conRequerimientosItems,
  });

  int get aprobados => provAprobados + recAprobados + fichasAprobadas;
  int get rechazados => provRechazados + recRechazados + fichasRechazadas;

  static _ResumenDocumental calcular({
    required List<ProveedorDoc> proveedores,
    required List<RecepcionDoc> recepciones,
    required List<FichaTecnicaDoc> fichas,
    required List<MarcaDoc> marcas,
    required ReqEngine? engine,
  }) {
    final hoy = DateTime.now();
    final hoy0 = DateTime(hoy.year, hoy.month, hoy.day);

    var provPend = 0, provApr = 0, provRech = 0;
    var vigVenc = 0, vigProx = 0, vigSin = 0;
    var faltanDocs = 0;
    var conReq = 0;
    final incompletos = <MapEntry<String, List<String>>>[];
    final provPendItems = <String>[];
    final recPendItems = <String>[];
    final recTransItems = <String>[];
    final fichasPendItems = <String>[];
    final vigVencItems = <String>[];
    final vigProxItems = <String>[];
    final vigSinItems = <String>[];
    final conReqItems = <String>[];

    void contarVigencia(String docKey, String etiqueta, DocAdjunto d) {
      if (!documentoRequiereVigencia(docKey) || !d.tieneDoc) return;
      final f = d.fechaVencimiento?.toDate();
      if (f == null) {
        vigSin++;
        vigSinItems.add(etiqueta);
        return;
      }
      final dias = DateTime(f.year, f.month, f.day).difference(hoy0).inDays;
      if (dias < 0) {
        vigVenc++;
        vigVencItems.add('$etiqueta (${DateFormat('dd/MM/yyyy').format(f)})');
      } else if (dias <= 30) {
        vigProx++;
        vigProxItems.add('$etiqueta (${DateFormat('dd/MM/yyyy').format(f)})');
      }
    }

    for (final p in proveedores) {
      // Requeridos: motor de reglas por categoría; si la empresa aún no lo
      // configura, al menos los obligatorios de siempre (RUT y Cámara).
      final reqKeys = (engine != null && !engine.isEmpty)
          ? engine.docsProveedor(p.categorias).map((r) => r.keyApp).toList()
          : List<String>.of(kDocumentosProveedorObligatorios);
      final faltan = <String>[];
      for (final key in reqKeys) {
        if (kDocProveedorOcultos.contains(key)) continue;
        if (p.documentos[key]?.tieneDoc != true) {
          faltan.add(kDocProveedorLabels[key] ?? key);
        }
      }
      if (faltan.isNotEmpty) {
        faltanDocs += faltan.length;
        incompletos.add(MapEntry(p.razonSocial, faltan));
      }

      for (final e in p.documentos.entries) {
        if (kDocProveedorOcultos.contains(e.key)) continue;
        final d = e.value;
        if (!d.tieneDoc) continue;
        final etiqueta =
            '${kDocProveedorLabels[e.key] ?? e.key} — ${p.razonSocial}';
        if (d.aprobadoConRequerimientos) {
          conReq++;
          conReqItems.add(etiqueta);
        } else if (d.aprobado) {
          provApr++;
        } else if (d.rechazado) {
          provRech++;
        } else {
          provPend++;
          provPendItems.add(etiqueta);
        }
        contarVigencia(e.key, etiqueta, d);
      }
    }

    var recPend = 0, recApr = 0, recRech = 0, recTrans = 0;
    for (final r in recepciones) {
      final fechaRec = DateFormat('dd/MM/yyyy').format(r.fecha.toDate());
      for (final prod in r.productos) {
        for (final e in prod.documentos.entries) {
          final d = e.value;
          if (!d.tieneDoc) continue;
          final etiqueta =
              '${kDocRecepcionLabels[e.key] ?? e.key} — ${prod.nombre} · '
              '${r.razonSocial} ($fechaRec)';
          contarVigencia(e.key, etiqueta, d);
          if (d.rechazado) {
            recRech++;
            continue;
          }
          if (esDocumentoTransitorioRecepcion(e.key)) {
            // Mismo criterio que la pestaña "Recepción": pendiente hasta que
            // Calidad lo marque como consultado.
            if (d.estadoCalidad != 'consultado') {
              recTrans++;
              recTransItems.add(etiqueta);
            }
          } else if (d.aprobadoConRequerimientos) {
            conReq++;
            conReqItems.add(etiqueta);
          } else if (d.aprobado) {
            recApr++;
          } else {
            recPend++;
            recPendItems.add(etiqueta);
          }
        }
      }
    }

    var ficPend = 0, ficApr = 0, ficRech = 0;
    for (final f in fichas) {
      final d = f.documentoActual;
      if (d == null || !d.tieneDoc) continue;
      if (d.aprobadoConRequerimientos) {
        conReq++;
        conReqItems.add(
          f.marcaNombre.isEmpty
              ? '${f.productoNombre} — ${f.proveedorNombre}'
              : '${f.productoNombre} / ${f.marcaNombre} — ${f.proveedorNombre}',
        );
      } else if (d.aprobado) {
        ficApr++;
      } else if (d.rechazado) {
        ficRech++;
      } else {
        ficPend++;
        fichasPendItems.add(
          f.marcaNombre.isEmpty
              ? '${f.productoNombre} — ${f.proveedorNombre}'
              : '${f.productoNombre} / ${f.marcaNombre} — ${f.proveedorNombre}',
        );
      }
    }

    // Marcas: ficha técnica y registro sanitario forman parte de la misma cola
    // de Calidad. Además de indicar faltantes, sus estados alimentan los
    // semáforos del resumen para que coincidan con la pestaña Pendientes.
    final marcasIncompletas = <MapEntry<String, List<String>>>[];
    for (final m in marcas) {
      final faltan = <String>[
        for (final e in kDocumentosAsociadosLabels.entries)
          if (m.documentosAsociados[e.key]?.tieneDoc != true) e.value,
      ];
      if (faltan.isNotEmpty) {
        marcasIncompletas.add(MapEntry(m.descripcion, faltan));
      }
      for (final entry in m.documentosAsociados.entries) {
        final doc = entry.value;
        if (!doc.tieneDoc) continue;
        final etiqueta =
            '${kDocumentosAsociadosLabels[entry.key] ?? entry.key} — ${m.descripcion}';
        if (doc.aprobadoConRequerimientos) {
          conReq++;
          conReqItems.add(etiqueta);
        } else if (doc.aprobado) {
          ficApr++;
        } else if (doc.rechazado) {
          ficRech++;
        } else {
          ficPend++;
          fichasPendItems.add(etiqueta);
        }
        contarVigencia(entry.key, etiqueta, doc);
      }
    }

    // Los más incompletos primero.
    incompletos.sort((a, b) => b.value.length.compareTo(a.value.length));
    marcasIncompletas.sort((a, b) => b.value.length.compareTo(a.value.length));

    return _ResumenDocumental(
      provPendientes: provPend,
      provAprobados: provApr,
      provRechazados: provRech,
      recPendientes: recPend,
      recAprobados: recApr,
      recRechazados: recRech,
      recTransitorios: recTrans,
      fichasPendientes: ficPend,
      fichasAprobadas: ficApr,
      fichasRechazadas: ficRech,
      vigVencidos: vigVenc,
      vigProximos: vigProx,
      vigSinFecha: vigSin,
      faltanDocs: faltanDocs,
      conRequerimientos: conReq,
      incompletos: incompletos,
      marcasIncompletas: marcasIncompletas,
      provPendientesItems: provPendItems,
      recPendientesItems: recPendItems,
      recTransitoriosItems: recTransItems,
      fichasPendientesItems: fichasPendItems,
      vigVencidosItems: vigVencItems,
      vigProximosItems: vigProxItems,
      vigSinFechaItems: vigSinItems,
      conRequerimientosItems: conReqItems,
    );
  }
}

/// Arma el texto del tooltip: viñetas con las primeras [max] entradas.
String _resumenTooltip(List<String> items, {int max = 12}) {
  if (items.isEmpty) return '';
  final visibles = items.take(max).map((e) => '• $e').join('\n');
  final resto = items.length - max;
  return resto > 0 ? '$visibles\n… y $resto más' : visibles;
}

/// Tarjeta de indicador del Resumen. Ancho fijo para componer con Wrap.
class _ResumenStatCard extends StatelessWidget {
  final String valor;
  final String label;
  final String? detalle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  /// Al pasar el mouse (o dejar presionado en móvil) muestra el detalle de
  /// QUÉ documentos componen el número — pedido explícito del usuario.
  final String? tooltip;

  const _ResumenStatCard({
    required this.valor,
    required this.label,
    this.detalle,
    required this.icon,
    required this.color,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 176,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const Spacer(),
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: color.withValues(alpha: 0.7),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (detalle != null) ...[
            const SizedBox(height: 2),
            Text(
              detalle!,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 9.5,
                color: Colors.black54,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
    Widget result = onTap == null
        ? card
        : InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: card,
          );
    if (tooltip != null && tooltip!.isNotEmpty) {
      result = Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 350),
        textStyle: const TextStyle(
          fontFamily: _kFont,
          fontSize: 11.5,
          color: Colors.white,
          height: 1.45,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: result,
      );
    }
    return result;
  }
}

class _ResumenCalidadTab extends StatelessWidget {
  final ComprasService svc;
  final String empresaId;
  final bool esAdmin;
  final ReqEngine? reqEngine;
  final bool cargandoReq;

  const _ResumenCalidadTab({
    required this.svc,
    required this.empresaId,
    required this.esAdmin,
    required this.reqEngine,
    required this.cargandoReq,
  });

  @override
  Widget build(BuildContext context) {
    if (cargandoReq) {
      return const _CalidadLoadingState(
        message: 'Cargando resumen documental...',
      );
    }
    return StreamBuilder<List<ProveedorDoc>>(
      stream: svc.streamProveedores(empresaId),
      builder: (_, provSnap) => StreamBuilder<List<RecepcionDoc>>(
        stream: svc.streamRecepciones(empresaId),
        builder: (_, recSnap) => StreamBuilder<List<FichaTecnicaDoc>>(
          stream: svc.streamFichasTecnicas(empresaId),
          builder: (_, fichaSnap) => StreamBuilder<List<MarcaDoc>>(
            stream: svc.streamMarcas(empresaId),
            builder: (context, marcaSnap) {
              if (!provSnap.hasData ||
                  !recSnap.hasData ||
                  !fichaSnap.hasData ||
                  !marcaSnap.hasData) {
                return const _CalidadLoadingState(
                  message: 'Calculando resumen documental...',
                );
              }
              final d = _ResumenDocumental.calcular(
                proveedores: provSnap.data!,
                recepciones: recSnap.data!,
                fichas: fichaSnap.data!,
                marcas: marcaSnap.data!,
                engine: reqEngine,
              );
              return _contenido(context, d);
            },
          ),
        ),
      ),
    );
  }

  Widget _contenido(BuildContext context, _ResumenDocumental d) {
    void irATab(int index) => DefaultTabController.of(context).animateTo(index);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _CalidadSectionPanel(
          titulo: 'Revisión de Calidad',
          subtitulo:
              'Estado de los documentos subidos. Pasa el mouse por una '
              'tarjeta para ver cuáles son.',
          icon: Icons.fact_check_outlined,
          color: const Color(0xFF15803D),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ResumenStatCard(
                valor: '${d.provPendientes}',
                label: 'Proveedores por revisar',
                detalle: 'Documentos del expediente',
                icon: Icons.business_center_outlined,
                color: const Color(0xFFB45309),
                onTap: () => irATab(1),
                tooltip: _resumenTooltip(d.provPendientesItems),
              ),
              _ResumenStatCard(
                valor: '${d.fichasPendientes}',
                label: 'Producto y marca por revisar',
                detalle: 'Fichas y registros sanitarios',
                icon: Icons.description_outlined,
                color: const Color(0xFFB45309),
                onTap: () => irATab(1),
                tooltip: _resumenTooltip(d.fichasPendientesItems),
              ),
              _ResumenStatCard(
                valor: '${d.recPendientes}',
                label: 'Recepciones por revisar',
                detalle: 'Documentos permanentes',
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFFB45309),
                onTap: () => irATab(1),
                tooltip: _resumenTooltip(d.recPendientesItems),
              ),
              _ResumenStatCard(
                valor: '${d.recTransitorios}',
                label: 'Recepción por consultar',
                detalle: 'Documentos por lote o entrada',
                icon: Icons.local_shipping_outlined,
                color: const Color(0xFF1D4ED8),
                onTap: () => irATab(2),
                tooltip: _resumenTooltip(d.recTransitoriosItems),
              ),
              _ResumenStatCard(
                valor: '${d.conRequerimientos}',
                label: 'Con requerimientos',
                detalle: 'Utilizables · obligación abierta',
                icon: Icons.rule_folder_outlined,
                color: const Color(0xFFB45309),
                onTap: () => irATab(1),
                tooltip: _resumenTooltip(d.conRequerimientosItems),
              ),
              _ResumenStatCard(
                valor: '${d.aprobados}',
                label: 'Aprobados',
                detalle:
                    'Prov. ${d.provAprobados} · Recep. ${d.recAprobados} · Producto/marca ${d.fichasAprobadas}',
                icon: Icons.verified_outlined,
                color: kComprasGreen,
                onTap: esAdmin ? () => irATab(4) : null,
              ),
              _ResumenStatCard(
                valor: '${d.rechazados}',
                label: 'Rechazados',
                detalle:
                    'Prov. ${d.provRechazados} · Recep. ${d.recRechazados} · Producto/marca ${d.fichasRechazadas}',
                icon: Icons.cancel_outlined,
                color: kComprasRed,
                onTap: () => irATab(3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _CalidadSectionPanel(
          titulo: 'Expediente por completar',
          subtitulo: 'Documentos requeridos que aún no han sido subidos.',
          icon: Icons.upload_file_outlined,
          color: const Color(0xFF7B3F00),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ResumenStatCard(
                    valor: '${d.faltanDocs}',
                    label: 'Documentos faltantes',
                    detalle: 'Según las reglas por categoría',
                    icon: Icons.note_add_outlined,
                    color: const Color(0xFF7B3F00),
                    tooltip: _resumenTooltip([
                      for (final e in d.incompletos)
                        '${e.key}: ${e.value.join(', ')}',
                    ]),
                  ),
                  _ResumenStatCard(
                    valor: '${d.incompletos.length}',
                    label: 'Proveedores incompletos',
                    detalle: 'Con expediente por completar',
                    icon: Icons.business_center_outlined,
                    color: const Color(0xFF7B3F00),
                    tooltip: _resumenTooltip([
                      for (final e in d.incompletos)
                        '${e.key} (faltan ${e.value.length})',
                    ]),
                  ),
                  _ResumenStatCard(
                    valor: '${d.marcasIncompletas.length}',
                    label: 'Marcas por completar',
                    detalle: 'Ficha técnica y Registro sanitario',
                    icon: Icons.label_important_outline,
                    color: const Color(0xFF7B3F00),
                    tooltip: _resumenTooltip([
                      for (final e in d.marcasIncompletas)
                        '${e.key}: falta ${e.value.join(' y ')}',
                    ]),
                  ),
                ],
              ),
              if (d.incompletos.isNotEmpty) ...[
                const Divider(height: 22),
                for (final e in d.incompletos.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.business,
                          size: 13,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.key,
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Faltan ${e.value.length}: ${e.value.join(', ')}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 10.5,
                                  color: Colors.black54,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (d.incompletos.length > 6)
                  Text(
                    '+ ${d.incompletos.length - 6} proveedor(es) más con pendientes.',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 10.5,
                      color: Colors.black45,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _CalidadSectionPanel(
          titulo: 'Vigencias documentales',
          subtitulo: 'Fechas "Vigente hasta" de los documentos cargados.',
          icon: Icons.event_outlined,
          color: const Color(0xFFB45309),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ResumenStatCard(
                    valor: '${d.vigVencidos}',
                    label: 'Vencidos',
                    icon: Icons.event_busy_outlined,
                    color: kComprasRed,
                    onTap: () => _abrirVigencias(context, filtro: 'vencidos'),
                    tooltip: _resumenTooltip(d.vigVencidosItems),
                  ),
                  _ResumenStatCard(
                    valor: '${d.vigProximos}',
                    label: 'Vencen en 30 días',
                    icon: Icons.notification_important_outlined,
                    color: const Color(0xFFB45309),
                    onTap: () => _abrirVigencias(context, filtro: '30'),
                    tooltip: _resumenTooltip(d.vigProximosItems),
                  ),
                  _ResumenStatCard(
                    valor: '${d.vigSinFecha}',
                    label: 'Sin fecha registrada',
                    detalle: 'Requieren "Vigente hasta"',
                    icon: Icons.event_note_outlined,
                    color: const Color(0xFF64748B),
                    onTap: () => _abrirVigencias(context, filtro: 'sin_fecha'),
                    tooltip: _resumenTooltip(d.vigSinFechaItems),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _abrirVigencias(context),
                  icon: const Icon(Icons.calendar_month, size: 16),
                  label: const Text(
                    'Abrir vigencias y calendario',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _abrirVigencias(BuildContext context, {String? filtro}) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              _VencimientosScreen(empresaId: empresaId, filtroInicial: filtro),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// APROBADOS — pestaña exclusiva del Admin Documental
//
// El resto de la pantalla de Calidad filtra los documentos aprobados
// (`!doc.aprobado && !doc.rechazado`), así que esta pestaña es el único lugar
// donde vuelven a verse. Sirve para corregir una aprobación dada por error sin
// tener que descargar el archivo y volverlo a subir.
// ══════════════════════════════════════════════════════════════════════════════

/// Resultado del diálogo de reversión.
class _ReversionDecision {
  final String motivo;

  /// true: el documento queda rechazado y se notifica a quien lo subió.
  /// false: el documento vuelve a la cola de Calidad.
  final bool rechazar;

  const _ReversionDecision({required this.motivo, required this.rechazar});
}

/// Pide el motivo y el destino de la reversión. Devuelve null si se cancela.
Future<_ReversionDecision?> _pedirMotivoReversion(
  BuildContext context, {
  required String docLabel,
  required String contexto,
}) async {
  final ctrl = TextEditingController();
  var rechazar = false;
  var intentoVacio = false;

  final decision = await showDialog<_ReversionDecision>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setLocal) => AlertDialog(
        title: const Text(
          'Revertir aprobación',
          style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                docLabel,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                contexto,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '¿Qué debe pasar con el documento?',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: rechazar,
                onChanged: (v) => setLocal(() => rechazar = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Volver a revisión',
                  style: TextStyle(fontFamily: _kFont, fontSize: 13),
                ),
                subtitle: const Text(
                  'Se aprobó por error. Regresa a la cola de Calidad.',
                  style: TextStyle(fontFamily: _kFont, fontSize: 11),
                ),
              ),
              RadioListTile<bool>(
                value: true,
                groupValue: rechazar,
                onChanged: (v) => setLocal(() => rechazar = v ?? true),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Rechazar',
                  style: TextStyle(fontFamily: _kFont, fontSize: 13),
                ),
                subtitle: const Text(
                  'El documento está malo. Se notifica a quien lo subió y se '
                  'crea la tarea de corrección.',
                  style: TextStyle(fontFamily: _kFont, fontSize: 11),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                maxLines: 3,
                autofocus: true,
                style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Motivo de la reversión',
                  hintText: 'Queda registrado en el documento.',
                  errorText: intentoVacio ? 'El motivo es obligatorio.' : null,
                  border: const OutlineInputBorder(),
                  labelStyle: const TextStyle(fontFamily: _kFont),
                  hintStyle: const TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
                onChanged: (_) {
                  if (intentoVacio) setLocal(() => intentoVacio = false);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar', style: TextStyle(fontFamily: _kFont)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: rechazar ? kComprasRed : const Color(0xFFB45309),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final motivo = ctrl.text.trim();
              if (motivo.isEmpty) {
                setLocal(() => intentoVacio = true);
                return;
              }
              Navigator.pop(
                dialogCtx,
                _ReversionDecision(motivo: motivo, rechazar: rechazar),
              );
            },
            child: Text(
              rechazar ? 'Revertir y rechazar' : 'Revertir a revisión',
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  ctrl.dispose();
  return decision;
}

class _AprobadosAdminTab extends StatelessWidget {
  final ComprasService svc;
  final String empresaId;
  final String userId;
  final String filtro;
  final DateTime? filtroFecha;

  const _AprobadosAdminTab({
    required this.svc,
    required this.empresaId,
    required this.userId,
    required this.filtro,
    this.filtroFecha,
  });

  bool _coincide(String value) {
    final f = filtro.trim().toLowerCase();
    if (f.isEmpty) return true;
    return value.toLowerCase().contains(f);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
            ),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                color: Color(0xFFB45309),
                size: 18,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Documentos ya aprobados. Usa "Revertir" solo para corregir '
                  'una aprobación dada por error: queda registrado quién la '
                  'revirtió, cuándo y por qué.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildProveedoresAprobados(context),
        const SizedBox(height: 14),
        _buildFichasAprobadas(context),
        const SizedBox(height: 14),
        _buildRecepcionesAprobadas(context),
      ],
    );
  }

  Widget _buildProveedoresAprobados(BuildContext context) {
    return _CalidadSectionPanel(
      titulo: 'Proveedores',
      subtitulo: 'Documentos del expediente del proveedor ya aprobados.',
      icon: Icons.business_center_outlined,
      color: const Color(0xFF7B3F00),
      child: StreamBuilder<List<ProveedorDoc>>(
        stream: svc.streamProveedores(empresaId),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const _CalidadLoadingState(
              message: 'Cargando proveedores...',
            );
          }
          final proveedores = snap.data!
              .where((p) => _coincide(p.razonSocial) || _coincide(p.nit))
              .where(
                (p) => p.documentos.entries.any(
                  (e) =>
                      !kDocProveedorOcultos.contains(e.key) &&
                      e.value.aprobado &&
                      e.value.tieneDoc,
                ),
              )
              .toList();

          if (proveedores.isEmpty) {
            return const _CalidadEmptyState(
              icon: Icons.business_center_outlined,
              message: 'No hay documentos de proveedores aprobados.',
            );
          }

          return Column(
            children: [
              for (final p in proveedores)
                _AprobadoGrupo(
                  titulo: p.razonSocial,
                  subtitulo: 'NIT ${p.nit}',
                  filas: [
                    for (final e in p.documentos.entries)
                      if (!kDocProveedorOcultos.contains(e.key) &&
                          e.value.aprobado &&
                          e.value.tieneDoc)
                        _AprobadoFila(
                          label: kDocProveedorLabels[e.key] ?? e.key,
                          doc: e.value,
                          onRevertir: () => _revertirProveedor(
                            context,
                            proveedorId: p.id,
                            razonSocial: p.razonSocial,
                            docKey: e.key,
                          ),
                        ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRecepcionesAprobadas(BuildContext context) {
    return _CalidadSectionPanel(
      titulo: 'Recepciones',
      subtitulo: 'Documentos permanentes de recepción ya aprobados.',
      icon: Icons.local_shipping_outlined,
      color: const Color(0xFF1D4ED8),
      child: StreamBuilder<List<RecepcionDoc>>(
        stream: svc.streamRecepciones(empresaId),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const _CalidadLoadingState(
              message: 'Cargando recepciones...',
            );
          }
          var recepciones = snap.data!
              .where(
                (r) =>
                    _coincide(r.razonSocial) ||
                    _coincide(r.nit) ||
                    _coincide(r.ordenCompra) ||
                    r.productos.any((p) => _coincide(p.nombre)),
              )
              .where(
                (r) => r.productos.any(
                  (p) =>
                      p.documentos.values.any((d) => d.aprobado && d.tieneDoc),
                ),
              )
              .toList();

          if (filtroFecha != null) {
            recepciones = recepciones.where((r) {
              final f = r.fecha.toDate();
              return f.year == filtroFecha!.year &&
                  f.month == filtroFecha!.month &&
                  f.day == filtroFecha!.day;
            }).toList();
          }

          if (recepciones.isEmpty) {
            return const _CalidadEmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'No hay documentos de recepción aprobados.',
            );
          }

          return Column(
            children: [
              for (final r in recepciones)
                _AprobadoGrupo(
                  titulo: r.razonSocial,
                  subtitulo:
                      'Recepción ${DateFormat('dd/MM/yyyy', 'es').format(r.fecha.toDate())}'
                      '${r.ordenCompra.trim().isEmpty ? '' : ' · OC ${r.ordenCompra}'}',
                  filas: [
                    for (var i = 0; i < r.productos.length; i++)
                      for (final e in r.productos[i].documentos.entries)
                        if (e.value.aprobado && e.value.tieneDoc)
                          _AprobadoFila(
                            label:
                                '${r.productos[i].nombre} · '
                                '${kDocRecepcionLabels[e.key] ?? e.key}',
                            doc: e.value,
                            onRevertir: () => _revertirRecepcion(
                              context,
                              recepcion: r,
                              productoIdx: i,
                              docKey: e.key,
                              productoNombre: r.productos[i].nombre,
                            ),
                          ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFichasAprobadas(BuildContext context) {
    return _CalidadSectionPanel(
      titulo: 'Fichas técnicas',
      subtitulo:
          'Fichas aprobadas que pueden volver a revisión o quedar rechazadas.',
      icon: Icons.description_outlined,
      color: const Color(0xFF0277BD),
      child: StreamBuilder<List<FichaTecnicaDoc>>(
        stream: svc.streamFichasTecnicas(empresaId),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const _CalidadLoadingState(
              message: 'Cargando fichas técnicas...',
            );
          }
          final fichas = snap.data!
              .where(
                (ficha) =>
                    ficha.documentoActual?.aprobado == true &&
                    ficha.documentoActual?.tieneDoc == true &&
                    (_coincide(ficha.productoNombre) ||
                        _coincide(ficha.marcaNombre) ||
                        _coincide(ficha.proveedorNombre)),
              )
              .toList();

          if (fichas.isEmpty) {
            return const _CalidadEmptyState(
              icon: Icons.description_outlined,
              message: 'No hay fichas técnicas aprobadas.',
            );
          }

          return Column(
            children: [
              for (final ficha in fichas)
                _AprobadoGrupo(
                  titulo: ficha.productoNombre,
                  subtitulo: [
                    ficha.marcaNombre,
                    ficha.proveedorNombre,
                  ].where((value) => value.trim().isNotEmpty).join(' · '),
                  filas: [
                    _AprobadoFila(
                      label: 'Ficha técnica',
                      doc: ficha.documentoActual!,
                      onRevertir: () => _revertirFicha(context, ficha: ficha),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _revertirProveedor(
    BuildContext context, {
    required String proveedorId,
    required String razonSocial,
    required String docKey,
  }) async {
    final decision = await _pedirMotivoReversion(
      context,
      docLabel: kDocProveedorLabels[docKey] ?? docKey,
      contexto: razonSocial,
    );
    if (decision == null) return;
    if (!context.mounted) return;
    try {
      await svc.revertirAprobacionDocProveedor(
        proveedorId: proveedorId,
        docKey: docKey,
        motivo: decision.motivo,
        revertidoPor: userId,
        rechazar: decision.rechazar,
      );
      if (!context.mounted) return;
      _avisoReversion(context, decision.rechazar);
    } catch (e) {
      if (!context.mounted) return;
      _avisoError(context, e);
    }
  }

  Future<void> _revertirFicha(
    BuildContext context, {
    required FichaTecnicaDoc ficha,
  }) async {
    final decision = await _pedirMotivoReversion(
      context,
      docLabel: 'Ficha técnica',
      contexto: [
        ficha.productoNombre,
        ficha.marcaNombre,
        ficha.proveedorNombre,
      ].where((value) => value.trim().isNotEmpty).join(' · '),
    );
    if (decision == null || !context.mounted) return;
    try {
      await svc.revertirAprobacionFichaTecnica(
        fichaId: ficha.id,
        motivo: decision.motivo,
        revertidoPor: userId,
        rechazar: decision.rechazar,
      );
      if (!context.mounted) return;
      _avisoReversion(context, decision.rechazar);
    } catch (error) {
      if (!context.mounted) return;
      _avisoError(context, error);
    }
  }

  Future<void> _revertirRecepcion(
    BuildContext context, {
    required RecepcionDoc recepcion,
    required int productoIdx,
    required String docKey,
    required String productoNombre,
  }) async {
    final decision = await _pedirMotivoReversion(
      context,
      docLabel: kDocRecepcionLabels[docKey] ?? docKey,
      contexto: '$productoNombre · ${recepcion.razonSocial}',
    );
    if (decision == null) return;
    if (!context.mounted) return;
    try {
      await svc.revertirAprobacionDocRecepcion(
        recepcion: recepcion,
        productoIdx: productoIdx,
        docKey: docKey,
        motivo: decision.motivo,
        revertidoPor: userId,
        rechazar: decision.rechazar,
      );
      if (!context.mounted) return;
      _avisoReversion(context, decision.rechazar);
    } catch (e) {
      if (!context.mounted) return;
      _avisoError(context, e);
    }
  }

  void _avisoReversion(BuildContext context, bool rechazar) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: rechazar ? kComprasRed : const Color(0xFFB45309),
        content: Text(
          rechazar
              ? 'Aprobación revertida. El documento quedó rechazado y se '
                    'notificó a quien lo subió.'
              : 'Aprobación revertida. El documento volvió a la cola de Calidad.',
          style: const TextStyle(fontFamily: _kFont),
        ),
      ),
    );
  }

  void _avisoError(BuildContext context, Object e) {
    final mensaje = e is StateError ? e.message : e.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: kComprasRed,
        content: Text(
          'No se pudo revertir: $mensaje',
          style: const TextStyle(fontFamily: _kFont),
        ),
      ),
    );
  }
}

/// Agrupa las filas aprobadas de un proveedor o de una recepción.
class _AprobadoGrupo extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final List<Widget> filas;

  const _AprobadoGrupo({
    required this.titulo,
    required this.subtitulo,
    required this.filas,
  });

  @override
  Widget build(BuildContext context) {
    if (filas.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            Text(
              subtitulo,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 11,
                color: Colors.black54,
              ),
            ),
            const Divider(height: 18),
            ...filas,
          ],
        ),
      ),
    );
  }
}

/// Una fila de documento aprobado con su botón de reversión.
class _AprobadoFila extends StatelessWidget {
  final String label;
  final DocAdjunto doc;
  final VoidCallback onRevertir;

  const _AprobadoFila({
    required this.label,
    required this.doc,
    required this.onRevertir,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, size: 14, color: kComprasGreen),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
              ),
              if (doc.tieneDoc)
                IconButton(
                  onPressed: () async {
                    final uri = Uri.tryParse(doc.url ?? '');
                    if (uri == null) return;
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: Colors.blue,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: 'Ver documento',
                ),
              const SizedBox(width: 4),
              // Botón compacto de ancho intrínseco. NO usar _CalidadActionButton
              // aquí: su minimumSize Size.fromHeight(42) implica ancho infinito
              // y dentro de un Row aplasta al Expanded del label.
              OutlinedButton.icon(
                onPressed: onRevertir,
                icon: const Icon(Icons.undo, size: 14),
                label: const Text('Revertir'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB45309),
                  side: BorderSide(
                    color: const Color(0xFFB45309).withValues(alpha: 0.6),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (doc.tuvoReversion)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(
                'Ya tuvo una reversión previa'
                '${doc.motivoReversion == null ? '' : ': ${doc.motivoReversion}'}',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 10,
                  color: Colors.orange.shade800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FICHA TÉCNICA CARD para pantalla de Calidad
// ══════════════════════════════════════════════════════════════════════════════

class _FichaCalidadCard extends StatelessWidget {
  final FichaTecnicaDoc ficha;
  final ComprasService svc;
  final String userId;
  final bool showRejectedOnly;
  final int retentionDays;

  const _FichaCalidadCard({
    required this.ficha,
    required this.svc,
    required this.userId,
    this.showRejectedOnly = false,
    this.retentionDays = 8,
  });

  String? _fechaEliminacion(DocAdjunto? doc) {
    final fecha = doc?.fechaRevision?.toDate();
    if (fecha == null) return null;
    return DateFormat(
      'dd/MM/yyyy',
      'es',
    ).format(fecha.add(Duration(days: retentionDays)));
  }

  String? _fechaRevision(DocAdjunto? doc) {
    final fecha = doc?.fechaRevision?.toDate();
    if (fecha == null) return null;
    return DateFormat('dd/MM/yyyy', 'es').format(fecha);
  }

  Future<void> _aprobar(BuildContext context) async {
    try {
      await svc.aprobarFichaTecnica(fichaId: ficha.id, revisadoPor: userId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ficha técnica aprobada.',
            style: TextStyle(fontFamily: _kFont),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: $e',
            style: const TextStyle(fontFamily: _kFont),
          ),
        ),
      );
    }
  }

  Future<void> _aprobarConRequerimientos(BuildContext context) async {
    final decision = await _pedirRequerimientoCalidad(
      context,
      'Ficha técnica de ${ficha.productoNombre}${ficha.marcaNombre.isEmpty ? '' : ' / ${ficha.marcaNombre}'}',
    );
    if (decision == null) return;
    try {
      await svc.aprobarConRequerimientosFichaTecnica(
        fichaId: ficha.id,
        nota: decision.nota,
        requiereAdjunto: decision.requiereAdjunto,
        fechaLimite: decision.fechaLimite,
        revisadoPor: userId,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ficha aceptada con requerimiento y tarea asignada.'),
          backgroundColor: Color(0xFFB45309),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No fue posible registrar: $error')),
        );
      }
    }
  }

  Future<void> _rechazar(BuildContext context) async {
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: _comprasDialogTitle(
          ctx,
          'Rechazar ficha técnica',
          icon: Icons.cancel_outlined,
        ),
        content: SingleChildScrollView(
          child: TextField(
            controller: motivoCtrl,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Motivo del rechazo *',
              labelStyle: TextStyle(fontFamily: _kFont),
              border: OutlineInputBorder(),
              hintText: 'Describe el motivo del rechazo...',
            ),
            style: const TextStyle(fontFamily: _kFont),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(fontFamily: _kFont)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kComprasRed),
            onPressed: () {
              if (motivoCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text(
              'Rechazar',
              style: TextStyle(fontFamily: _kFont, color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (ok != true || motivoCtrl.text.trim().isEmpty) return;
    try {
      await svc.rechazarFichaTecnica(
        fichaId: ficha.id,
        motivo: motivoCtrl.text.trim(),
        revisadoPor: userId,
        creadoPor: ficha.creadoPor,
        empresaId: ficha.empresaId,
        productoNombre: ficha.productoNombre,
        marcaNombre: ficha.marcaNombre,
        proveedorNombre: ficha.proveedorNombre,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ficha técnica rechazada. Se notificó al usuario.',
            style: TextStyle(fontFamily: _kFont),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: $e',
            style: const TextStyle(fontFamily: _kFont),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = ficha.documentoActual;
    final fechaRechazo = _fechaRevision(doc);
    final fechaEliminacion = _fechaEliminacion(doc);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF90CAF9), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  size: 20,
                  color: Color(0xFF0277BD),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ficha.productoNombre,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (ficha.marcaNombre.isNotEmpty)
              Text(
                'Marca: ${ficha.marcaNombre}',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            Text(
              'Proveedor: ${ficha.proveedorNombre}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
            if ((doc?.subidoPor ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 12,
                    color: Colors.black45,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: UserNameText(
                      doc!.subidoPor!.trim(),
                      prefix: 'Subió: ',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (showRejectedOnly)
                  _Chip('Rechazada', kComprasRed)
                else if (doc?.aprobadoConRequerimientos == true)
                  _Chip('Aprobada con requerimientos', const Color(0xFFB45309))
                else
                  _Chip('Pendiente', const Color(0xFFB45309)),
                if (fechaRechazo != null && showRejectedOnly)
                  _Chip('Revisada: $fechaRechazo', const Color(0xFFB91C1C)),
                if (fechaEliminacion != null && showRejectedOnly)
                  _Chip(
                    'Se elimina: $fechaEliminacion',
                    const Color(0xFFB45309),
                  ),
              ],
            ),
            if (doc?.observacionActualizacion?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Color(0xFFB45309),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Obs. actualización: ${doc!.observacionActualizacion}',
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (showRejectedOnly &&
                doc?.observacionCalidad?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  'Motivo del rechazo: ${doc!.observacionCalidad!.trim()}',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (doc?.tieneDoc == true)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _abrirUrl(context, doc!.url),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text(
                    'Ver PDF',
                    style: TextStyle(fontFamily: _kFont, fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
              ),
            if (!showRejectedOnly) ...[
              if (doc?.tieneDoc == true) const SizedBox(height: 10),
              if (doc?.aprobadoConRequerimientos == true)
                _RequerimientoCalidadView(
                  doc: doc!,
                  label: 'Ficha técnica',
                  onView: () => _abrirUrl(context, doc.url),
                  onClose: () => _aprobar(context),
                )
              else
                _CalidadDecisionButtons(
                  onApprove: () => _aprobar(context),
                  onApproveWithRequirements: () =>
                      _aprobarConRequerimientos(context),
                  onReject: () => _rechazar(context),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CalidadDecisionButtons extends StatelessWidget {
  final VoidCallback onApprove;
  final VoidCallback onApproveWithRequirements;
  final VoidCallback onReject;

  const _CalidadDecisionButtons({
    required this.onApprove,
    required this.onApproveWithRequirements,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final approve = _CalidadActionButton(
      label: 'Aprobar',
      icon: Icons.check_circle,
      color: kComprasGreen,
      onPressed: onApprove,
    );
    final reject = _CalidadActionButton(
      label: 'Rechazar',
      icon: Icons.cancel,
      color: kComprasRed,
      onPressed: onReject,
    );
    final conditional = _CalidadActionButton(
      label: 'Aprobar con requerimientos',
      icon: Icons.rule_folder_outlined,
      color: const Color(0xFFB45309),
      onPressed: onApproveWithRequirements,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              approve,
              const SizedBox(height: 8),
              conditional,
              const SizedBox(height: 8),
              reject,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: approve),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: conditional),
            const SizedBox(width: 10),
            Expanded(child: reject),
          ],
        );
      },
    );
  }
}

class _RequerimientoDecision {
  final String nota;
  final bool requiereAdjunto;
  final DateTime fechaLimite;

  const _RequerimientoDecision({
    required this.nota,
    required this.requiereAdjunto,
    required this.fechaLimite,
  });
}

Future<_RequerimientoDecision?> _pedirRequerimientoCalidad(
  BuildContext context,
  String documento,
) async {
  final controller = TextEditingController();
  var requiereAdjunto = true;
  var fechaLimite = DateTime.now().add(const Duration(days: 8));
  final result = await showDialog<_RequerimientoDecision>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: _comprasDialogTitle(
          dialogContext,
          'Aprobar con requerimientos',
          icon: Icons.rule_folder_outlined,
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  documento,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'El documento podrá utilizarse, pero conservará un requerimiento abierto hasta que Calidad valide su cumplimiento.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '¿Qué hace falta? *',
                    hintText:
                        'Ejemplo: anexar la página firmada o el certificado complementario.',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: requiereAdjunto,
                  onChanged: (value) =>
                      setDialogState(() => requiereAdjunto = value ?? true),
                  title: const Text(
                    'Requiere adjuntar un soporte',
                    style: TextStyle(fontFamily: _kFont),
                  ),
                  subtitle: const Text(
                    'Al cargarlo se generará un PDF consolidado sin borrar el original.',
                    style: TextStyle(fontFamily: _kFont, fontSize: 11),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Fecha límite'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(fechaLimite)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: fechaLimite,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => fechaLimite = picked);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB45309),
            ),
            onPressed: () {
              final nota = controller.text.trim();
              if (nota.isEmpty) return;
              Navigator.pop(
                dialogContext,
                _RequerimientoDecision(
                  nota: nota,
                  requiereAdjunto: requiereAdjunto,
                  fechaLimite: fechaLimite,
                ),
              );
            },
            icon: const Icon(Icons.check),
            label: const Text('Aceptar con requerimientos'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

class _RequerimientoCalidadView extends StatelessWidget {
  final DocAdjunto doc;
  final String label;
  final VoidCallback onView;
  final VoidCallback onClose;

  const _RequerimientoCalidadView({
    required this.doc,
    required this.label,
    required this.onView,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final deadline = doc.requerimientoFechaLimite?.toDate();
    final supportReady =
        !doc.requerimientoRequiereAdjunto ||
        doc.soportesRequerimiento.isNotEmpty ||
        (doc.documentoConsolidadoUrl?.isNotEmpty ?? false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rule_folder_outlined, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$label · Aprobado con requerimientos',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Ver documento vigente',
                onPressed: onView,
                icon: const Icon(Icons.open_in_new, size: 17),
              ),
            ],
          ),
          Text(
            doc.requerimientoNota ?? doc.observacionCalidad ?? '',
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              color: Color(0xFF78350F),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(
                doc.requerimientoRequiereAdjunto
                    ? supportReady
                          ? 'Soporte cargado · pendiente cierre'
                          : 'Falta adjunto'
                    : 'No requiere adjunto',
                supportReady
                    ? const Color(0xFF0369A1)
                    : const Color(0xFFB45309),
              ),
              if (deadline != null)
                _Chip(
                  'Límite: ${DateFormat('dd/MM/yyyy').format(deadline)}',
                  const Color(0xFFB45309),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: supportReady ? onClose : null,
              icon: const Icon(Icons.verified_outlined, size: 17),
              label: const Text('Cerrar requerimiento'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalidadActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _CalidadActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: 0.05),
        side: BorderSide(color: color.withValues(alpha: 0.85)),
        minimumSize: const Size.fromHeight(42),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: _kFont,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RecepcionCalidadCard extends StatelessWidget {
  final RecepcionDoc recepcion;
  final ComprasService svc;
  final String userId;
  final String filtroProducto;
  final ReqEngine? reqEngine;
  final bool consultaTransitorios;

  /// Muestra únicamente los documentos permanentes pendientes de aprobación.
  final bool soloPermanentes;
  final int retentionDays;

  const _RecepcionCalidadCard({
    required this.recepcion,
    required this.svc,
    required this.userId,
    required this.filtroProducto,
    this.reqEngine,
    this.consultaTransitorios = false,
    this.soloPermanentes = false,
    this.retentionDays = 8,
  });

  bool _matchesDocFilter(String docKey, DocAdjunto? doc) {
    if (doc == null || !doc.tieneDoc) return false;
    if (consultaTransitorios) {
      return esDocumentoTransitorioRecepcion(docKey) &&
          doc.estadoCalidad != 'consultado';
    }
    if (soloPermanentes) {
      // Pestaña "Pendientes": solo permanentes por aprobar; los transitorios
      // tienen su propia pestaña de consulta.
      return esDocumentoPermanenteRecepcion(docKey) &&
          (doc.aprobadoConRequerimientos || (!doc.aprobado && !doc.rechazado));
    }
    return doc.aprobadoConRequerimientos || (!doc.aprobado && !doc.rechazado);
  }

  String? _fechaEliminacion(DocAdjunto doc) {
    final fecha = doc.fechaRevision?.toDate();
    if (fecha == null) return null;
    return DateFormat(
      'dd/MM/yyyy',
      'es',
    ).format(fecha.add(Duration(days: retentionDays)));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: proveedor + fecha
            Row(
              children: [
                const Icon(Icons.business, size: 14, color: Colors.black45),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    recepcion.razonSocial,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  _fmtFecha(recepcion.fecha),
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
            if (recepcion.ordenCompra.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'OC: ${recepcion.ordenCompra}',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.black45,
                ),
              ),
            ],
            const Divider(height: 16),
            // Productos con todos los docs requeridos
            ...recepcion.productos.asMap().entries.expand((entry) {
              final productoIdx = entry.key;
              final rp = entry.value;
              if (filtroProducto.isNotEmpty &&
                  !rp.nombre.toLowerCase().contains(filtroProducto)) {
                return <Widget>[];
              }

              final engine = reqEngine;
              final requeridos = (engine != null && !engine.isEmpty)
                  ? engine.docsRecepcion(
                      categoriaProducto: rp.categoria,
                      origenProducto: rp.origen,
                      etapa: 'CADA_PEDIDO',
                    )
                  : <ReqDocAplic>[];

              // Docs subidos que no están en la lista de requeridos (legacy/extra)
              final keysRequeridos = requeridos.map((r) => r.keyApp).toSet();
              final docsExtra = rp.documentos.entries
                  .where(
                    (e) =>
                        _matchesDocFilter(e.key, e.value) &&
                        !keysRequeridos.contains(e.key),
                  )
                  .toList();

              final tieneAlgo = rp.documentos.entries.any(
                (entry) => _matchesDocFilter(entry.key, entry.value),
              );
              if (!tieneAlgo) return <Widget>[];

              // Contar docs subidos: aprobados vs total subidos
              final docsSubidos = rp.documentos.entries
                  .where((entry) => _matchesDocFilter(entry.key, entry.value))
                  .length;
              final totalReq = docsSubidos;
              final aprobadosCount = rp.documentos.entries
                  .where(
                    (entry) => !consultaTransitorios && entry.value.aprobado,
                  )
                  .length;
              final rechazadosCount = rp.documentos.entries
                  .where(
                    (entry) =>
                        _matchesDocFilter(entry.key, entry.value) &&
                        entry.value.rechazado,
                  )
                  .length;

              return [
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: consultaTransitorios
                        ? const Color(0xFFEFF6FF)
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: consultaTransitorios
                          ? const Color(0xFF93C5FD)
                          : Colors.orange.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.inventory_2,
                                  size: 14,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    rp.nombre,
                                    style: const TextStyle(
                                      fontFamily: _kFont,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (rp.marca.isNotEmpty)
                                  _Chip(rp.marca, kComprasPrimary),
                                const SizedBox(width: 4),
                                _Chip(
                                  rp.origen,
                                  rp.origen == 'IMPORTADO'
                                      ? Colors.purple.shade700
                                      : Colors.green.shade700,
                                ),
                              ],
                            ),
                            if (totalReq > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                consultaTransitorios
                                    ? '$totalReq documento(s) de consulta · $rechazadosCount rechazado(s)'
                                    : '$aprobadosCount/$totalReq docs aprobados',
                                style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 11,
                                  color: consultaTransitorios
                                      ? const Color(0xFF1D4ED8)
                                      : aprobadosCount == totalReq
                                      ? kComprasGreen
                                      : Colors.orange.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (rp.observaciones.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Obs: ${rp.observaciones}',
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                            if (rp.lotes.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Lotes: ${rp.lotes.map((lote) => lote.numero).join(', ')}',
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 11,
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                      // Docs requeridos (del ReqEngine) — solo los subidos
                      ...requeridos
                          .where(
                            (req) => _matchesDocFilter(
                              req.keyApp,
                              rp.documentos[req.keyApp],
                            ),
                          )
                          .map((req) {
                            final docKey = req.keyApp;
                            final doc = rp.documentos[docKey];
                            final label =
                                kDocRecepcionLabels[docKey] ??
                                req.documentoRequerido;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildDocRow(
                                context: context,
                                docKey: docKey,
                                label: label,
                                doc: doc,
                                productoIdx: productoIdx,
                              ),
                            );
                          }),
                      // Docs extra subidos (no en la lista de requeridos)
                      ...docsExtra.map((e) {
                        final docKey = e.key;
                        final doc = e.value;
                        final label = kDocRecepcionLabels[docKey] ?? docKey;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildDocRow(
                            context: context,
                            docKey: docKey,
                            label: label,
                            doc: doc,
                            productoIdx: productoIdx,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ];
            }),
          ],
        ),
      ),
    );
  }

  /// Envuelve el tile de documento y añade, cuando consta, el nombre público de
  /// quien subió el archivo (visible tanto para Calidad al revisar como para el
  /// rol Compras que solo visualiza).
  Widget _buildDocRow({
    required BuildContext context,
    required String docKey,
    required String label,
    required DocAdjunto? doc,
    required int productoIdx,
  }) {
    final inner = _buildDocRowInner(
      context: context,
      docKey: docKey,
      label: label,
      doc: doc,
      productoIdx: productoIdx,
    );
    final subidoPor = doc?.subidoPor?.trim() ?? '';
    if (subidoPor.isEmpty) return inner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        inner,
        Padding(
          padding: const EdgeInsets.only(left: 10, top: 2),
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 12, color: Colors.black45),
              const SizedBox(width: 4),
              Flexible(
                child: UserNameText(
                  subidoPor,
                  prefix: 'Subió: ',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 10,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDocRowInner({
    required BuildContext context,
    required String docKey,
    required String label,
    required DocAdjunto? doc,
    required int productoIdx,
  }) {
    final tieneDoc = doc?.tieneDoc == true;

    if (!tieneDoc) {
      // Sin cargar
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.upload_outlined, size: 14, color: Colors.amber.shade800),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Text(
                'Sin cargar',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (consultaTransitorios && !doc!.rechazado) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  size: 15,
                  color: Color(0xFF1D4ED8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _abrirUrl(context, doc.url),
                  icon: const Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: Color(0xFF1D4ED8),
                  ),
                  tooltip: 'Ver documento',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDBEAFE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Consulta',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                ),
              ],
            ),
            if (doc.observacionActualizacion?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                'Observación: ${doc.observacionActualizacion!.trim()}',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Color(0xFF475569),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CalidadActionButton(
                    label: 'Revisado',
                    icon: Icons.check,
                    color: kComprasGreen,
                    onPressed: () =>
                        _marcarConsultado(context, productoIdx, docKey),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CalidadActionButton(
                    label: 'Rechazar',
                    icon: Icons.close,
                    color: kComprasRed,
                    onPressed: () => _rechazarDoc(context, productoIdx, docKey),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (doc!.aprobadoConRequerimientos) {
      return _RequerimientoCalidadView(
        doc: doc,
        label: label,
        onView: () => _abrirUrl(context, doc.url),
        onClose: () => _aprobarDoc(context, productoIdx, docKey),
      );
    }

    if (doc.aprobado) {
      // Aprobado — solo visual
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 14, color: kComprasGreen),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.black87,
                ),
              ),
            ),
            if (doc.tieneDoc)
              IconButton(
                onPressed: () => _abrirUrl(context, doc.url),
                icon: const Icon(
                  Icons.open_in_new,
                  size: 14,
                  color: Colors.blue,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Ver documento',
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: const Text(
                'Aprobado',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: kComprasGreen,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (doc.rechazado) {
      // Rechazado — muestra motivo
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.cancel, size: 14, color: kComprasRed),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (doc.tieneDoc)
                  IconButton(
                    onPressed: () => _abrirUrl(context, doc.url),
                    icon: const Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: Colors.blue,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    tooltip: 'Ver documento',
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: const Text(
                    'Rechazado',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: kComprasRed,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (doc.observacionCalidad?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                'Motivo: ${doc.observacionCalidad}',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.red.shade700,
                ),
              ),
            ),
          if (_fechaEliminacion(doc) != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Text(
                'Se elimina: ${_fechaEliminacion(doc)}',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      );
    }

    // Pendiente de revisión — botones Aprobar / Rechazar
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.hourglass_empty, size: 14, color: Colors.orange),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                ),
              ),
              if (doc.fechaVencimiento != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (doc.fechaVencimiento!.toDate().isBefore(
                            DateTime.now(),
                          ))
                          ? Colors.red.withOpacity(0.1)
                          : Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color:
                            (doc.fechaVencimiento!.toDate().isBefore(
                              DateTime.now(),
                            ))
                            ? Colors.red.withOpacity(0.3)
                            : Colors.blue.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 10,
                          color:
                              (doc.fechaVencimiento!.toDate().isBefore(
                                DateTime.now(),
                              ))
                              ? Colors.red
                              : Colors.blue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Vence: ${DateFormat('dd/MM/yyyy').format(doc.fechaVencimiento!.toDate())}',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color:
                                (doc.fechaVencimiento!.toDate().isBefore(
                                  DateTime.now(),
                                ))
                                ? Colors.red
                                : Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (doc.tieneDoc)
                IconButton(
                  onPressed: () => _abrirUrl(context, doc.url),
                  icon: const Icon(Icons.search, size: 18, color: Colors.blue),
                  tooltip: 'Ver documento',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
        ),
        if (doc.observacionActualizacion?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                'Obs. actualización: ${doc.observacionActualizacion!.trim()}',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        _CalidadDecisionButtons(
          onApprove: () => _aprobarDoc(context, productoIdx, docKey),
          onApproveWithRequirements: () =>
              _aprobarDocConRequerimientos(context, productoIdx, docKey),
          onReject: () => _rechazarDoc(context, productoIdx, docKey),
        ),
      ],
    );
  }

  Future<void> _aprobarDoc(
    BuildContext context,
    int productoIdx,
    String docKey,
  ) async {
    try {
      await svc.aprobarDocRecepcion(
        recepcion: recepcion,
        productoIdx: productoIdx,
        docKey: docKey,
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento aprobado'),
            backgroundColor: kComprasGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _aprobarDocConRequerimientos(
    BuildContext context,
    int productoIdx,
    String docKey,
  ) async {
    final decision = await _pedirRequerimientoCalidad(
      context,
      kDocRecepcionLabels[docKey] ?? docKey,
    );
    if (decision == null) return;
    try {
      await svc.aprobarConRequerimientosDocRecepcion(
        recepcion: recepcion,
        productoIdx: productoIdx,
        docKey: docKey,
        nota: decision.nota,
        requiereAdjunto: decision.requiereAdjunto,
        fechaLimite: decision.fechaLimite,
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento aceptado con requerimiento.'),
            backgroundColor: Color(0xFFB45309),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No fue posible registrar: $error')),
        );
      }
    }
  }

  Future<void> _rechazarDoc(
    BuildContext context,
    int productoIdx,
    String docKey,
  ) async {
    final motivoCtrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: _comprasDialogTitle(
          dialogContext,
          'Rechazar documento',
          icon: Icons.cancel_outlined,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Documento: ${kDocRecepcionLabels[docKey] ?? docKey}',
                style: const TextStyle(fontFamily: _kFont, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoCtrl,
                decoration: InputDecoration(
                  labelText: 'Motivo del rechazo *',
                  labelStyle: const TextStyle(fontFamily: _kFont),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                maxLines: 3,
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(fontFamily: _kFont)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kComprasRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (motivoCtrl.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Rechazar', style: TextStyle(fontFamily: _kFont)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await svc.rechazarDocRecepcion(
        recepcion: recepcion,
        productoIdx: productoIdx,
        docKey: docKey,
        motivo: motivoCtrl.text.trim(),
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento rechazado. Se notificará al usuario.'),
            backgroundColor: kComprasRed,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _marcarConsultado(
    BuildContext context,
    int productoIdx,
    String docKey,
  ) async {
    try {
      await svc.marcarDocRecepcionConsultado(
        recepcion: recepcion,
        productoIdx: productoIdx,
        docKey: docKey,
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento marcado como revisado.'),
            backgroundColor: kComprasGreen,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No fue posible marcarlo como revisado: $error'),
            backgroundColor: kComprasRed,
          ),
        );
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DOCUMENTOS DE MARCA — CALIDAD
// ══════════════════════════════════════════════════════════════════════════════

class _MarcaCalidadCard extends StatelessWidget {
  final MarcaDoc marca;
  final ComprasService svc;
  final String userId;
  final bool showRejectedOnly;
  final int retentionDays;

  const _MarcaCalidadCard({
    required this.marca,
    required this.svc,
    required this.userId,
    required this.showRejectedOnly,
    required this.retentionDays,
  });

  bool _visible(DocAdjunto doc) {
    if (!doc.tieneDoc) return false;
    if (!showRejectedOnly) {
      return doc.aprobadoConRequerimientos || (!doc.aprobado && !doc.rechazado);
    }
    if (!doc.rechazado) return false;
    final fecha = doc.fechaRevision?.toDate();
    if (fecha == null) return true;
    return !fecha.isBefore(
      DateTime.now().subtract(Duration(days: retentionDays)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docs = marca.documentosAsociados.entries.where(
      (entry) => _visible(entry.value),
    );
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFC4B5FD)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.local_offer_outlined,
                  size: 19,
                  color: Color(0xFF6D28D9),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${marca.descripcion} · ${marca.codigo}',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final entry in docs) ...[
              _buildDocRow(context, entry.key, entry.value),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocRow(BuildContext context, String key, DocAdjunto doc) {
    final label = kDocumentosAsociadosLabels[key] ?? key;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: showRejectedOnly ? Colors.red.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: showRejectedOnly
              ? Colors.red.shade200
              : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                showRejectedOnly ? Icons.cancel_outlined : Icons.hourglass_top,
                size: 17,
                color: showRejectedOnly ? kComprasRed : Colors.orange.shade800,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Ver documento',
                onPressed: () => _abrirUrl(context, doc.url),
                icon: const Icon(Icons.open_in_new, size: 17),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          if (showRejectedOnly &&
              (doc.observacionCalidad?.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 4),
            Text(
              'Motivo: ${doc.observacionCalidad}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 11,
                color: kComprasRed,
              ),
            ),
          ],
          if (!showRejectedOnly && doc.aprobadoConRequerimientos) ...[
            const SizedBox(height: 6),
            _RequerimientoCalidadView(
              doc: doc,
              label: label,
              onView: () => _abrirUrl(context, doc.url),
              onClose: () => _aprobar(context, key),
            ),
          ] else if (!showRejectedOnly) ...[
            const SizedBox(height: 6),
            _CalidadDecisionButtons(
              onApprove: () => _aprobar(context, key),
              onApproveWithRequirements: () =>
                  _aprobarConRequerimientos(context, key, label),
              onReject: () => _rechazar(context, key, label),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _aprobar(BuildContext context, String key) async {
    try {
      await svc.aprobarDocMarca(
        marcaId: marca.id,
        docKey: key,
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento de marca aprobado.'),
            backgroundColor: kComprasGreen,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No fue posible aprobar: $error')),
        );
      }
    }
  }

  Future<void> _aprobarConRequerimientos(
    BuildContext context,
    String key,
    String label,
  ) async {
    final decision = await _pedirRequerimientoCalidad(context, label);
    if (decision == null) return;
    try {
      await svc.aprobarConRequerimientosDocMarca(
        marcaId: marca.id,
        docKey: key,
        nota: decision.nota,
        requiereAdjunto: decision.requiereAdjunto,
        fechaLimite: decision.fechaLimite,
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento aceptado con requerimiento.'),
            backgroundColor: Color(0xFFB45309),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No fue posible registrar: $error')),
        );
      }
    }
  }

  Future<void> _rechazar(BuildContext context, String key, String label) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: _comprasDialogTitle(
          dialogContext,
          'Rechazar documento de marca',
          icon: Icons.cancel_outlined,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Motivo para $label *',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kComprasRed),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await svc.rechazarDocMarca(
        marcaId: marca.id,
        docKey: key,
        motivo: controller.text,
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento rechazado y devolución notificada.'),
            backgroundColor: kComprasRed,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No fue posible rechazar: $error')),
        );
      }
    } finally {
      controller.dispose();
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PROVEEDOR CALIDAD CARD
// ══════════════════════════════════════════════════════════════════════════════

class _ProveedorCalidadCard extends StatelessWidget {
  final ProveedorDoc proveedor;
  final ComprasService svc;
  final String userId;
  final ReqEngine? reqEngine;
  final bool showRejectedOnly;
  final int retentionDays;

  const _ProveedorCalidadCard({
    required this.proveedor,
    required this.svc,
    required this.userId,
    this.reqEngine,
    this.showRejectedOnly = false,
    this.retentionDays = 8,
  });

  bool _matchesDocFilter(DocAdjunto? doc) {
    if (doc == null || !doc.tieneDoc) return false;
    if (!showRejectedOnly) {
      return doc.aprobadoConRequerimientos || (!doc.aprobado && !doc.rechazado);
    }
    if (!doc.rechazado) return false;
    final fecha = doc.fechaRevision?.toDate();
    if (fecha == null) return true;
    final limite = DateTime.now().subtract(Duration(days: retentionDays));
    return !fecha.isBefore(limite);
  }

  String? _fechaEliminacion(DocAdjunto doc) {
    final fecha = doc.fechaRevision?.toDate();
    if (fecha == null) return null;
    return DateFormat(
      'dd/MM/yyyy',
      'es',
    ).format(fecha.add(Duration(days: retentionDays)));
  }

  @override
  Widget build(BuildContext context) {
    final engine = reqEngine;
    final requeridos = (engine != null && !engine.isEmpty)
        ? engine.docsProveedor(proveedor.categorias)
        : <ReqDocAplic>[];

    // Docs subidos no en la lista de requeridos
    final keysRequeridos = requeridos.map((r) => r.keyApp).toSet();
    final docsExtra = proveedor.documentos.entries
        .where(
          (e) =>
              _matchesDocFilter(e.value) &&
              !keysRequeridos.contains(e.key) &&
              !kDocProveedorOcultos.contains(e.key),
        )
        .toList();

    // Contar aprobados vs requeridos
    final totalReq = requeridos.length;
    final aprobadosCount = requeridos
        .where((r) => proveedor.documentos[r.keyApp]?.aprobado == true)
        .length;
    final rechazadosCount = proveedor.documentos.entries
        .where(
          (entry) =>
              !kDocProveedorOcultos.contains(entry.key) &&
              _matchesDocFilter(entry.value),
        )
        .length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.brown.shade200, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.business, size: 18, color: Color(0xFF7B3F00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    proveedor.razonSocial,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'NIT: ${proveedor.nit}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
            if (totalReq > 0) ...[
              const SizedBox(height: 4),
              Text(
                showRejectedOnly
                    ? '$rechazadosCount rechazado(s) vigente(s)'
                    : '$aprobadosCount/$totalReq docs aprobados',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: showRejectedOnly
                      ? kComprasRed
                      : aprobadosCount == totalReq
                      ? kComprasGreen
                      : Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Docs requeridos
            ...requeridos.map((req) {
              final docKey = req.keyApp;
              final doc = proveedor.documentos[docKey];
              final label =
                  kDocProveedorLabels[docKey] ?? req.documentoRequerido;
              if (!_matchesDocFilter(doc)) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildDocRow(
                  context: context,
                  docKey: docKey,
                  label: label,
                  doc: doc,
                ),
              );
            }),
            // Docs extra subidos
            ...docsExtra.map((e) {
              final docKey = e.key;
              final doc = e.value;
              final label = kDocProveedorLabels[docKey] ?? docKey;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildDocRow(
                  context: context,
                  docKey: docKey,
                  label: label,
                  doc: doc,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDocRow({
    required BuildContext context,
    required String docKey,
    required String label,
    required DocAdjunto? doc,
  }) {
    final inner = _buildDocRowInner(
      context: context,
      docKey: docKey,
      label: label,
      doc: doc,
    );
    final subidoPor = doc?.subidoPor?.trim() ?? '';
    if (subidoPor.isEmpty) return inner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        inner,
        Padding(
          padding: const EdgeInsets.only(left: 10, top: 2),
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 12, color: Colors.black45),
              const SizedBox(width: 4),
              Flexible(
                child: UserNameText(
                  subidoPor,
                  prefix: 'Subió: ',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 10,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDocRowInner({
    required BuildContext context,
    required String docKey,
    required String label,
    required DocAdjunto? doc,
  }) {
    final tieneDoc = doc?.tieneDoc == true;

    if (!tieneDoc) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.upload_outlined, size: 14, color: Colors.amber.shade800),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Text(
                'Sin cargar',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (doc!.aprobadoConRequerimientos) {
      return _RequerimientoCalidadView(
        doc: doc,
        label: label,
        onView: () => _abrirUrl(context, doc.url),
        onClose: () => _aprobarDoc(context, docKey),
      );
    }

    if (doc.aprobado) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 14, color: kComprasGreen),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.black87,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _abrirUrl(context, doc.url),
              icon: const Icon(Icons.open_in_new, size: 14, color: Colors.blue),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Ver documento',
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: const Text(
                'Aprobado',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: kComprasGreen,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (doc.rechazado) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.cancel, size: 14, color: kComprasRed),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _abrirUrl(context, doc.url),
                  icon: const Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: Colors.blue,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: 'Ver documento',
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: const Text(
                    'Rechazado',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: kComprasRed,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (doc.observacionCalidad?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                'Motivo: ${doc.observacionCalidad}',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.red.shade700,
                ),
              ),
            ),
          if (_fechaEliminacion(doc) != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Text(
                'Se elimina: ${_fechaEliminacion(doc)}',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      );
    }

    // Pendiente — botones Aprobar / Rechazar
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.hourglass_empty, size: 14, color: Colors.orange),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontFamily: _kFont, fontSize: 12),
              ),
            ),
            IconButton(
              onPressed: () => _abrirUrl(context, doc.url),
              icon: const Icon(Icons.search, size: 18, color: Colors.blue),
              tooltip: 'Ver documento',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _CalidadDecisionButtons(
          onApprove: () => _aprobarDoc(context, docKey),
          onApproveWithRequirements: () =>
              _aprobarDocConRequerimientos(context, docKey),
          onReject: () => _rechazarDoc(context, docKey),
        ),
      ],
    );
  }

  Future<void> _aprobarDoc(BuildContext context, String docKey) async {
    try {
      await svc.aprobarDocProveedor(
        proveedorId: proveedor.id,
        docKey: docKey,
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento aprobado'),
            backgroundColor: kComprasGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _aprobarDocConRequerimientos(
    BuildContext context,
    String docKey,
  ) async {
    final decision = await _pedirRequerimientoCalidad(
      context,
      kDocProveedorLabels[docKey] ?? docKey,
    );
    if (decision == null) return;
    try {
      await svc.aprobarConRequerimientosDocProveedor(
        proveedorId: proveedor.id,
        docKey: docKey,
        nota: decision.nota,
        requiereAdjunto: decision.requiereAdjunto,
        fechaLimite: decision.fechaLimite,
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento aceptado con requerimiento.'),
            backgroundColor: Color(0xFFB45309),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No fue posible registrar: $error')),
        );
      }
    }
  }

  Future<void> _rechazarDoc(BuildContext context, String docKey) async {
    final motivoCtrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: _comprasDialogTitle(
          dialogContext,
          'Rechazar documento',
          icon: Icons.cancel_outlined,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Documento: ${kDocProveedorLabels[docKey] ?? docKey}',
                style: const TextStyle(fontFamily: _kFont, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoCtrl,
                decoration: InputDecoration(
                  labelText: 'Motivo del rechazo *',
                  labelStyle: const TextStyle(fontFamily: _kFont),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                maxLines: 3,
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(fontFamily: _kFont)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kComprasRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (motivoCtrl.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Rechazar', style: TextStyle(fontFamily: _kFont)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await svc.rechazarDocProveedor(
        proveedorId: proveedor.id,
        docKey: docKey,
        motivo: motivoCtrl.text.trim(),
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento rechazado.'),
            backgroundColor: kComprasRed,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

// WIDGETS DE APOYO
// ══════════════════════════════════════════════════════════════════════════════

class _CalidadSectionPanel extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icon;
  final Color color;
  final int? count;
  final Widget child;

  const _CalidadSectionPanel({
    required this.titulo,
    required this.subtitulo,
    required this.icon,
    required this.color,
    required this.child,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              if (count != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: _kFont,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _CalidadEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _CalidadEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey.shade500, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalidadLoadingState extends StatelessWidget {
  final String message;

  const _CalidadLoadingState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String titulo;
  final IconData icon;
  final Color color;

  const _SectionHeader(this.titulo, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 4,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Text(
        titulo,
        style: TextStyle(
          fontFamily: _kFont,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: color,
        ),
      ),
    ],
  );
}

Widget _Chip(String label, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: color.withOpacity(0.12),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(
    label,
    style: TextStyle(
      fontFamily: _kFont,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: color,
    ),
  ),
);

class _StatusDot extends StatelessWidget {
  final bool ok;

  const _StatusDot({required this.ok});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: ok ? 'Documentos completos' : 'Documentos pendientes',
    child: Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: ok ? kComprasGreen : kComprasRed,
        shape: BoxShape.circle,
      ),
    ),
  );
}

Widget _InfoRow(IconData icon, String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 14, color: Colors.black38),
      const SizedBox(width: 6),
      Text(
        '$label: ',
        style: const TextStyle(
          fontFamily: _kFont,
          fontSize: 12,
          color: Colors.black45,
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            fontFamily: _kFont,
            fontSize: 12,
            color: Colors.black87,
          ),
        ),
      ),
    ],
  ),
);
