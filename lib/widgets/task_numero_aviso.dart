// lib/widgets/task_numero_aviso.dart
//
// "Tarea No. 2088" en rojo en los avisos (documento "Tareas - octubre 04 de
// 2026": "Notificaciones: mostrar número de tarea"). Los avisos nuevos traen
// `taskNumero`; los anteriores solo el id de la tarea, y el número se busca
// una vez por tarea (únicamente para los avisos que se están viendo).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/task_estado_visible.dart' show taskNumero;

const Color kTaskNumeroAvisoColor = Color(0xFFDC2626);

/// Quita el "Tarea No. N · " con que empieza la descripción de un aviso
/// cuando el número ya se muestra aparte.
String sinPrefijoNumeroTarea(String texto) =>
    texto.replaceFirst(RegExp(r'^Tarea No\. \d+( · )?'), '');

class TaskNumeroAvisoChip extends StatelessWidget {
  /// Id de la tarea del aviso. Los avisos de otros módulos usan prefijos
  /// (`visita:`, `proveedor:`…) y no se buscan.
  final String? taskId;

  /// `taskNumero` del aviso, si lo trae.
  final Object? numero;

  const TaskNumeroAvisoChip({super.key, this.taskId, this.numero});

  static final Map<String, Future<int?>> _cache = {};

  static Future<int?> _buscar(String id) => _cache.putIfAbsent(id, () async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(id)
          .get();
      return taskNumero(snap.data() ?? const <String, dynamic>{});
    } catch (_) {
      // Sin permiso o sin conexión: el aviso se muestra sin número.
      return null;
    }
  });

  Widget _etiqueta(int n) => Text(
    'Tarea No. $n',
    style: const TextStyle(
      fontFamily: 'Arial',
      fontSize: 12,
      fontWeight: FontWeight.w900,
      color: kTaskNumeroAvisoColor,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final propio = taskNumero({'numero': numero});
    if (propio != null) return _etiqueta(propio);
    final id = (taskId ?? '').trim();
    if (id.isEmpty || id.contains(':') || id.contains('/')) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<int?>(
      future: _buscar(id),
      builder: (_, snap) {
        final n = snap.data;
        return n == null ? const SizedBox.shrink() : _etiqueta(n);
      },
    );
  }
}
