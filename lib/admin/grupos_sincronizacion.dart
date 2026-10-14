// lib/admin/grupos_sincronizacion.dart
//
// Admin › Gestión interna › Grupos › Sincronización de personas (14 oct 2026).
//
// La jerarquía que usa Interventoría para asignar es
//   empresa → grupo → establecimiento → cargo.
// Cada establecimiento está en un grupo (Admin) y cada persona trabaja en uno
// o varios establecimientos (Talento Humano). Aquí se cruzan los dos:
//   * La persona cuyo establecimiento ya tiene grupo recibe ese grupo
//     (`gruposInterventoria`). Solo se AGREGA: nunca se quita un grupo.
//   * La persona con un establecimiento sin grupo, o sin establecimiento, no se
//     toca: se lista para decidir a mano.
//   * El grupo que la persona tiene pero que ninguno de sus establecimientos
//     justifica se muestra como "de más", sin quitarlo.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../compras/compras_models.dart' show ComprasGrupoDoc;
import '../core/grupos_trabajo.dart';
import '../core/user_directory.dart';
import '../interventoria/interventoria_revision_maestro.dart'
    show CambioCobertura;
import '../utils/user_company.dart' show mergeCompanyScopedData;
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'admin_repository.dart' show CentroCostoItem;

enum EstadoGrupoPersona {
  /// Le falta algún grupo que sus establecimientos ya tienen.
  porSincronizar,

  /// Algún establecimiento suyo no tiene grupo (puede o no faltarle otro).
  centroSinGrupo,

  /// No tiene establecimiento: cargos corporativos o ficha incompleta.
  sinEstablecimiento,

  /// Sus grupos coinciden con los de sus establecimientos.
  enOrden,
}

class FilaGrupoPersona {
  final String id;
  final String nombre;
  final String cargo;

  /// Establecimientos de la persona (ids).
  final Set<String> centros;

  /// Grupos que tiene hoy (claves `G6`).
  final Set<String> gruposActuales;

  /// Grupos que le faltan según sus establecimientos.
  final Set<String> agregar;

  /// Nombres de sus establecimientos que no están en ningún grupo.
  final List<String> centrosSinGrupo;

  /// Grupos que tiene y ninguno de sus establecimientos justifica.
  final Set<String> deMas;

  const FilaGrupoPersona({
    required this.id,
    required this.nombre,
    required this.cargo,
    required this.centros,
    required this.gruposActuales,
    required this.agregar,
    required this.centrosSinGrupo,
    required this.deMas,
  });

  EstadoGrupoPersona get estado {
    if (centros.isEmpty) return EstadoGrupoPersona.sinEstablecimiento;
    if (agregar.isNotEmpty) return EstadoGrupoPersona.porSincronizar;
    if (centrosSinGrupo.isNotEmpty) return EstadoGrupoPersona.centroSinGrupo;
    return EstadoGrupoPersona.enOrden;
  }
}

/// Cruza personas, establecimientos y grupos de UNA empresa. Función pura:
/// la misma lista sirve a Web y móvil y se prueba sin Firestore.
List<FilaGrupoPersona> calcularSincronizacionGrupos({
  required String empresaId,
  required List<ComprasGrupoDoc> grupos,
  required List<CentroCostoItem> centros,
  required Iterable<({String id, Map<String, dynamic> data})> personas,
}) {
  String texto(Object? v) => (v ?? '').toString().trim();
  Set<String> lista(Object? raw) => raw is Iterable && raw is! String
      ? raw.map(texto).where((v) => v.isNotEmpty).toSet()
      : <String>{};

  final grupoDeCentro = <String, String>{};
  for (final g in grupos) {
    if (!g.activo) continue;
    final clave = claveGrupoTrabajo(g.nombre);
    if (clave.isEmpty) continue;
    for (final c in g.centroIds) {
      grupoDeCentro.putIfAbsent(c.trim(), () => clave);
    }
  }
  final nombreCentro = {for (final c in centros) c.centroId: c.nombre};

  final filas = <FilaGrupoPersona>[];
  for (final p in personas) {
    final d = mergeCompanyScopedData(p.data, empresaId);
    final ids = <String>{
      texto(d['centroId']),
      texto(d['centroOperacionId']),
      texto(d['centroTrabajoId']),
      ...lista(d['centrosOperacionIds']),
      ...lista(d['centrosTrabajoIds']),
    }..remove('');
    ids.remove('global');
    final actuales = gruposDePersonaFicha(d['gruposInterventoria']);
    final esperados = <String>{};
    final sinGrupo = <String>[];
    for (final c in ids) {
      final g = grupoDeCentro[c];
      if (g == null) {
        sinGrupo.add(nombreCentro[c] ?? c);
      } else {
        esperados.add(g);
      }
    }
    sinGrupo.sort();
    final nombre = UserDirectory.instance
        .fromUsuario(p.id, p.data)
        .displayName
        .trim();
    filas.add(
      FilaGrupoPersona(
        id: p.id,
        nombre: nombre.isEmpty ? p.id : nombre,
        cargo: texto(d['cargo'] ?? d['cargoNombre']),
        centros: ids,
        gruposActuales: actuales,
        agregar: esperados.difference(actuales),
        centrosSinGrupo: sinGrupo,
        // Sin establecimientos no hay con qué compararlos: no se marca "de más".
        deMas: ids.isEmpty ? <String>{} : actuales.difference(esperados),
      ),
    );
  }
  filas.sort(
    (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
  );
  return filas;
}

/// Cambios a escribir: solo quien tiene grupos por agregar.
List<CambioCobertura> cambiosDeSincronizacion(
  Iterable<FilaGrupoPersona> filas,
) => [
  for (final f in filas)
    if (f.agregar.isNotEmpty)
      CambioCobertura(userId: f.id, nombre: f.nombre, agregarGrupos: f.agregar),
];

/// Tablero de sincronización dentro del panel de Grupos.
class GruposSincronizacionSeccion extends StatefulWidget {
  final String empresaId;
  final List<ComprasGrupoDoc> grupos;
  final List<CentroCostoItem> centros;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> usuarios;

  /// Escribe los grupos que faltan. Devuelve cuando terminó.
  final Future<void> Function(List<CambioCobertura> cambios) sincronizar;

  const GruposSincronizacionSeccion({
    super.key,
    required this.empresaId,
    required this.grupos,
    required this.centros,
    required this.usuarios,
    required this.sincronizar,
  });

  @override
  State<GruposSincronizacionSeccion> createState() =>
      _GruposSincronizacionSeccionState();
}

class _GruposSincronizacionSeccionState
    extends State<GruposSincronizacionSeccion> {
  bool _trabajando = false;
  EstadoGrupoPersona? _ver;

  List<FilaGrupoPersona> get _filas => calcularSincronizacionGrupos(
    empresaId: widget.empresaId,
    grupos: widget.grupos,
    centros: widget.centros,
    personas: [for (final u in widget.usuarios) (id: u.id, data: u.data())],
  );

  Future<void> _sincronizar(List<FilaGrupoPersona> filas) async {
    final cambios = cambiosDeSincronizacion(filas);
    if (cambios.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sincronizar grupos'),
        content: Text(
          'Se agregará a ${cambios.length} '
          '${cambios.length == 1 ? 'persona' : 'personas'} el grupo de sus '
          'establecimientos. No se quita ningún grupo ni se tocan las tareas '
          'ya creadas; para moverlas usa "Reasignar por grupos" en '
          'Interventoría.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _trabajando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.sincronizar(cambios);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${cambios.length} '
            '${cambios.length == 1 ? 'persona sincronizada' : 'personas sincronizadas'}.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB91C1C),
          content: Text('No se pudo sincronizar: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filas = _filas;
    int cuenta(EstadoGrupoPersona e) =>
        filas.where((f) => f.estado == e).length;
    final porSync = cuenta(EstadoGrupoPersona.porSincronizar);
    final deMas = filas.where((f) => f.deMas.isNotEmpty).length;
    final visibles = _ver == null
        ? const <FilaGrupoPersona>[]
        : filas.where((f) => f.estado == _ver).toList();

    Widget chip(EstadoGrupoPersona e, String texto, Color color) {
      final n = cuenta(e);
      return ChoiceChip(
        selected: _ver == e,
        label: Text('$texto: $n'),
        selectedColor: color.withValues(alpha: 0.18),
        onSelected: (v) => setState(() => _ver = v ? e : null),
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sincronización de personas',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              'Empresa → grupo → establecimiento → cargo. A quien trabaja en un '
              'establecimiento que ya tiene grupo se le agrega ese grupo. '
              'Quien tiene un establecimiento sin grupo, o ninguno, se lista '
              'para decidirlo a mano en Talento Humano. Nunca se quita un grupo.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                chip(
                  EstadoGrupoPersona.porSincronizar,
                  'Por sincronizar',
                  const Color(0xFF3B82F6),
                ),
                chip(
                  EstadoGrupoPersona.centroSinGrupo,
                  'Establecimiento sin grupo',
                  const Color(0xFFB45309),
                ),
                chip(
                  EstadoGrupoPersona.sinEstablecimiento,
                  'Sin establecimiento',
                  const Color(0xFF64748B),
                ),
                chip(
                  EstadoGrupoPersona.enOrden,
                  'En orden',
                  const Color(0xFF16A34A),
                ),
              ],
            ),
            if (deMas > 0) ...[
              const SizedBox(height: 6),
              Text(
                '$deMas ${deMas == 1 ? 'persona tiene' : 'personas tienen'} un '
                'grupo que ninguno de sus establecimientos justifica '
                '(se indica en su fila; no se quita).',
                style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: porSync == 0 || _trabajando
                    ? null
                    : () => _sincronizar(filas),
                icon: _trabajando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(
                  _trabajando
                      ? 'Sincronizando…'
                      : 'Sincronizar grupos ($porSync)',
                ),
              ),
            ),
            if (_ver != null) ...[
              const Divider(height: 20),
              if (visibles.isEmpty)
                const Text('Nadie en esta lista.')
              else
                PagedListSection<FilaGrupoPersona>(
                  items: visibles,
                  etiqueta: 'personas',
                  itemBuilder: (context, f, _) => _fila(f),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fila(FilaGrupoPersona f) {
    String grupos(Set<String> s) =>
        (s.toList()..sort()).map(etiquetaGrupoTrabajo).join(', ');
    final detalle = <String>[
      if (f.cargo.isNotEmpty) f.cargo,
      f.gruposActuales.isEmpty
          ? 'sin grupo'
          : 'grupos: ${grupos(f.gruposActuales)}',
      if (f.agregar.isNotEmpty) 'recibirá: ${grupos(f.agregar)}',
      if (f.centrosSinGrupo.isNotEmpty)
        'sin grupo: ${f.centrosSinGrupo.join(', ')}',
      if (f.deMas.isNotEmpty) 'de más: ${grupos(f.deMas)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(userId: f.id, nameHint: f.nombre, radius: 13),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  detalle.join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
