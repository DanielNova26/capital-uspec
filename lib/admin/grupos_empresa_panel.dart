// lib/admin/grupos_empresa_panel.dart
//
// Admin › Gestión interna › Grupos: los grupos de la EMPRESA (Grupo 1,
// Grupo 9…), los mismos de Compras. A cada grupo se le agregan los
// establecimientos que lo forman; cada establecimiento va en un solo grupo.
//
// Quién los usa:
//   * Talento Humano: asigna a cada persona los grupos a los que pertenece
//     (puede ser más de uno).
//   * Interventoría: al asignar un hallazgo da prioridad a quien trabaja en el
//     grupo donde está el establecimiento, y permite filtrar por grupo.
//
// No son los grupos de Visitas: esos se arman dentro de Visitas, por
// departamento y con sus profesionales y coordinadores.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../compras/compras_models.dart' show ComprasGrupoDoc;
import '../core/area_directory.dart';
import '../core/grupos_trabajo.dart';
import '../core/user_directory.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import '../utils/user_company.dart' show mergeCompanyScopedData;
import 'admin_repository.dart';
import 'grupo_empresa_dialog.dart';

const String _kFont = 'Arial';
const Color _kAccent = Color(0xFF3B82F6);
const Color _kMuted = Color(0xFF64748B);
const Color _kRojo = Color(0xFFDC2626);

class AdminGruposEmpresaPanel extends StatelessWidget {
  final List<ComprasGrupoDoc> grupos;
  final List<CentroCostoItem> centros;

  /// Personal habilitado de la empresa, para mostrar quién está en cada grupo.
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> usuarios;
  final String empresaId;

  /// Crea o actualiza el grupo y sus establecimientos. Devuelve cuando ya se
  /// guardó.
  final Future<void> Function({
    String? id,
    required String nombre,
    required bool activo,
    required List<String> centroIds,
  })
  guardar;

  const AdminGruposEmpresaPanel({
    super.key,
    required this.grupos,
    required this.centros,
    required this.usuarios,
    required this.empresaId,
    required this.guardar,
  });

  Future<void> _editar(BuildContext context, ComprasGrupoDoc? g) async {
    final otros = <String, String>{
      for (final o in grupos)
        if (o.id != g?.id)
          for (final c in o.centroIds) c: o.nombre,
    };
    final r = await showDialog<GrupoEmpresaEditado>(
      context: context,
      builder: (_) => GrupoEmpresaDialog(
        nombreInicial: g?.nombre ?? '',
        // Renombrar un grupo existente cambiaría la clave con la que Talento
        // Humano asignó a las personas: el nombre solo se fija al crearlo.
        nombreEditable: g == null,
        centrosIniciales: {...?g?.centroIds},
        centros: centros,
        enOtroGrupo: otros,
      ),
    );
    if (r == null || !context.mounted) return;
    final repetido = grupos.any(
      (o) =>
          o.id != g?.id &&
          claveGrupoTrabajo(o.nombre) == claveGrupoTrabajo(r.nombre),
    );
    if (repetido) {
      _aviso(context, 'Ya existe un grupo con ese nombre.', error: true);
      return;
    }
    try {
      await guardar(
        id: g?.id,
        nombre: r.nombre,
        activo: g?.activo ?? true,
        centroIds: r.centroIds.toList(),
      );
      if (context.mounted) _aviso(context, 'Grupo guardado.');
    } catch (e) {
      if (context.mounted) {
        _aviso(context, 'No se pudo guardar: $e', error: true);
      }
    }
  }

  void _aviso(BuildContext context, String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
      ),
    );
  }

  /// Personas de la empresa que tienen este grupo asignado en Talento Humano.
  List<({String id, String nombre})> _personas(ComprasGrupoDoc g) {
    final clave = claveGrupoTrabajo(g.nombre);
    final out = <({String id, String nombre})>[];
    for (final u in usuarios) {
      final data = u.data();
      final raw = mergeCompanyScopedData(
        data,
        empresaId,
      )['gruposInterventoria'];
      if (gruposDePersonaFicha(raw).contains(clave)) {
        final nombre = UserDirectory.instance
            .fromUsuario(u.id, data)
            .displayName
            .trim();
        out.add((id: u.id, nombre: nombre.isEmpty ? u.id : nombre));
      }
    }
    out.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final nombreCentro = {for (final c in centros) c.centroId: c.nombre};
    final conGrupo = {for (final g in grupos) ...g.centroIds};
    final sinGrupo = [
      for (final c in centros)
        if (c.enabled && !conGrupo.contains(c.centroId)) c.nombre,
    ]..sort();
    int numero(String n) =>
        int.tryParse(n.replaceAll(RegExp(r'\D'), '')) ?? 1 << 30;
    final ordenados = [...grupos]
      ..sort((a, b) {
        final c = numero(a.nombre).compareTo(numero(b.nombre));
        return c != 0 ? c : a.nombre.compareTo(b.nombre);
      });
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Grupos de la empresa',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
              onPressed: () => _editar(context, null),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Nuevo grupo'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Son los grupos de la empresa (Grupo 1, Grupo 9…), los mismos de '
          'Compras. Agrega a cada uno sus establecimientos; las personas se '
          'asignan en Talento Humano y pueden estar en varios grupos. '
          'Interventoría asigna primero a quien trabaja en el grupo del '
          'establecimiento. No son los grupos de Visitas.',
          style: TextStyle(fontSize: 12, color: _kMuted),
        ),
        if (sinGrupo.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${sinGrupo.length} establecimiento'
              '${sinGrupo.length == 1 ? '' : 's'} sin grupo: '
              '${sinGrupo.take(8).join(', ')}${sinGrupo.length > 8 ? '…' : ''}.',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (ordenados.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No hay grupos. Crea uno con "Nuevo grupo".',
              style: TextStyle(color: _kMuted),
            ),
          )
        else
          PagedListSection<ComprasGrupoDoc>(
            items: ordenados,
            etiqueta: 'grupos',
            itemBuilder: (context, g, _) => _tarjeta(context, g, nombreCentro),
          ),
      ],
    );
  }

  Widget _tarjeta(
    BuildContext context,
    ComprasGrupoDoc g,
    Map<String, String> nombreCentro,
  ) {
    final personas = _personas(g);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    g.nombre,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Tooltip(
                  message: g.activo ? 'Activo en Compras' : 'Inactivo',
                  child: Switch(
                    value: g.activo,
                    onChanged: (v) => guardar(
                      id: g.id,
                      nombre: g.nombre,
                      activo: v,
                      centroIds: g.centroIds,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Editar establecimientos',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editar(context, g),
                ),
              ],
            ),
            Text(
              g.centroIds.isEmpty
                  ? 'Sin establecimientos: edítalo para agregarlos'
                  : '${g.centroIds.length} establecimiento'
                        '${g.centroIds.length == 1 ? '' : 's'}: '
                        '${g.centroIds.map((c) => nombreCentro[c] ?? 'Establecimiento retirado').join(', ')}',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: g.centroIds.isEmpty ? _kRojo : Colors.black87,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: personas.isEmpty
                  ? const Text(
                      'Sin personas: asígnales el grupo en Talento Humano',
                      style: TextStyle(fontSize: 12, color: _kMuted),
                    )
                  : Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Personas:',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        for (final p in personas)
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              UserAvatar(
                                userId: p.id,
                                nameHint: p.nombre,
                                radius: 11,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                p.nombre,
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12,
                                ),
                              ),
                            ],
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
