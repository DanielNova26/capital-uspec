import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'facturacion_dashboard_screen.dart';
import 'facturacion_models.dart';

Future<bool> tryOpenFacturacionDocumentTask(
  BuildContext context, {
  required String userId,
  required String taskId,
  Map<String, dynamic>? taskData,
}) async {
  final id = taskId.trim();
  if (id.isEmpty) return false;

  final data =
      taskData ??
      (await FirebaseFirestore.instance.collection('TBL_TAREAS').doc(id).get())
          .data();
  if (data == null) return false;

  final target = FacDocumentTaskTarget.fromTaskData(id, data);
  if (target == null) return false;

  if (target.asignadoUid != userId.trim()) {
    return false;
  }
  if (!context.mounted) return true;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FacturacionDocumentUploadScreen(
        userId: userId,
        empresaId: target.empresaId,
        establecimientoId: target.establecimientoId,
        docTipo: target.docTipo,
        mes: target.mes,
        taskId: target.taskId,
        fechaLimite: target.fechaLimite,
      ),
    ),
  );
  return true;
}
