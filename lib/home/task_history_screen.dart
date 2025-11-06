// lib/home/task_history_screen.dart
import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:cloud_functions/cloud_functions.dart';

const Color kBrand = Color(0xFF1E3A8A); // Indigo 800
const String kArial = 'Arial';

DateTime? _toDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) return DateTime.tryParse(v);
  return null;
}

String _fmt(DateTime? d) =>
    d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(d);

int? _daysLeft(DateTime? due) {
  if (due == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final end = DateTime(due.year, due.month, due.day, 23, 59, 59);
  return end.difference(today).inDays;
}

Color _statusColor(String s) {
  switch (s) {
    case 'pendiente':
      return Colors.orange.shade600;
    case 'en_progreso':
      return Colors.blue.shade600;
    case 'completada':
      return Colors.green.shade700;
    case 'finalizado':
      return Colors.green.shade800;
    case 'devuelta':
      return Colors.purple.shade600;
    case 'retrasado':
      return Colors.red.shade700;
    default:
      return Colors.grey.shade600;
  }
}

/// Estado efectivo con prioridad:
/// 1) finalizado (o approved == true)
/// 2) completada
/// 3) retrasado (si vencida y no finalizada/completada)
/// 4) el estado que tenga o 'pendiente'
String _resolvedEstado(Map<String, dynamic> m) {
  final approved = m['approved'] == true;
  final raw = (m['estado'] ?? m['status'] ?? '').toString().trim().toLowerCase();

  if (approved || raw == 'finalizado') return 'finalizado';
  if (raw == 'completada') return 'completada';

  final due = _toDate(m['fecha_limite']); // <-- tu campo de vencimiento
  final days = _daysLeft(due);
  if (days != null && days < 0) return 'retrasado';

  return raw.isEmpty ? 'pendiente' : raw;
}

/// Extrae un mensaje/descripcion de múltiples claves posibles
String _msgOf(Map<String, dynamic> m) {
  final keys = [
    'description',
    'mensaje',
    'descripcion',
    'detalle',
    'texto',
    'msg',
    'comment',
  ];
  for (final k in keys) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

/// -------- Helpers de adjuntos y lectura básica --------

/// Normaliza a mapas {name, url?, path?, desc?}
List<Map<String, String>> _attachmentsFromRoot(Map<String, dynamic> m) {
  final out = <Map<String, String>>[];

  // adjuntos: [{name,url?,path?,desc?/description?}] o [url]
  final adj = (m['adjuntos'] as List?) ?? (m['attachments'] as List?);
  if (adj != null) {
    for (final e in adj) {
      if (e is Map) {
        final mm = Map<String, dynamic>.from(e);
        out.add({
          'name': (mm['name'] ?? mm['filename'] ?? 'archivo').toString(),
          'url': (mm['url'] ?? '').toString(),
          'path': (mm['path'] ?? '').toString(),
          'desc': (mm['desc'] ?? mm['description'] ?? '').toString(),
        });
      } else if (e is String) {
        final name = Uri.tryParse(e)?.pathSegments.last ?? 'archivo';
        out.add({'name': name, 'url': e, 'desc': ''});
      }
    }
  }

  // evidencias: [url]
  final evid = (m['evidencias'] as List?)?.cast<dynamic>() ?? const [];
  for (final e in evid) {
    final url = e?.toString() ?? '';
    if (url.isEmpty) continue;
    final name = Uri.tryParse(url)?.pathSegments.last ?? 'evidencia';
    out.add({'name': name, 'url': url, 'desc': 'Evidencia'});
  }

  // evidencias_paths: [path]
  final evidPaths =
      (m['evidencias_paths'] as List?)?.cast<dynamic>() ?? const [];
  for (final p in evidPaths) {
    final path = p?.toString() ?? '';
    if (path.isEmpty) continue;
    final name = path.split('/').last;
    out.add({'name': name, 'path': path, 'desc': 'Evidencia (Storage)'});
  }

  // finalización en root (opcional)
  final fin = (m['completionAttachments'] as List?) ?? const [];
  for (final e in fin) {
    if (e is String) {
      final name = Uri.tryParse(e)?.pathSegments.last ?? 'finalizacion';
      out.add({'name': name, 'url': e, 'desc': 'Finalización'});
    } else if (e is Map) {
      final mm = Map<String, dynamic>.from(e);
      out.add({
        'name': (mm['name'] ?? 'finalizacion').toString(),
        'url': (mm['url'] ?? '').toString(),
        'path': (mm['path'] ?? '').toString(),
        'desc': (mm['desc'] ?? mm['description'] ?? 'Finalización').toString(),
      });
    }
  }

  return out;
}

/// Normaliza cualquier lista de adjuntos (String o Map) a [{name,url?,path?,desc?}]
List<Map<String, String>> _attachmentsFromAny(dynamic listOrNull) {
  final out = <Map<String, String>>[];
  final list = (listOrNull as List?) ?? const [];
  for (final e in list) {
    if (e is String) {
      final name = Uri.tryParse(e)?.pathSegments.last ?? 'archivo';
      out.add({'name': name, 'url': e, 'desc': ''});
    } else if (e is Map) {
      final mm = Map<String, dynamic>.from(e);
      out.add({
        'name': (mm['name'] ?? mm['filename'] ?? 'archivo').toString(),
        'url': (mm['url'] ?? '').toString(),
        'path': (mm['path'] ?? '').toString(),
        'desc': (mm['desc'] ?? mm['description'] ?? '').toString(),
      });
    }
  }
  return out;
}

/// Adjuntos de un avance (attachments + evidencias)
List<Map<String, String>> _attachmentsFromAvance(Map<String, dynamic> m) {
  final out = <Map<String, String>>[];
  out.addAll(_attachmentsFromAny(m['attachments']));

  final evid = (m['evidencias'] as List?)?.cast<dynamic>() ?? const [];
  for (final e in evid) {
    final url = e?.toString() ?? '';
    if (url.isEmpty) continue;
    final name = Uri.tryParse(url)?.pathSegments.last ?? 'evidencia';
    out.add({'name': name, 'url': url, 'desc': 'Evidencia'});
  }
  return out;
}

Future<bool> _openAttachment(Map<String, String> m) async {
  String? url = m['url'];
  if ((url == null || url.isEmpty) && (m['path']?.isNotEmpty ?? false)) {
    try {
      url = await FirebaseStorage.instance.ref(m['path']!).getDownloadURL();
    } catch (_) {
      url = null;
    }
  }
  if (url == null || !url.startsWith('http')) return false;

  if (await launchUrlString(url, mode: LaunchMode.externalApplication)) {
    return true;
  }
  if (await launchUrlString(url, mode: LaunchMode.inAppWebView)) {
    return true;
  }
  final docs =
      'https://docs.google.com/gview?embedded=1&url=${Uri.encodeComponent(url)}';
  return await launchUrlString(docs, mode: LaunchMode.inAppWebView);
}

/// Extrae fecha sugerida de un avance (varias llaves posibles)
DateTime? _extractSuggestedDate(Map<String, dynamic>? adv) {
  if (adv == null) return null;
  return _toDate(adv['nextDate']) ??
      _toDate(adv['nextdate']) ??
      _toDate(adv['sugerida']) ??
      _toDate(adv['propuesta']) ??
      _toDate(adv['due']);
}

/// Reúne adjuntos por categoría (tabs).
Future<Map<String, List<Map<String, String>>>> _collectAllAttachments(
    String taskId,
    Map<String, dynamic> taskRoot,
    ) async {
  final res = <String, List<Map<String, String>>>{};
  res['Tarea'] = _attachmentsFromRoot(taskRoot);

  // Novedades
  try {
    final qs = await FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .doc(taskId)
        .collection('novedades')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .get();
    final tmp = <Map<String, String>>[];
    for (final d in qs.docs) {
      final m = d.data();
      final msg = _msgOf(m);
      final att = (m['attachments'] as List?) ?? const [];
      for (final e in att) {
        if (e is String) {
          final name = Uri.tryParse(e)?.pathSegments.last ?? 'nvd_${d.id}';
          tmp.add({'name': name, 'url': e, 'desc': msg.isEmpty ? 'Novedad' : msg});
        } else if (e is Map) {
          final mm = Map<String, dynamic>.from(e);
          tmp.add({
            'name': (mm['name'] ?? 'novedad').toString(),
            'url': (mm['url'] ?? '').toString(),
            'path': (mm['path'] ?? '').toString(),
            'desc': (mm['desc'] ?? mm['description'] ?? msg.isEmpty ? 'Novedad' : msg).toString(),
          });
        }
      }
    }
    if (tmp.isNotEmpty) res['Novedades'] = tmp;
  } catch (_) {}

  // Avances
  try {
    final qs = await FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .doc(taskId)
        .collection('avances')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .get();
    final tmp = <Map<String, String>>[];
    for (final d in qs.docs) {
      final m = d.data();
      final msg = _msgOf(m);
      final evid = (m['evidencias'] as List?)?.cast<dynamic>() ?? const [];
      for (final e in evid) {
        final url = e?.toString() ?? '';
        if (url.isEmpty) continue;
        final name = Uri.tryParse(url)?.pathSegments.last ?? 'avance_${d.id}';
        tmp.add({'name': name, 'url': url, 'desc': msg.isEmpty ? 'Avance' : msg});
      }
      final att = (m['attachments'] as List?) ?? const [];
      for (final e in att) {
        if (e is Map) {
          final mm = Map<String, dynamic>.from(e);
          tmp.add({
            'name': (mm['name'] ?? 'avance').toString(),
            'url': (mm['url'] ?? '').toString(),
            'path': (mm['path'] ?? '').toString(),
            'desc': (mm['desc'] ?? mm['description'] ?? msg.isEmpty ? 'Avance' : msg).toString(),
          });
        } else if (e is String) {
          final name = Uri.tryParse(e)?.pathSegments.last ?? 'avance_${d.id}';
          tmp.add({'name': name, 'url': e, 'desc': msg.isEmpty ? 'Avance' : msg});
        }
      }
    }
    if (tmp.isNotEmpty) res['Avances'] = tmp;
  } catch (_) {}

  // Finalización
  try {
    final qs = await FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .doc(taskId)
        .collection('finalizacion')
        .orderBy('createdAt', descending: true)
        .limit(5)
        .get();
    final tmp = <Map<String, String>>[];
    for (final d in qs.docs) {
      final m = d.data();
      final msg = _msgOf(m);
      final att = (m['attachments'] as List?) ?? const [];
      for (final e in att) {
        if (e is String) {
          final name = Uri.tryParse(e)?.pathSegments.last ?? 'finalizacion_${d.id}';
          tmp.add({'name': name, 'url': e, 'desc': msg.isEmpty ? 'Finalización' : msg});
        } else if (e is Map) {
          final mm = Map<String, dynamic>.from(e);
          tmp.add({
            'name': (mm['name'] ?? 'finalizacion').toString(),
            'url': (mm['url'] ?? '').toString(),
            'path': (mm['path'] ?? '').toString(),
            'desc': (mm['desc'] ?? mm['description'] ?? msg.isEmpty ? 'Finalización' : msg).toString(),
          });
        }
      }
    }
    if (tmp.isNotEmpty) res['Finalización'] = tmp;
  } catch (_) {}

  return res;
}

/// Banner/hero con la última novedad (mensaje y fecha)
Future<Map<String, String>?> _latestNovedad(String taskId) async {
  try {
    final qs = await FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .doc(taskId)
        .collection('novedades')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (qs.docs.isEmpty) return null;
    final m = qs.docs.first.data();
    final msg = _msgOf(m);
    final created = _fmt(_toDate(m['createdAt']));
    return {'msg': msg, 'created': created};
  } catch (_) {
    return null;
  }
}

/// Detecta extensión y devuelve icono y etiqueta
(IconData, String) _iconAndLabelFor(String name) {
  final ext = name.split('.').last.toLowerCase();
  switch (ext) {
    case 'pdf':
      return (Icons.picture_as_pdf, 'PDF');
    case 'doc':
    case 'docx':
      return (Icons.description, 'Word');
    case 'xls':
    case 'xlsx':
      return (Icons.grid_on, 'Excel');
    case 'ppt':
    case 'pptx':
      return (Icons.slideshow, 'PowerPoint');
    case 'zip':
    case 'rar':
      return (Icons.archive, 'Archivo');
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
      return (Icons.image, 'Imagen');
    case 'mp4':
    case 'mov':
    case 'avi':
      return (Icons.movie, 'Video');
    default:
      return (Icons.insert_drive_file, 'Archivo');
  }
}

bool _isImageName(String name) {
  final ext = name.split('.').last.toLowerCase();
  return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
}

/// -------------------- Pantalla de Adjuntos --------------------

class _AttachmentsScreen extends StatelessWidget {
  final String taskId;
  final Map<String, dynamic> taskData;
  final Map<String, List<Map<String, String>>> tabsMap;
  final Map<String, String>? lastNovedad;
  final String? initialTabKey;

  const _AttachmentsScreen({
    required this.taskId,
    required this.taskData,
    required this.tabsMap,
    required this.lastNovedad,
    this.initialTabKey,
  });

  Color _tabCardColor(String k) {
    switch (k) {
      case 'Novedades':
        return const Color(0xFFE8EEFF); // light indigo
      case 'Avances':
        return const Color(0xFFEFF4FF); // even lighter indigo
      case 'Finalización':
        return const Color(0xFFE3F2FD); // light blue
      default:
        return const Color(0xFFF0F5FF); // default soft blue
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = tabsMap.keys.toList();
    int initIndex = 0;
    if (initialTabKey != null) {
      final i = keys.indexOf(initialTabKey!);
      if (i >= 0) initIndex = i;
    }
    return DefaultTabController(
      length: keys.length,
      initialIndex: initIndex,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FF),
        appBar: AppBar(
          backgroundColor: kBrand,
          title: const Text('Adjuntos de la tarea',
              style: TextStyle(fontFamily: kArial)),
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            indicatorColor: Colors.white,
            tabs: [for (final k in keys) Tab(text: '$k (${tabsMap[k]!.length})')],
          ),
        ),
        body: Column(
          children: [
            if (lastNovedad != null &&
                (lastNovedad!['msg'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFD3FF)),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.campaign,
                          size: 20, color: Color(0xFF1E3A8A)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Última novedad',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Color(0xFF102A63))),
                            const SizedBox(height: 4),
                            Text(
                              lastNovedad!['msg']!,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              lastNovedad!['created'] ?? '',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final k in keys)
                    ListView.separated(
                      padding:
                      const EdgeInsets.fromLTRB(12, 10, 12, 16),
                      itemCount: tabsMap[k]!.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final m = tabsMap[k]![i];
                        final name = (m['name'] ?? 'archivo').toString();
                        final desc = (m['desc'] ?? '').toString();
                        final cardColor = _tabCardColor(k);
                        final (iconData, label) = _iconAndLabelFor(name);
                        final isImage = _isImageName(name);
                        final url = m['url'] ?? '';

                        // Animación sutil por item (stagger)
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 16, end: 0),
                          duration:
                          Duration(milliseconds: 210 + (i * 18)),
                          builder: (ctx, dx, child) => Opacity(
                            opacity: (16 - dx) / 16,
                            child: Transform.translate(
                                offset: Offset(dx, 0), child: child),
                          ),
                          child: Card(
                            color: cardColor,
                            elevation: 0.5,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              dense: true,
                              visualDensity: const VisualDensity(
                                  horizontal: -2, vertical: -1),
                              leading: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                  Border.all(color: Colors.black12),
                                ),
                                child: Icon(iconData, size: 22),
                              ),
                              title: Text(
                                (desc.isNotEmpty ? desc : label),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                              trailing: isImage && url.isNotEmpty
                                  ? ClipRRect(
                                borderRadius:
                                BorderRadius.circular(8),
                                child: Image.network(
                                  url,
                                  width: 52,
                                  height: 36,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.open_in_new),
                                ),
                              )
                                  : const Icon(Icons.open_in_new),
                              onTap: () async {
                                final ok = await _openAttachment(m);
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                      content:
                                      Text('No se pudo abrir el archivo')));
                                }
                              },
                            ),
                          ),
                        );
                      },
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

/// Navegación con transición fluida (fade + slide)
void _pushAttachmentsPage(
    BuildContext context, {
      required String taskId,
      required Map<String, dynamic> taskData,
      required Map<String, List<Map<String, String>>> tabsMap,
      required Map<String, String>? lastNovedad,
      String? initialTabKey,
    }) {
  Navigator.of(context).push(PageRouteBuilder(
    pageBuilder: (_, __, ___) => _AttachmentsScreen(
      taskId: taskId,
      taskData: taskData,
      tabsMap: tabsMap,
      lastNovedad: lastNovedad,
      initialTabKey: initialTabKey,
    ),
    transitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (_, anim, __, child) {
      final slide = Tween<Offset>(
          begin: const Offset(0.06, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
      final fade =
      CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
          opacity: fade, child: SlideTransition(position: slide, child: child));
    },
  ));
}

/// Abre la pantalla de adjuntos (colecta y navega con animación).
Future<void> _openAttachmentsPage(
    BuildContext context, {
      required String taskId,
      required Map<String, dynamic> taskData,
      String? initialTabKey,
    }) async {
  final tabsMap = await _collectAllAttachments(taskId, taskData);
  if (tabsMap.isEmpty || tabsMap.values.every((l) => l.isEmpty)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay adjuntos.')));
    }
    return;
  }
  final lastN = await _latestNovedad(taskId);
  if (context.mounted) {
    _pushAttachmentsPage(context,
        taskId: taskId,
        taskData: taskData,
        tabsMap: tabsMap,
        lastNovedad: lastN,
        initialTabKey: initialTabKey);
  }
}

/// =========================================================
/// Historial con 2 pestañas: Asignadas a mí / Yo asigné
class TaskHistoryScreen extends StatefulWidget {
  final String currentUserId;
  const TaskHistoryScreen({super.key, required this.currentUserId});

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: kBrand,
          title: const Text('Historial de tareas',
              style: TextStyle(fontFamily: kArial)),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Asignadas a mí', icon: Icon(Icons.assignment_ind)),
              Tab(text: 'Yo asigné', icon: Icon(Icons.manage_accounts)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AssignedToMeTab(userId: ''),
            _ICreatedTab(userId: ''),
          ],
        ),
      ),
    );
  }
}

/// ======================= TAB 1: Asignadas a mí =======================

class _AssignedToMeTab extends StatefulWidget {
  final String userId;
  const _AssignedToMeTab({required this.userId});

  @override
  State<_AssignedToMeTab> createState() => _AssignedToMeTabState();
}

class _AssignedToMeTabState extends State<_AssignedToMeTab> {
  final _searchCtl = TextEditingController();

  // filtros
  String _areaSel = 'todas';
  String _estadoSel = 'todos';
  DateTime? _from;
  DateTime? _to;

  // catálogos
  final Map<String, String> _areasMap = {'todas': 'Todas'};
  final Map<String, String> _estadosMap = {
    'todos': 'Todos',
    'pendiente': 'Pendiente',
    'en_progreso': 'En progreso',
    'completada': 'Completada',
    'finalizado': 'Finalizada',
    'devuelta': 'Devuelta',
    'retrasado': 'Retrasado',
  };

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('TBL_AREAS')
          .limit(1000)
          .get();
      for (final d in qs.docs) {
        final m = d.data();
        final id = (m['areaId'] ?? d.id).toString();
        final nombre = (m['nombre'] ?? id).toString();
        _areasMap[id] = nombre;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Query<Map<String, dynamic>> _query(String userId) {
    return FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .where('asignado_uid', isEqualTo: userId);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365 * 2)),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _from == null || _to == null
          ? null
          : DateTimeRange(start: _from!, end: _to!),
    );
    if (range != null) setState(() {
      _from = range.start;
      _to = range.end;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query(widget.userId).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Column(
            children: [
              _filtersBar(),
              const Expanded(
                child: Center(
                  child: Text('No hay tareas asignadas.',
                      style: TextStyle(fontFamily: kArial)),
                ),
              ),
            ],
          );
        }

        int tsOf(Map<String, dynamic> m) {
          final t = (m['updatedAt'] as Timestamp?) ??
              (m['fecha_actualizacion'] as Timestamp?) ??
              (m['createdAt'] as Timestamp?) ??
              (m['fecha_creacion'] as Timestamp?);
          return t?.toDate().millisecondsSinceEpoch ?? 0;
        }

        var ordered = [...docs]
          ..sort((a, b) => tsOf(b.data()).compareTo(tsOf(a.data())));

        // Filtros (cliente)
        final q = _searchCtl.text.trim().toLowerCase();
        ordered = ordered.where((d) {
          final m = d.data();
          final title =
          ((m['titulo'] ?? m['title'] ?? '') as String).toLowerCase();
          final areaId = (m['areaId'] ?? '').toString();
          final estado = _resolvedEstado(m);
          final due = _toDate(m['fecha_limite']);
          if (q.isNotEmpty && !title.contains(q)) return false;
          if (_areaSel != 'todas' && areaId != _areaSel) return false;
          if (_estadoSel != 'todos' && estado != _estadoSel) return false;
          if (_from != null &&
              (due == null ||
                  due.isBefore(
                      DateTime(_from!.year, _from!.month, _from!.day)))) {
            return false;
          }
          if (_to != null &&
              (due == null ||
                  due.isAfter(DateTime(
                      _to!.year, _to!.month, _to!.day, 23, 59, 59)))) {
            return false;
          }
          return true;
        }).toList();

        return Column(
          children: [
            _filtersBar(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                itemCount: ordered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _AssignedTile(doc: ordered[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _filtersBar() {
    const pill = OutlineInputBorder(
      borderSide: BorderSide(color: Colors.black26),
      borderRadius: BorderRadius.all(Radius.circular(10)),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Column(
        children: [
          // Fila 1: búsqueda
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar por título…',
                    border: pill, enabledBorder: pill, focusedBorder: pill,
                    contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Fila 2: Área + Estado (misma fila)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isDense: true,
                  value: _areaSel,
                  decoration: const InputDecoration(
                    isDense: true, labelText: 'Área',
                    border: pill, enabledBorder: pill,
                    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  ),
                  items: _areasMap.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _areaSel = v ?? 'todas'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isDense: true,
                  value: _estadoSel,
                  decoration: const InputDecoration(
                    isDense: true, labelText: 'Estado',
                    border: pill, enabledBorder: pill,
                    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  ),
                  items: _estadosMap.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _estadoSel = v ?? 'todos'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Fila 3: Rango de fechas
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month, size: 18),
                label: Text(
                  _from == null && _to == null
                      ? 'Rango de fechas'
                      : '${_from == null ? '—' : DateFormat('dd/MM').format(_from!)}  →  ${_to == null ? '—' : DateFormat('dd/MM').format(_to!)}',
                ),
                onPressed: _pickDateRange,
              ),
              const SizedBox(width: 8),
              if (_from != null || _to != null)
                TextButton.icon(
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Quitar rango'),
                  onPressed: () => setState(() { _from = null; _to = null; }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssignedTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _AssignedTile({required this.doc});

  Widget _pillSmall(IconData icon, String value) {
    final isEmpty = value.trim().isEmpty || value == '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: isEmpty ? Colors.grey : Colors.black87),
        const SizedBox(width: 4),
        Text(isEmpty ? "—" : value,
            style: const TextStyle(fontFamily: kArial, fontSize: 11)),
      ]),
    );
  }

  Widget _pillActionSmall(
      IconData icon, String value, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: _pillSmall(icon, value),
      ),
    );
  }

  Widget _countdownBadge(DateTime? due, String estado) {
    if (estado == 'finalizado') return const SizedBox.shrink();
    final d = _daysLeft(due);
    if (d == null) return const SizedBox.shrink();
    Color bg;
    if (d > 0) {
      bg = Colors.green.shade600;
    } else if (d == 0) {
      bg = Colors.orange.shade700;
    } else {
      bg = Colors.red.shade700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        d.toString(),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showNovedadDialog(
      BuildContext context, {
        required String taskId,
        required Map<String, dynamic> taskData,
        required Map<String, dynamic> novedad,
      }) {
    final msg = _msgOf(novedad);
    final created = _fmt(_toDate(novedad['createdAt']));
    final atts = _attachmentsFromAny(novedad['attachments']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.campaign, color: Color(0xFF1E3A8A)),
                const SizedBox(width: 8),
                const Text('Novedad',
                    style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Text(created,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54)),
              ]),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFD3FF)),
                ),
                child: Text(
                  msg.isEmpty ? 'Sin descripción' : msg,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (atts.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Adjuntos',
                    style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: atts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final a = atts[i];
                    final (icon, _) =
                    _iconAndLabelFor(a['name'] ?? 'archivo');
                    return ListTile(
                      dense: true,
                      tileColor: const Color(0xFFEFF4FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(icon),
                      title: Text(a['desc']?.isNotEmpty == true
                          ? a['desc']!
                          : (a['name'] ?? 'archivo')),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () async {
                        final ok = await _openAttachment(a);
                        if (!ok && ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content:
                                Text('No se pudo abrir el archivo')),
                          );
                        }
                      },
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kBrand),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Ver adjuntos'),
                  onPressed: () {
                    Navigator.pop(context);
                    _openAttachmentsPage(
                      context,
                      taskId: taskId,
                      taskData: taskData,
                      initialTabKey: 'Novedades',
                    );
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipEstado(String estado) => Chip(
    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    visualDensity:
    const VisualDensity(horizontal: -3, vertical: -3),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    label: Text(
      (estado.isEmpty ? 'sin estado' : estado),
      style: const TextStyle(
          color: Colors.white, fontFamily: kArial, fontSize: 11),
    ),
    backgroundColor: _statusColor(estado),
  );

  void _showQuickDetails(BuildContext context, Map<String, dynamic> m) {
    final asignado =
    (m['asignado_nombre'] ?? m['assignedToName'] ?? '').toString();
    final vence = _fmt(_toDate(m['fecha_limite']));
    final prioridad = (m['prioridad'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((m['titulo'] ?? '(Sin título)').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              _kv('Asignado', asignado.isEmpty ? '—' : asignado),
              _kv('Vence', vence),
              if (prioridad.isNotEmpty)
                _kv('Prioridad', prioridad.toUpperCase()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(
            width: 100,
            child: Text('$k:',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13))),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: doc.reference
          .collection('novedades')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get(),
      builder: (ctx, snap) {
        Map<String, dynamic>? lastNovedad;
        if (snap.data?.docs.isNotEmpty ?? false) {
          lastNovedad = snap.data!.docs.first.data();
        }
        final hasNovedad = lastNovedad != null;

        final m = doc.data();
        final title =
        (m['titulo'] ?? m['title'] ?? '(Sin título)').toString();
        final estado = _resolvedEstado(m);
        final prioridad = (m['prioridad'] ?? '').toString().toUpperCase();
        final due = _toDate(m['fecha_limite']);
        final vence = _fmt(due);

        return Card(
          elevation: 1,
          color: const Color(0xFFF0F5FF),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (lastNovedad != null) {
                _showNovedadDialog(context,
                    taskId: doc.id, taskData: m, novedad: lastNovedad!);
              } else {
                _openAttachmentsPage(
                    context, taskId: doc.id, taskData: m);
              }
            },
            onLongPress: () => _showQuickDetails(context, m),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding:
                      const EdgeInsets.only(top: 2, right: 10),
                      child: Icon(
                        hasNovedad
                            ? Icons.error_outline
                            : Icons.assignment_outlined,
                        color: hasNovedad
                            ? Colors.amber.shade700
                            : Colors.grey,
                        size: 18,
                      ),
                    ),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _chipEstado(estado),
                                _pillSmall(Icons.schedule, vence),
                                if (prioridad == 'ALTA')
                                  _pillSmall(Icons.flag, prioridad),
                                if (hasNovedad)
                                  _pillActionSmall(
                                    Icons.campaign,
                                    'Novedad',
                                        () => _showNovedadDialog(
                                      context,
                                      taskId: doc.id,
                                      taskData: m,
                                      novedad: lastNovedad!,
                                    ),
                                  ),
                              ],
                            ),
                          ]),
                    ),
                    const SizedBox(width: 8),
                    _countdownBadge(due, estado),
                  ]),
            ),
          ),
        );
      },
    );
  }
}

/// ======================= TAB 2: Yo asigné =======================

class _ICreatedTab extends StatefulWidget {
  final String userId;
  const _ICreatedTab({required this.userId});

  @override
  State<_ICreatedTab> createState() => _ICreatedTabState();
}

class _ICreatedTabState extends State<_ICreatedTab> {
  final _searchCtl = TextEditingController();

  String _areaSel = 'todas';
  String _estadoSel = 'todos';
  DateTime? _from;
  DateTime? _to;

  final Map<String, String> _areasMap = {'todas': 'Todas'};
  final Map<String, String> _estadosMap = const {
    'todos': 'Todos',
    'pendiente': 'Pendiente',
    'en_progreso': 'En progreso',
    'completada': 'Completada',
    'finalizado': 'Finalizada',
    'devuelta': 'Devuelta',
    'retrasado': 'Retrasado',
  };

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('TBL_AREAS')
          .limit(1000)
          .get();
      for (final d in qs.docs) {
        final m = d.data();
        final id = (m['areaId'] ?? d.id).toString();
        final nombre = (m['nombre'] ?? id).toString();
        _areasMap[id] = nombre;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    return FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .where('creador_id', isEqualTo: widget.userId)
        .snapshots();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365 * 2)),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _from == null || _to == null
          ? null
          : DateTimeRange(start: _from!, end: _to!),
    );
    if (range != null) setState(() {
      _from = range.start;
      _to = range.end;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Column(
            children: [
              _filtersBar(),
              const Expanded(
                child: Center(
                  child: Text('No has creado tareas.',
                      style: TextStyle(fontFamily: kArial)),
                ),
              ),
            ],
          );
        }

        int tsOf(Map<String, dynamic> m) {
          final t = (m['updatedAt'] as Timestamp?) ??
              (m['fecha_actualizacion'] as Timestamp?) ??
              (m['createdAt'] as Timestamp?) ??
              (m['fecha_creacion'] as Timestamp?);
          return t?.toDate().millisecondsSinceEpoch ?? 0;
        }

        var ordered = [...docs]
          ..sort((a, b) => tsOf(b.data()).compareTo(tsOf(a.data())));

        final q = _searchCtl.text.trim().toLowerCase();
        ordered = ordered.where((d) {
          final m = d.data();
          final title =
          ((m['titulo'] ?? m['title'] ?? '') as String).toLowerCase();
          final areaId = (m['areaId'] ?? '').toString();
          final estado = _resolvedEstado(m);
          final due = _toDate(m['fecha_limite']);
          if (q.isNotEmpty && !title.contains(q)) return false;
          if (_areaSel != 'todas' && areaId != _areaSel) return false;
          if (_estadoSel != 'todos' && estado != _estadoSel) return false;
          if (_from != null &&
              (due == null ||
                  due.isBefore(
                      DateTime(_from!.year, _from!.month, _from!.day)))) {
            return false;
          }
          if (_to != null &&
              (due == null ||
                  due.isAfter(DateTime(
                      _to!.year, _to!.month, _to!.day, 23, 59, 59)))) {
            return false;
          }
          return true;
        }).toList();

        return Column(
          children: [
            _filtersBar(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                itemCount: ordered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _CreatedTile(doc: ordered[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _filtersBar() {
    const pill = OutlineInputBorder(
      borderSide: BorderSide(color: Colors.black26),
      borderRadius: BorderRadius.all(Radius.circular(10)),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Column(
        children: [
          // Fila 1: búsqueda
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar por título…',
                    border: pill, enabledBorder: pill, focusedBorder: pill,
                    contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Fila 2: Área + Estado (misma fila)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isDense: true,
                  value: _areaSel,
                  decoration: const InputDecoration(
                    isDense: true, labelText: 'Área',
                    border: pill, enabledBorder: pill,
                    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  ),
                  items: _areasMap.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _areaSel = v ?? 'todas'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isDense: true,
                  value: _estadoSel,
                  decoration: const InputDecoration(
                    isDense: true, labelText: 'Estado',
                    border: pill, enabledBorder: pill,
                    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  ),
                  items: _estadosMap.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _estadoSel = v ?? 'todos'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Fila 3: Rango de fechas
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month, size: 18),
                label: Text(
                  _from == null && _to == null
                      ? 'Rango de fechas'
                      : '${_from == null ? '—' : DateFormat('dd/MM').format(_from!)}  →  ${_to == null ? '—' : DateFormat('dd/MM').format(_to!)}',
                ),
                onPressed: _pickDateRange,
              ),
              const SizedBox(width: 8),
              if (_from != null || _to != null)
                TextButton.icon(
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Quitar rango'),
                  onPressed: () => setState(() { _from = null; _to = null; }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreatedTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  _CreatedTile({required this.doc});

  Future<Map<String, dynamic>?> _latest(String sub) async {
    final qs = await doc.reference
        .collection(sub)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (qs.docs.isEmpty) return null;
    return qs.docs.first.data();
  }

  Widget _chipMini(String text, Color bg) => Chip(
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity:
    const VisualDensity(horizontal: -3, vertical: -3),
    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    label: Text(text,
        style: const TextStyle(
            fontFamily: kArial, fontSize: 11, color: Colors.white)),
    backgroundColor: bg,
  );

  Widget _pillMini(String text) => Chip(
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity:
    const VisualDensity(horizontal: -3, vertical: -3),
    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    label: Text(text,
        style: const TextStyle(fontFamily: kArial, fontSize: 11)),
    backgroundColor: Colors.white,
    side: const BorderSide(color: Colors.black12),
  );

  Widget _countdownBadge(DateTime? due, String estado) {
    if (estado == 'finalizado') return const SizedBox.shrink();
    final d = _daysLeft(due);
    if (d == null) return const SizedBox.shrink();
    Color bg;
    if (d > 0) {
      bg = Colors.green.shade600;
    } else if (d == 0) {
      bg = Colors.orange.shade700;
    } else {
      bg = Colors.red.shade700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        d.toString(),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final title = (m['titulo'] ?? m['title'] ?? '(Sin título)').toString();
    final asignado = (m['asignado_nombre'] ?? '').toString();
    final estado = _resolvedEstado(m);
    final prioridad = (m['prioridad'] ?? '').toString().toUpperCase();
    final due = _toDate(m['fecha_limite']);
    final vence = _fmt(due);

    return FutureBuilder(
      future: Future.wait([_latest('novedades'), _latest('avances')]),
      builder: (context, snap) {
        Map<String, dynamic>? lastN =
        (snap.data is List && (snap.data as List).isNotEmpty)
            ? (snap.data as List)[0] as Map<String, dynamic>?
            : null;
        Map<String, dynamic>? lastA =
        (snap.data is List && (snap.data as List).length >= 2)
            ? (snap.data as List)[1] as Map<String, dynamic>?
            : null;

        final hasNovedad = lastN != null;
        final hasAvance = lastA != null;

        final leading = estado == 'finalizado'
            ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
            : (hasNovedad
            ? const Icon(Icons.error_outline, color: Colors.amber, size: 20)
            : const Icon(Icons.assignment_outlined,
            color: Colors.grey, size: 20));

        return Card(
          elevation: hasNovedad ? 2 : 1,
          color: const Color(0xFFF0F5FF),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            dense: true,
            visualDensity:
            const VisualDensity(horizontal: -3, vertical: -3),
            leading: leading,
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Asignado: ${asignado.isEmpty ? "—" : asignado}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: kArial, fontSize: 12)),
                  _chipMini('Estado: ${estado.isEmpty ? "—" : estado}',
                      _statusColor(estado)),
                  _pillMini('Vence: $vence'),
                  if (prioridad == 'ALTA') _pillMini('Prioridad: $prioridad'),
                  if (hasNovedad) _pillMini('Novedad'),
                  if (hasAvance) _pillMini('Avance'),
                ],
              ),
            ),
            trailing: _countdownBadge(due, estado),
            onTap: () => _openActions(context, doc,
                lastN: lastN, lastA: lastA, resEstado: estado),
          ),
        );
      },
    );
  }

  Future<void> _openActions(
      BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc, {
        Map<String, dynamic>? lastN,
        Map<String, dynamic>? lastA,
        required String resEstado,
      }) async {
    final m = doc.data();

    if (resEstado == 'finalizado') {
      // Solo ver adjuntos
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Wrap(children: [
              ListTile(
                dense: true,
                visualDensity:
                const VisualDensity(horizontal: -3, vertical: -3),
                title: Text(
                  (m['titulo'] ?? m['title'] ?? '(Sin título)').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('ID: ${doc.id}',
                    style: const TextStyle(fontSize: 12)),
                trailing: Chip(
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  visualDensity:
                  const VisualDensity(horizontal: -3, vertical: -3),
                  materialTapTargetSize:
                  MaterialTapTargetSize.shrinkWrap,
                  label: const Text('finalizado',
                      style: TextStyle(color: Colors.white, fontSize: 11)),
                  backgroundColor: _statusColor('finalizado'),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                visualDensity:
                const VisualDensity(horizontal: -3, vertical: -3),
                leading: const Icon(Icons.folder_open),
                title: const Text('Ver adjuntos'),
                onTap: () async {
                  Navigator.pop(context);
                  await _openAttachmentsPage(
                    context,
                    taskId: doc.id,
                    taskData: m,
                  );
                },
              ),
              const SizedBox(height: 6),
            ]),
          ),
        ),
      );
      return;
    }

    // Modal con acciones completas
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Wrap(children: [
            ListTile(
              dense: true,
              visualDensity:
              const VisualDensity(horizontal: -3, vertical: -3),
              title: Text(
                (m['titulo'] ?? m['title'] ?? '(Sin título)').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('ID: ${doc.id}',
                  style: const TextStyle(fontSize: 12)),
              trailing: Chip(
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                visualDensity:
                const VisualDensity(horizontal: -3, vertical: -3),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text(resEstado.isEmpty ? 'sin_estado' : resEstado,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11)),
                backgroundColor: _statusColor(resEstado),
              ),
            ),
            const Divider(height: 1),

            ListTile(
              dense: true,
              visualDensity:
              const VisualDensity(horizontal: -3, vertical: -3),
              leading: const Icon(Icons.report_problem_outlined),
              title: const Text('Responder novedad'),
              subtitle: Text(
                lastN == null
                    ? 'No hay novedad reciente (igual puedes responder).'
                    : _msgOf(lastN!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () async {
                Navigator.pop(context);
                await _dialogResponderNovedad(context, doc);
              },
            ),
            ListTile(
              dense: true,
              visualDensity:
              const VisualDensity(horizontal: -3, vertical: -3),
              leading: const Icon(Icons.trending_up),
              title: const Text('Gestionar avance'),
              subtitle: Text(
                lastA == null ? 'No hay avance reciente (puedes gestionar el plazo).'
                    : _msgOf(lastA!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () async {
                Navigator.pop(context);
                await _dialogGestionarAvance(context, doc, lastA: lastA);
              },
            ),
            const Divider(height: 1),

            ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
              leading: const Icon(Icons.verified_outlined),
              title: const Text('Aprobar finalización'),
              onTap: () async {
                Navigator.pop(context);
                await _aprobarFinalizacion(context, doc);
              },
            ),
            ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
              leading: const Icon(Icons.undo),
              title: const Text('Devolver tarea (asignar nueva fecha)'),
              onTap: () async {
                Navigator.pop(context);
                await _devolverTarea(context, doc);
              },
            ),

            const Divider(height: 1),
            ListTile(
              dense: true,
              visualDensity:
              const VisualDensity(horizontal: -3, vertical: -3),
              leading: const Icon(Icons.folder_open),
              title: const Text('Ver adjuntos'),
              onTap: () async {
                Navigator.pop(context);
                await _openAttachmentsPage(
                  context,
                  taskId: doc.id,
                  taskData: m,
                );
              },
            ),

            const SizedBox(height: 6),
          ]),
        ),
      ),
    );
  }

  // ---------- Novedad ----------
  Future<void> _dialogResponderNovedad(
      BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final txtCtrl = TextEditingController();
    DateTime? nuevaFecha;
    bool aprueba = true;

    Future<void> pickFecha(void Function(void Function()) sbSetState) async {
      final now = DateTime.now();
      final d = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
      );
      if (d != null) sbSetState(() => nuevaFecha = d);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, sbSetState) => AlertDialog(
          title: const Text('Responder novedad'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('¿Apruebas la novedad? Puedes asignar nueva fecha si apruebas.'),
              const SizedBox(height: 8),
              RadioListTile<bool>(
                dense: true,
                visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
                value: true,
                groupValue: aprueba,
                onChanged: (v) => sbSetState(() => aprueba = true),
                title: const Text('Aprobar (asignar plazo)'),
              ),
              RadioListTile<bool>(
                dense: true,
                visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
                value: false,
                groupValue: aprueba,
                onChanged: (v) => sbSetState(() => aprueba = false),
                title: const Text('Rechazar (mantener plazo)'),
              ),
              const SizedBox(height: 8),
              if (aprueba)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month),
                    onPressed: () => pickFecha(sbSetState),
                    label: Text(
                      nuevaFecha == null
                          ? 'Elegir nueva fecha'
                          : 'Nueva fecha: ${DateFormat('dd/MM/yyyy').format(nuevaFecha!)}',
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: txtCtrl,
                decoration: const InputDecoration(
                  hintText: 'Comentario (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enviar')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final resp = {
      'type': 'respuesta_novedad',
      'approved': aprueba == true,
      'comment': txtCtrl.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };
    await doc.reference.collection('novedades').add(resp);

    if (aprueba == true && nuevaFecha != null) {
      await doc.reference.update({
        'fecha_limite': Timestamp.fromDate(nuevaFecha!),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await doc.reference.update({'updatedAt': FieldValue.serverTimestamp()});
    }

    final assigned = (doc.data()['asignado_uid'] ?? '').toString();
    if (assigned.isNotEmpty) {
      final fn = FirebaseFunctions.instance.httpsCallable('notifyTaskNews');
      await fn.call(<String, dynamic>{
        'taskId': doc.id,
        'title': 'Respuesta a novedad',
        'body': aprueba == true
            ? 'Se aprobó la novedad. ${nuevaFecha != null ? "Nueva fecha: ${DateFormat('dd/MM/yyyy').format(nuevaFecha!)}" : ""}'
            : 'Se rechazó la novedad. Se mantiene el plazo.',
        'creatorId': assigned,
      });
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Respuesta enviada')));
    }
  }

  // ---------- Avance (con fecha sugerida) ----------
  Future<void> _dialogGestionarAvance(
      BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc, {
        Map<String, dynamic>? lastA, // mensaje y posible nextDate
      }) async {
    final mensaje = _msgOf(lastA ?? {});
    final DateTime? sugerida = _extractSuggestedDate(lastA);

    // usamos strings para opciones
    String opSel = (sugerida != null) ? 'sugerida' : 'mantener';
    DateTime? nuevaFecha;

    Future<void> pickFecha(void Function(void Function()) sbSetState) async {
      final now = DateTime.now();
      final d = await showDatePicker(
        context: context,
        initialDate: (nuevaFecha ?? sugerida ?? now),
        firstDate: now,
        lastDate: now.add(const Duration(days: 365 * 2)),
      );
      if (d != null) sbSetState(() => nuevaFecha = d);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, sbSetState) => AlertDialog(
          title: const Text('Gestionar avance'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mensaje.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      border: Border.all(color: const Color(0xFFBFD3FF)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      mensaje,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              RadioListTile<String>(
                dense: true,
                visualDensity:
                const VisualDensity(horizontal: -3, vertical: -3),
                value: 'mantener',
                groupValue: opSel,
                onChanged: (v) => sbSetState(() => opSel = v ?? 'mantener'),
                title: const Text('Mantener fecha actual'),
                subtitle: const Text('No se modifica el plazo.'),
              ),
              if (sugerida != null)
                RadioListTile<String>(
                  dense: true,
                  visualDensity:
                  const VisualDensity(horizontal: -3, vertical: -3),
                  value: 'sugerida',
                  groupValue: opSel,
                  onChanged: (v) => sbSetState(() => opSel = v ?? 'sugerida'),
                  title: Text(
                      'Aceptar fecha sugerida (${DateFormat('dd/MM/yyyy').format(sugerida)})'),
                ),
              RadioListTile<String>(
                dense: true,
                visualDensity:
                const VisualDensity(horizontal: -3, vertical: -3),
                value: 'nueva',
                groupValue: opSel,
                onChanged: (v) => sbSetState(() => opSel = v ?? 'nueva'),
                title: const Text('Asignar nueva fecha'),
                subtitle: (opSel == 'nueva' && nuevaFecha != null)
                    ? Text(
                    'Nueva fecha: ${DateFormat('dd/MM/yyyy').format(nuevaFecha!)}')
                    : null,
              ),
              if (opSel == 'nueva')
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => pickFecha(sbSetState),
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      nuevaFecha == null
                          ? 'Elegir nueva fecha'
                          : 'Nueva fecha: ${DateFormat('dd/MM/yyyy').format(nuevaFecha!)}',
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (opSel == 'nueva' && nuevaFecha == null) return;
                Navigator.pop(context, true);
              },
              child: const Text('Aplicar'),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _openAttachmentsPage(
                  context,
                  taskId: doc.id,
                  taskData: doc.data(),
                  initialTabKey: 'Avances',
                );
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Ver adjuntos'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    // Resolver la fecha final a aplicar
    DateTime? fechaFinal;
    if (opSel == 'sugerida') fechaFinal = sugerida;
    if (opSel == 'nueva') fechaFinal = nuevaFecha;

    if (fechaFinal != null) {
      await doc.reference.update({
        'fecha_limite': Timestamp.fromDate(fechaFinal),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await doc.reference.update({'updatedAt': FieldValue.serverTimestamp()});
    }

    // Notificar
    final assigned = (doc.data()['asignado_uid'] ?? '').toString();
    if (assigned.isNotEmpty) {
      final fn = FirebaseFunctions.instance.httpsCallable('notifyTaskNews');
      final body = (fechaFinal != null)
          ? 'Nueva fecha: ${DateFormat('dd/MM/yyyy').format(fechaFinal)}'
          : 'Se mantiene la fecha actual.';
      await fn.call(<String, dynamic>{
        'taskId': doc.id,
        'title': 'Gestión de avance',
        'body': body,
        'creatorId': assigned,
      });
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Actualización aplicada')));
    }
  }

  // ---------- Finalización ----------
  Future<void> _aprobarFinalizacion(
      BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    await doc.reference.update({
      'approved': true,
      'approvedAt': FieldValue.serverTimestamp(),
      'estado': 'finalizado',  // set ambos
      'status': 'finalizado',  // set ambos
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final assigned = (doc.data()['asignado_uid'] ?? '').toString();
    if (assigned.isNotEmpty) {
      final fn =
      FirebaseFunctions.instance.httpsCallable('notifyTaskCompleted');
      await fn.call(<String, dynamic>{
        'creatorId': assigned,
        'taskId': doc.id,
        'title': 'Tarea aprobada',
        'body': 'La finalización fue aprobada.',
      });
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Finalización aprobada')));
    }
  }

  // ---------- Devolver ----------
  Future<void> _devolverTarea(
      BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    DateTime? nuevaFecha;
    final motivoCtrl = TextEditingController();

    Future<void> pickFecha() async {
      final now = DateTime.now();
      final d = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)),
      );
      if (d != null) nuevaFecha = d;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Devolver tarea'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Explica por qué se devuelve y asigna nueva fecha de entrega.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: pickFecha,
              icon: const Icon(Icons.calendar_month),
              label: Text(
                nuevaFecha == null
                    ? 'Elegir nueva fecha'
                    : 'Nueva fecha: ${DateFormat('dd/MM/yyyy').format(nuevaFecha!)}',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                hintText: 'Motivo (requerido)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Devolver')),
        ],
      ),
    );

    if (ok == true &&
        nuevaFecha != null &&
        motivoCtrl.text.trim().isNotEmpty) {
      await doc.reference.update({
        'estado': 'en_progreso',
        'status': 'en_progreso',
        'fecha_limite': Timestamp.fromDate(nuevaFecha!),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await doc.reference.collection('novedades').add({
        'type': 'devolucion',
        'reason': motivoCtrl.text.trim(),
        'newDueDate': Timestamp.fromDate(nuevaFecha!),
        'createdAt': FieldValue.serverTimestamp(),
      });

      final assigned = (doc.data()['asignado_uid'] ?? '').toString();
      if (assigned.isNotEmpty) {
        final fn = FirebaseFunctions.instance.httpsCallable('notifyTaskNews');
        await fn.call(<String, dynamic>{
          'taskId': doc.id,
          'title': 'Tarea devuelta',
          'body':
          'Se devolvió la tarea. Nueva fecha: ${DateFormat('dd/MM/yyyy').format(nuevaFecha!)}. Motivo: ${motivoCtrl.text.trim()}',
          'creatorId': assigned,
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Tarea devuelta')));
      }
    } else if (ok == true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Debes indicar motivo y nueva fecha.')));
      }
    }
  }
}
