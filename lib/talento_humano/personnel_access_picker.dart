// lib/talento_humano/personnel_access_picker.dart
//
// Selector de módulos en lenguaje de Talento Humano: "¿qué va a usar esta
// persona?" en vez de una matriz de appIds.
//
// Es un control gobernado (recibe `seleccion` y avisa por `onChanged`), para
// poder incrustarlo tanto en el alta de personal como en la contratación y en
// la pantalla de accesos, sin que cada pantalla reimplemente la lista.

import 'package:flutter/material.dart';

import '../core/app_catalog.dart';
import '../utils/user_company.dart';

const String _kFont = 'Arial';

class PersonnelAccessPicker extends StatelessWidget {
  /// Módulos que la persona tendrá (IDs canónicos).
  final Set<String> seleccion;

  /// Catálogo disponible para esta empresa (ya filtrado por TBL_APPS).
  final List<AppCatalogEntry> modulos;

  final ValueChanged<Set<String>> onChanged;

  /// Módulos que la persona ya tiene y Talento Humano no administra
  /// (Administración, Tokens DIAN). Se muestran como informativos.
  final Set<String> gestionadosPorAdmin;

  /// Compacta la presentación para formularios ya cargados de campos.
  final bool densa;

  const PersonnelAccessPicker({
    super.key,
    required this.seleccion,
    required this.modulos,
    required this.onChanged,
    this.gestionadosPorAdmin = const <String>{},
    this.densa = false,
  });

  bool _tiene(String appId) =>
      seleccion.any((app) => appIdsEquivalent(app, appId));

  void _alternar(String appId, bool valor) {
    final next = {...seleccion}
      ..removeWhere((app) => appIdsEquivalent(app, appId));
    if (valor) next.add(appId);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final grupos = <AppCatalogGroup, List<AppCatalogEntry>>{};
    for (final entry in modulos) {
      grupos.putIfAbsent(entry.grupo, () => []).add(entry);
    }
    final seleccionados = modulos.where((m) => _tiene(m.appId)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _AlwaysOnCard(densa: densa),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '¿Qué más va a usar en la app?',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              seleccionados == 0
                  ? 'Ninguno'
                  : '$seleccionados de ${modulos.length}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Marque solo lo que la persona necesita para su trabajo. '
          'Puede cambiarlo después en Accesos del personal.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: seleccionados == modulos.length
                  ? null
                  : () => onChanged(modulos.map((m) => m.appId).toSet()),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Marcar todos'),
            ),
            TextButton.icon(
              onPressed: seleccionados == 0
                  ? null
                  : () => onChanged(<String>{}),
              icon: const Icon(Icons.remove_done_rounded, size: 18),
              label: const Text('Quitar todos'),
            ),
          ],
        ),
        for (final grupo in AppCatalogGroup.values)
          if ((grupos[grupo] ?? const []).isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(
                grupo.label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            ...grupos[grupo]!.map(
              (entry) => _ModuloTile(
                entry: entry,
                valor: _tiene(entry.appId),
                densa: densa,
                onChanged: (v) => _alternar(entry.appId, v),
              ),
            ),
          ],
        if (gestionadosPorAdmin.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AdminOnlyCard(appIds: gestionadosPorAdmin),
        ],
      ],
    );
  }
}

class _ModuloTile extends StatelessWidget {
  final AppCatalogEntry entry;
  final bool valor;
  final bool densa;
  final ValueChanged<bool> onChanged;

  const _ModuloTile({
    required this.entry,
    required this.valor,
    required this.densa,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nota = entry.notaRolInterno;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: valor ? entry.color.withValues(alpha: 0.06) : null,
        border: Border.all(
          color: valor
              ? entry.color.withValues(alpha: 0.45)
              : scheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CheckboxListTile(
        value: valor,
        onChanged: (v) => onChanged(v ?? false),
        dense: densa,
        controlAffinity: ListTileControlAffinity.leading,
        secondary: CircleAvatar(
          radius: densa ? 15 : 18,
          backgroundColor: entry.color.withValues(alpha: 0.12),
          child: Icon(entry.icono, size: densa ? 16 : 19, color: entry.color),
        ),
        title: Text(
          entry.nombre,
          style: theme.textTheme.titleSmall?.copyWith(
            fontFamily: _kFont,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.paraQueSirve,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (valor && nota.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        nota,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
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

class _AlwaysOnCard extends StatelessWidget {
  final bool densa;

  const _AlwaysOnCard({required this.densa});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.all(densa ? 10 : 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Todo el personal recibe esto',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final servicio in kAlwaysOnServices)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    servicio.icono,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${servicio.nombre}: ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: servicio.paraQueSirve,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'No se pueden quitar y no dependen de los módulos marcados abajo.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOnlyCard extends StatelessWidget {
  final Set<String> appIds;

  const _AdminOnlyCard({required this.appIds});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nombres =
        appIds.map((id) => appCatalogEntryFor(id)?.nombre ?? id).toList()
          ..sort();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 17,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Esta persona además tiene ${nombres.join(', ')}. '
              'Ese acceso lo administra Admin y se conserva tal como está.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
