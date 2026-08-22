// lib/home/complete_task_screen.dart
// Pantalla para completar tarea con:
// - foto con marca de agua (logo + texto + (opcional) mini mapa estático)
// - adjuntar archivos
// - actualización de Firestore usando tus campos en español
// - notificación al creador vía Cloud Function callable

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart'; // opcional, para adivinar mime
import 'package:todo/services/company_branding_service.dart';

const Color kMarronOscuro = Color(0xFF145DA0);
const String kArial = 'Arial';

class CompleteTaskScreen extends StatefulWidget {
  final String taskId;
  final String currentUserId;
  final bool requestFinish;
  final String? requestFinishByName;
  const CompleteTaskScreen({
    Key? key,
    required this.taskId,
    required this.currentUserId,
    this.requestFinish = false,
    this.requestFinishByName,
  }) : super(key: key);

  @override
  State<CompleteTaskScreen> createState() => _CompleteTaskScreenState();
}

class _CompleteTaskScreenState extends State<CompleteTaskScreen> {
  // UI
  bool _busy = false;
  String? _error;
  String? _taskTitle;

  // Data
  Map<String, dynamic>? _task; // documento de la tarea
  final _picker = ImagePicker();
  final List<PlatformFile> _picked = [];
  final List<_PhotoMeta> _photos = [];

  // Ubicación
  Position? _pos;
  String? _address;

  @override
  void initState() {
    super.initState();
    _loadTask();
    _ensureLocation();
  }

  Future<void> _loadTask() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(widget.taskId)
          .get();
      final m = snap.data() ?? {};
      setState(() {
        _task = m;
        _taskTitle = (m['titulo'] ?? m['title'] ?? 'Completar tarea')
            .toString();
      });
    } catch (e) {
      // fallback
    }
  }

  Future<void> _ensureLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return;
      }
      _pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _address = await _reverseGeocode(_pos!.latitude, _pos!.longitude);
      setState(() {});
    } catch (_) {}
  }

  Future<String?> _reverseGeocode(double lat, double lng) async {
    // opcional: deja así, no es crítico para la marca de agua
    return null;
  }

  // ---------- UI Helpers ----------

  String _fmtDueDate(dynamic ts) {
    if (ts is Timestamp)
      return DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
    return '—';
  }

  Widget _chip(String text, {Color? color}) {
    return Chip(
      label: Text(
        text,
        style: const TextStyle(color: Colors.white, fontFamily: kArial),
      ),
      backgroundColor: color ?? Colors.grey.shade600,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  String _slugFileSegment(String value, {String fallback = 'tarea'}) {
    final lowered = value.trim().toLowerCase();
    final cleaned = lowered
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? fallback : cleaned;
  }

  String _processLabel() => widget.requestFinish ? 'Finalización' : 'Evidencia';

  bool get _requiresAttachment {
    final raw = _task?['requiere_adjunto'] ?? _task?['requiereAdjunto'];
    if (raw == null) return true;
    if (raw is bool) return raw;
    final normalized = raw.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == 'si';
  }

  // ---------- Adjuntos ----------

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'zip',
        'jpg',
        'jpeg',
        'png',
      ],
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() => _picked.addAll(res.files));
    }
  }

  // ---------- Foto con marca de agua ----------

  Future<void> _takePhoto() async {
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (x == null) return;

    final raw = await x.readAsBytes();
    final img = await _decodeUiImage(raw);

    final wm = await _buildWatermarkedBytes(
      base: img,
      title: _taskTitle ?? 'Tarea',
      who: _task?['asignado_nombre'] ?? '—',
      coords: _pos == null
          ? null
          : '${_pos!.latitude.toStringAsFixed(5)}, ${_pos!.longitude.toStringAsFixed(5)}',
      address: _address,
      deadline: _task?['fecha_limite'],
    );
    if (wm == null) return;

    final taskSlug = _slugFileSegment(_taskTitle ?? '', fallback: 'tarea');
    final name =
        '${taskSlug}_evidencia_${DateTime.now().millisecondsSinceEpoch}.png';
    String? filePath;
    if (!kIsWeb) {
      final dir = Directory.systemTemp;
      final file = File('${dir.path}/$name')..writeAsBytesSync(wm);
      filePath = file.path;
    }
    setState(() {
      _picked.add(
        PlatformFile(name: name, path: filePath, size: wm.length, bytes: wm),
      );
      _photos.add(
        _PhotoMeta(
          name: name,
          when: DateTime.now(),
          lat: _pos?.latitude,
          lng: _pos?.longitude,
        ),
      );
    });
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<Uint8List?> _buildWatermarkedBytes({
    required ui.Image base,
    required String title,
    required String who,
    String? coords,
    String? address,
    dynamic deadline, // Timestamp?
  }) async {
    final nowStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // carga logo
    ui.Image? logo;
    try {
      final logoBytes = await CompanyBrandingService().loadLogoBytes(
        (_task?['empresaId'] ?? _task?['empresa_id'] ?? '').toString(),
      );
      if (logoBytes == null || logoBytes.isEmpty) throw StateError('Sin logo');
      final lcodec = await ui.instantiateImageCodec(logoBytes);
      logo = (await lcodec.getNextFrame()).image;
    } catch (_) {}

    // (opcional) pequeño mapa estático
    ui.Image? staticMap;
    try {
      if (coords != null && coords.contains(',')) {
        final parts = coords.split(',');
        final lat = parts[0].trim();
        final lng = parts[1].trim();
        // si tienes Static Maps habilitado, pon tu key aquí (si no, ignora)
        const mapsKey = ''; // <-- opcional
        if (mapsKey.isNotEmpty) {
          final url = Uri.parse(
            'https://maps.googleapis.com/maps/api/staticmap'
            '?center=$lat,$lng&zoom=16&size=320x200&scale=2&maptype=roadmap&markers=color:red|$lat,$lng&key=$mapsKey',
          );
          final r = await http.get(url).timeout(const Duration(seconds: 7));
          if (r.statusCode == 200) {
            final codec = await ui.instantiateImageCodec(r.bodyBytes);
            staticMap = (await codec.getNextFrame()).image;
          }
        }
      }
    } catch (_) {}

    // compón
    final rec = ui.PictureRecorder();
    final c = Canvas(
      rec,
      Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
    );
    c.drawImage(
      base,
      Offset.zero,
      Paint()..filterQuality = ui.FilterQuality.medium,
    );

    final overlayH = (base.height * 0.22).clamp(140.0, 280.0);
    final overlay = Rect.fromLTWH(
      0,
      base.height - overlayH,
      base.width.toDouble(),
      overlayH,
    );
    c.drawRect(overlay, Paint()..color = const Color(0xCC000000));

    const pad = 16.0;
    final col1W = base.width * 0.18;
    final col2W = base.width * 0.52;
    final col3W = base.width * 0.30;

    final rLogo = Rect.fromLTWH(
      overlay.left + pad,
      overlay.top + pad,
      col1W - pad * 2,
      overlay.height - pad * 2,
    );
    final rText = Rect.fromLTWH(
      overlay.left + col1W,
      overlay.top + pad,
      col2W - pad * 2,
      overlay.height - pad * 2,
    );
    final rMap = Rect.fromLTWH(
      overlay.left + col1W + col2W,
      overlay.top + pad,
      col3W - pad * 2,
      overlay.height - pad * 2,
    );

    // logo centrado en blanco
    if (logo != null && rLogo.width > 0) {
      final s = math.min(rLogo.width / logo.width, rLogo.height / logo.height);
      final w = logo.width * s, h = logo.height * s;
      final dst = Rect.fromLTWH(
        rLogo.left + (rLogo.width - w) / 2,
        rLogo.top + (rLogo.height - h) / 2,
        w,
        h,
      );
      c.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        dst,
        Paint()
          ..colorFilter = const ui.ColorFilter.mode(
            Colors.white,
            ui.BlendMode.modulate,
          ),
      );
    }

    // texto
    final lines = <String>[
      'Tarea: $title',
      'Fecha: $nowStr',
      'Realizada por: $who',
      if (deadline is Timestamp)
        'Límite: ${DateFormat('dd/MM/yyyy HH:mm').format(deadline.toDate())}',
      if (coords != null) 'Ubicación: $coords',
      if (address != null && address.isNotEmpty) address,
    ];
    final pb =
        ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 8, ellipsis: '…'))
          ..pushStyle(
            ui.TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 24),
          );
    pb.addText(lines.join('\n'));
    final p = pb.build()..layout(ui.ParagraphConstraints(width: rText.width));
    c.drawParagraph(p, Offset(rText.left, rText.top));

    // mapa
    if (staticMap != null && rMap.width > 0) {
      final rr = RRect.fromRectAndRadius(rMap, const Radius.circular(12));
      final path = Path()..addRRect(rr);
      c.save();
      c.clipPath(path);
      c.drawImageRect(
        staticMap,
        Rect.fromLTWH(
          0,
          0,
          staticMap.width.toDouble(),
          staticMap.height.toDouble(),
        ),
        rMap,
        Paint()..filterQuality = ui.FilterQuality.high,
      );
      c.restore();
      c.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.white.withOpacity(0.9),
      );
    }

    final picture = rec.endRecording();
    final out = await picture.toImage(base.width, base.height);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  }

  // ---------- Submit ----------

  bool get _canSend {
    if (!widget.requestFinish) return _picked.isNotEmpty;
    if (_requiresAttachment) return _picked.isNotEmpty;
    return true;
  }

  Future<void> _submit() async {
    if (!_canSend) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final tareaRef = FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(widget.taskId);

      // 1) Subir adjuntos
      final now = DateTime.now();
      final y = DateFormat('yyyy').format(now),
          m = DateFormat('MM').format(now),
          d = DateFormat('dd').format(now);
      final taskSlug = _slugFileSegment(_taskTitle ?? '', fallback: 'tarea');

      final List<Map<String, dynamic>> nuevosAdjuntos = [];
      final List<String> nuevasEvidenciasUrls = [];

      for (final f in _picked) {
        final originalName = f.name;
        final bytes =
            f.bytes ??
            (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (bytes == null) continue;

        final ext = originalName.contains('.')
            ? originalName.split('.').last.toLowerCase()
            : '';
        final mime =
            lookupMimeType(originalName) ??
            (ext == 'png' ? 'image/png' : 'application/octet-stream');
        final evidenceName =
            '${taskSlug}_${DateTime.now().millisecondsSinceEpoch}_${originalName.replaceAll('/', '_').replaceAll('\\', '_')}';

        final path = 'tareas/$y/$m/$d/$evidenceName';
        final ref = FirebaseStorage.instance.ref(path);
        await ref.putData(bytes, SettableMetadata(contentType: mime));
        final url = await ref.getDownloadURL();

        nuevosAdjuntos.add({
          'name': originalName,
          'storedName': evidenceName,
          'path': path,
          'url': url,
          'mime': mime,
          'size': bytes.length,
          'process': _processLabel(),
          'desc': _processLabel(),
          'uploadedAt': Timestamp.now(),
          'by': widget.currentUserId,
        });

        // si es imagen (marca de agua), también lo agregamos a evidencias
        if (mime.startsWith('image/')) {
          nuevasEvidenciasUrls.add(url);
        }
      }

      // 2) Merge en Firestore (sin serverTimestamp dentro de arrays)
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final snap = await trx.get(tareaRef);
        final data = snap.data() ?? {};
        final currentAdj = (data['adjuntos'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final currentEvid = (data['evidencias'] as List<dynamic>? ?? [])
            .cast<String>();
        final now = Timestamp.now();

        if (widget.requestFinish) {
          final byName =
              (widget.requestFinishByName ?? data['asignado_nombre'] ?? '')
                  .toString();
          trx.update(tareaRef, {
            'estado': 'por_aprobar',
            'status': 'por_aprobar',
            'solicitud_finalizacion_estado': 'pendiente',
            'solicitud_finalizacion_at': now,
            'solicitud_finalizacion_by_uid': widget.currentUserId,
            'solicitud_finalizacion_by_nombre': byName,
            'lastEventType': 'solicitud_finalizacion',
            'lastEventAt': now,
            'lastEventText': 'Solicitud de finalización enviada por $byName',
            'fecha_actualizacion': now,
            'updatedAt': now,
            'adjuntos': [...currentAdj, ...nuevosAdjuntos],
            'evidencias': [...currentEvid, ...nuevasEvidenciasUrls],
            'actualizada_en': now,
          });
          return;
        }

        trx.update(tareaRef, {
          'estado': 'finalizado',
          'status': 'finalizado',
          'fecha_completada': FieldValue.serverTimestamp(), // OK top-level
          'adjuntos': [...currentAdj, ...nuevosAdjuntos],
          'evidencias': [...currentEvid, ...nuevasEvidenciasUrls],
          'actualizada_en': FieldValue.serverTimestamp(),
          'lastEventType': 'finalizado',
          'lastEventAt': now,
          'lastEventText':
              'Tarea finalizada por ${data['asignado_nombre'] ?? ''}',
        });
      });

      if (widget.requestFinish || nuevosAdjuntos.isNotEmpty) {
        final currentTask = _task ?? const <String, dynamic>{};
        final byName =
            (widget.requestFinishByName ??
                    currentTask['asignado_nombre'] ??
                    widget.currentUserId)
                .toString();
        await tareaRef.collection('finalizacion').add({
          'type': widget.requestFinish
              ? 'solicitud_finalizacion'
              : 'finalizacion',
          'message': widget.requestFinish
              ? 'Solicitud de finalización enviada por $byName'
              : 'Tarea finalizada por $byName',
          'attachments': nuevosAdjuntos,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': widget.currentUserId,
          'createdByName': byName,
        });
      }

      // onTaskUpdated genera la notificación in-app y el push para creador/jefe.
      if (mounted) {
        final msg = widget.requestFinish
            ? 'Solicitud de finalización enviada.'
            : '¡Tarea finalizada!';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final due = _task?['fecha_limite'];
    final estado = (_task?['estado'] ?? '').toString();

    final appTitle = widget.requestFinish
        ? 'Finalizar tarea'
        : 'Completar tarea';
    final appSubtitle = widget.requestFinish
        ? 'Envía evidencias para aprobación'
        : 'Adjunta evidencia de cierre';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Volver',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            Text(
              _taskTitle != null ? _taskTitle! : appSubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Color(0xCCFFFFFF),
              ),
            ),
          ],
        ),
        backgroundColor: kMarronOscuro,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            tooltip: 'Ir al Home',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header “tarjeta”
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.assignment_turned_in_outlined,
                        size: 28,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _taskTitle ?? '—',
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _chip(
                                  estado.isEmpty ? 'en_progreso' : estado,
                                  color: estado == 'finalizado'
                                      ? Colors.green.shade600
                                      : (estado == 'por_aprobar'
                                            ? Colors.orange.shade700
                                            : Colors.blueGrey.shade700),
                                ),
                                _chip(
                                  'Vence: ${_fmtDueDate(due)}',
                                  color: Colors.blue.shade600,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Botones acciones
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.attach_file,
                      label: 'Adjuntar\narchivos',
                      onTap: _busy ? null : _pickFiles,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.camera_alt,
                      label: 'Tomar foto',
                      onTap: _busy ? null : _takePhoto,
                    ),
                  ),
                ],
              ),
            ),

            // Listado de archivos seleccionados
            if (_picked.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  widget.requestFinish && !_requiresAttachment
                      ? 'Esta tarea no requiere adjuntos. Puedes enviarla a aprobación sin evidencia.'
                      : 'Agrega una foto o adjuntos como evidencia.',
                  style: const TextStyle(
                    fontFamily: kArial,
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ListView.separated(
                    itemCount: _picked.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final f = _picked[i];
                      final isImg =
                          (f.name.toLowerCase().endsWith('.png') ||
                          f.name.toLowerCase().endsWith('.jpg') ||
                          f.name.toLowerCase().endsWith('.jpeg'));
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ListTile(
                          leading: Icon(
                            isImg
                                ? Icons.image
                                : Icons.insert_drive_file_outlined,
                            color: Colors.black87,
                          ),
                          title: Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${(f.size / 1024).toStringAsFixed(1)} KB',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _picked.removeAt(i);
                                    if (i < _photos.length &&
                                        _photos[i].name == f.name)
                                      _photos.removeAt(i);
                                  }),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

            // Error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),

            // CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy || !_canSend ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kMarronOscuro,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 4,
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          widget.requestFinish
                              ? (_requiresAttachment
                                    ? 'Enviar evidencias y solicitar finalización'
                                    : 'Solicitar finalización')
                              : 'Enviar evidencias',
                          style: const TextStyle(fontFamily: kArial),
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ActionButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? kMarronOscuro : Colors.grey.shade400,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontFamily: kArial),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoMeta {
  final String name;
  final DateTime when;
  final double? lat;
  final double? lng;
  _PhotoMeta({required this.name, required this.when, this.lat, this.lng});
}
