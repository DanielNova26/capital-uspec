// lib/admin/grupo_empresa_dialog.dart
//
// Editor de un grupo de la empresa (Grupo 1, Grupo 9…): nombre y los
// establecimientos que lo forman. Es el grupo que usan Compras, Talento
// Humano e Interventoría; no es el grupo de Visitas (ese se arma dentro de
// Visitas, por departamento y con sus profesionales).

import 'package:flutter/material.dart';

import '../core/area_directory.dart';
import 'admin_repository.dart';

const Color _kAccent = Color(0xFF3B82F6);
const Color _kRojo = Color(0xFFDC2626);

typedef GrupoEmpresaEditado = ({String nombre, Set<String> centroIds});

class GrupoEmpresaDialog extends StatefulWidget {
  final String nombreInicial;
  final bool nombreEditable;
  final Set<String> centrosIniciales;
  final List<CentroCostoItem> centros;

  /// centroId → nombre del grupo que hoy lo tiene (los demás grupos).
  final Map<String, String> enOtroGrupo;

  const GrupoEmpresaDialog({
    super.key,
    required this.nombreInicial,
    required this.nombreEditable,
    required this.centrosIniciales,
    required this.centros,
    required this.enOtroGrupo,
  });

  @override
  State<GrupoEmpresaDialog> createState() => _GrupoEmpresaDialogState();
}

class _GrupoEmpresaDialogState extends State<GrupoEmpresaDialog> {
  late final TextEditingController _nombre;
  late Set<String> _centros;
  String _buscar = '';

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.nombreInicial);
    _centros = {...widget.centrosIniciales};
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  List<CentroCostoItem> get _visibles {
    final q = areaClave(_buscar);
    return [
      for (final c in widget.centros)
        if (c.enabled && (q.isEmpty || areaClave(c.nombre).contains(q))) c,
    ]..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  }

  /// "Los demás": los establecimientos que ningún otro grupo tiene.
  void _incluirLosDemas() => setState(() {
    for (final c in widget.centros) {
      if (c.enabled && !widget.enOtroGrupo.containsKey(c.centroId)) {
        _centros.add(c.centroId);
      }
    }
  });

  @override
  Widget build(BuildContext context) {
    final faltaNombre = _nombre.text.trim().isEmpty;
    final visibles = _visibles;
    return AlertDialog(
      title: Text(
        widget.nombreInicial.isEmpty ? 'Nuevo grupo' : 'Editar grupo',
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nombre,
              enabled: widget.nombreEditable,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nombre del grupo',
                hintText: 'Ej. Grupo 6',
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: faltaNombre ? _kRojo : Colors.black87,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Establecimientos (${_centros.length})',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Buscar establecimiento',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _buscar = v),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _centros.isEmpty ? _kRojo : Colors.black26,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: visibles.isEmpty
                    ? const Center(
                        child: Text('Ningún establecimiento coincide.'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final c in visibles)
                            CheckboxListTile(
                              dense: true,
                              value: _centros.contains(c.centroId),
                              title: Text(c.nombre),
                              subtitle:
                                  widget.enOtroGrupo.containsKey(c.centroId) &&
                                      !_centros.contains(c.centroId)
                                  ? Text(
                                      'Hoy en ${widget.enOtroGrupo[c.centroId]}: '
                                      'pasa a este grupo al guardar',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFFB45309),
                                      ),
                                    )
                                  : c.subcentros.isEmpty
                                  ? null
                                  : Text(
                                      'Incluye ${c.subcentros.length} '
                                      'subcentro${c.subcentros.length == 1 ? '' : 's'}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                              onChanged: (v) => setState(
                                () => v == true
                                    ? _centros.add(c.centroId)
                                    : _centros.remove(c.centroId),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _incluirLosDemas,
                icon: const Icon(Icons.playlist_add_check, size: 18),
                label: const Text(
                  'Incluir los demás (los que no están en otro grupo)',
                ),
              ),
            ),
            const Text(
              'Un establecimiento va en un solo grupo. Los subcentros siguen '
              'a su establecimiento.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kAccent),
          onPressed: faltaNombre
              ? null
              : () => Navigator.pop<GrupoEmpresaEditado>(context, (
                  nombre: _nombre.text.trim(),
                  centroIds: _centros,
                )),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
