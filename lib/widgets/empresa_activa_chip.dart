// lib/widgets/empresa_activa_chip.dart
//
// Nombre de la empresa activa en el encabezado de cada módulo.
//
// Pedido del 28 sep 2026: "mostrar siempre el nombre de la empresa en la
// parte superior a mano derecha". Con varias empresas, nada en la pantalla
// del módulo decía en cuál se estaba trabajando, y el cambio de empresa vive
// en el Home.
//
// El nombre se lee una vez por empresa y queda en memoria: el encabezado se
// redibuja con cada pestaña y cada filtro, y un FutureBuilder con la consulta
// dentro de `build` volvía a leer TBL_EMPRESAS en cada redibujo.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_typography.dart';

/// Nombre legible de una empresa a partir de su documento.
///
/// Nunca devuelve el id crudo: si el documento no trae nombre, vacío, y quien
/// llama no pinta nada (mismo criterio que áreas y personas).
String nombreEmpresaDeDocumento(Map<String, dynamic>? data) {
  if (data == null) return '';
  for (final clave in const [
    'nombre',
    'nombreEmpresa',
    'alias',
    'razonSocial',
  ]) {
    final valor = (data[clave] ?? '').toString().trim();
    if (valor.isNotEmpty) return valor;
  }
  return '';
}

class NombresEmpresa {
  NombresEmpresa._();

  static final Map<String, Future<String>> _cache = {};

  /// Nombre de la empresa, leído una sola vez por sesión.
  static Future<String> de(String empresaId) {
    final id = empresaId.trim();
    if (id.isEmpty || id == 'Sin empresa') return Future.value('');
    return _cache.putIfAbsent(id, () => _leer(id));
  }

  static Future<String> _leer(String id) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('TBL_EMPRESAS')
          .doc(id)
          .get();
      return nombreEmpresaDeDocumento(doc.data());
    } catch (_) {
      // Un fallo no se queda en caché: el siguiente encabezado reintenta.
      _cache.remove(id);
      return '';
    }
  }
}

/// Nombre de la empresa activa. [compacto] es la versión del AppBar móvil:
/// texto sobre el color del módulo, sin recuadro.
class EmpresaActivaChip extends StatelessWidget {
  final String empresaId;
  final Color accentColor;
  final bool compacto;

  /// Lo que se pinta mientras no hay nombre (o si la empresa no lo tiene).
  final Widget? sinNombre;

  const EmpresaActivaChip({
    super.key,
    required this.empresaId,
    required this.accentColor,
    this.compacto = false,
    this.sinNombre,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: NombresEmpresa.de(empresaId),
      builder: (context, snap) {
        final nombre = (snap.data ?? '').trim();
        if (nombre.isEmpty) return sinNombre ?? const SizedBox.shrink();
        if (compacto) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.business_rounded,
                size: 12,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          );
        }
        return Tooltip(
          message: 'Empresa activa',
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accentColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.business_rounded, size: 16, color: accentColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
