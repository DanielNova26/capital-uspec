// lib/rutas/rutas_dashboard_screen.dart
//
// Punto de entrada del módulo Rutas. Enruta por ROL (y plataforma):
//   - admin / desarrollador → consola web (rutas, configuración, ...)
//   - calidad              → revisión web (Fase 4)
//   - conductor            → captura móvil (Fase 3)
//
// Convención del proyecto: todas las pantallas del módulo viven en este archivo.

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/session_audit_service.dart';
import '../widgets/user_avatar.dart';
import 'movilidad/movilidad_screen.dart';
import 'rutas_conductor_screen.dart';
import 'rutas_directions_bridge.dart';
import 'rutas_excel_parser.dart';
import 'rutas_logic.dart';
import 'rutas_models.dart';
import 'rutas_service.dart';
import '../widgets/paged_list.dart';

const Color kRutasColor = Color(0xFF15803D); // verde logística
const double _kCentroOperacionesLat = kRutaOrigenLatDefault;
const double _kCentroOperacionesLng = kRutaOrigenLngDefault;

Color _colorComida(String comida) {
  switch (comida) {
    case kComidaDesayuno:
      return const Color(0xFF16A34A);
    case kComidaAlmuerzo:
      return const Color(0xFFF59E0B);
    case kComidaCena:
      return const Color(0xFF2563EB);
    default:
      return kRutasColor;
  }
}

String _normalizarTexto(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u')
    .replaceAll('ñ', 'n');

class RutasDashboardScreen extends StatelessWidget {
  final String userId;
  final String empresaId;
  final String? rolRutas;
  final bool desarrolladorOverride;

  const RutasDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.rolRutas,
    this.desarrolladorOverride = false,
  });

  @override
  Widget build(BuildContext context) {
    final rol = (rolRutas ?? '').trim().toLowerCase();

    if (desarrolladorOverride ||
        rol == kRutasRolDesarrollador ||
        rol == 'developer') {
      return _RutasDeveloperHome(userId: userId, empresaId: empresaId);
    }
    if (rol == kRutasRolAdmin) {
      return _RutasAdminHome(userId: userId, empresaId: empresaId);
    }
    if (rol == kRutasRolAdminCalidad) {
      return _RutasAdminCalidadHome(userId: userId, empresaId: empresaId);
    }
    if (rol == kRutasRolCalidad) {
      return _CalidadHome(userId: userId, empresaId: empresaId);
    }
    if (rol == kRutasRolConductor) {
      // Conductores: SOLO móvil (cámara + GPS). En web se les invita a usar la app.
      if (kIsWeb) {
        return _EnConstruccion(
          titulo: 'Usa la app móvil',
          detalle:
              'La toma de evidencia es únicamente desde la app móvil (necesita '
              'cámara y ubicación). Ingresa desde tu celular.',
        );
      }
      return ConductorHomeScreen(userId: userId, empresaId: empresaId);
    }
    return _EnConstruccion(
      titulo: 'Rutas',
      detalle: 'Tu usuario no tiene un rol asignado en el módulo Rutas.',
    );
  }
}

class _RutasAdminCalidadHome extends StatelessWidget {
  final String userId;
  final String empresaId;

  const _RutasAdminCalidadHome({required this.userId, required this.empresaId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kRutasColor,
        foregroundColor: Colors.white,
        title: const Text('Rutas — Administración y Calidad'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          return GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: isWide ? 2 : 1,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: isWide ? 2.4 : 3.2,
            children: [
              _PerfilAccesoCard(
                title: 'Administración',
                subtitle:
                    'Establecimientos, rutas, asignaciones, centro de control y configuración inicial.',
                icon: Icons.admin_panel_settings,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        _RutasAdminHome(userId: userId, empresaId: empresaId),
                  ),
                ),
              ),
              _PerfilAccesoCard(
                title: 'Calidad',
                subtitle:
                    'Revisión de evidencias, aprobación, rechazo, informes y consulta histórica.',
                icon: Icons.verified,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        _CalidadHome(userId: userId, empresaId: empresaId),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PerfilAccesoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _PerfilAccesoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: kRutasColor.withOpacity(0.15),
                foregroundColor: kRutasColor,
                child: Icon(icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _RutasDeveloperHome extends StatelessWidget {
  final String userId;
  final String empresaId;

  const _RutasDeveloperHome({required this.userId, required this.empresaId});

  @override
  Widget build(BuildContext context) {
    final profiles = [
      (
        title: 'Administrador',
        subtitle: 'Rutas, asignaciones y configuración',
        icon: Icons.admin_panel_settings,
        onTap: () => _open(
          context,
          _RutasAdminHome(
            userId: userId,
            empresaId: empresaId,
            modoDesarrollador: true,
          ),
        ),
      ),
      (
        title: 'Calidad',
        subtitle: 'Revisar, aprobar, rechazar o eliminar evidencias',
        icon: Icons.verified,
        onTap: () => _open(
          context,
          _CalidadHome(
            userId: userId,
            empresaId: empresaId,
            puedeEliminar: true,
          ),
        ),
      ),
      (
        title: 'Conductor',
        subtitle: 'Tomar evidencia y borrar tus fotos de prueba',
        icon: Icons.local_shipping,
        onTap: () => _open(
          context,
          ConductorHomeScreen(userId: userId, empresaId: empresaId),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kRutasColor,
        foregroundColor: Colors.white,
        title: const Text('Rutas — Desarrollador'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: kRutasColor.withOpacity(0.08),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Modo de pruebas: puedes entrar a los tres perfiles del módulo sin cambiar tu rol de usuario.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 800;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isWide ? 3 : 1,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: isWide ? 1.45 : 3.2,
                ),
                itemCount: profiles.length,
                itemBuilder: (_, i) {
                  final profile = profiles[i];
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: profile.onTap,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: kRutasColor.withOpacity(0.15),
                              foregroundColor: kRutasColor,
                              child: Icon(profile.icon),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    profile.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    profile.subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Herramientas de prueba',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Limpia fotos, revisiones y resúmenes diarios del módulo Rutas para repetir pruebas completas.',
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      foregroundColor: Colors.red.shade800,
                    ),
                    onPressed: () => _limpiarHistorial(context),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Borrar historial'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _limpiarHistorial(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar historial de rutas'),
        content: const Text(
          'Se eliminarán las evidencias, fotos en Storage y resúmenes diarios de esta empresa. Las rutas y asignaciones se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Borrando historial de pruebas...')),
    );
    try {
      final result = await RutasService().limpiarHistorialEvidenciasEmpresa(
        empresaId,
      );
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Historial limpio: ${result.evidencias} evidencias y ${result.resumenes} resúmenes.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Error al borrar: $e')));
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CONSOLA ADMIN (web): pestañas Rutas + Configuración
// ══════════════════════════════════════════════════════════════════════════════

class _RutasAdminHome extends StatelessWidget {
  final String userId;
  final String empresaId;
  final bool modoDesarrollador;

  const _RutasAdminHome({
    required this.userId,
    required this.empresaId,
    this.modoDesarrollador = false,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: kRutasColor,
          foregroundColor: Colors.white,
          title: const Text('Rutas — Administración'),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.place_outlined), text: 'Establecimientos'),
              Tab(icon: Icon(Icons.alt_route), text: 'Rutas'),
              Tab(icon: Icon(Icons.assignment_ind), text: 'Asignaciones'),
              Tab(icon: Icon(Icons.login_rounded), text: 'Uso app'),
              Tab(icon: Icon(Icons.map_outlined), text: 'Centro control'),
              Tab(icon: Icon(Icons.speed), text: 'Estudio movilidad'),
              Tab(icon: Icon(Icons.tune), text: 'Configuración inicial'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _EstablecimientosTab(empresaId: empresaId),
            _RutasListTab(empresaId: empresaId),
            _AsignacionesTab(
              empresaId: empresaId,
              adminUserId: userId,
              modoDesarrollador: modoDesarrollador,
            ),
            _UsoAppRutasTab(empresaId: empresaId),
            _CentroControlTab(empresaId: empresaId),
            MovilidadEstudioTab(empresaId: empresaId, userId: userId),
            _ConfigTab(empresaId: empresaId),
          ],
        ),
      ),
    );
  }
}

// ─── Pestaña: maestro de establecimientos ───────────────────────────────────

class _EstablecimientosTab extends StatefulWidget {
  final String empresaId;

  const _EstablecimientosTab({required this.empresaId});

  @override
  State<_EstablecimientosTab> createState() => _EstablecimientosTabState();
}

class _EstablecimientosTabState extends State<_EstablecimientosTab> {
  final _service = RutasService();
  final _parser = RutasExcelParser();
  bool _syncing = false;
  bool _importing = false;

  Future<void> _sincronizarExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _snack('No se pudo leer el archivo seleccionado.');
      return;
    }

    final parsed = _parser.parse(bytes);
    if (!parsed.exitoso) {
      _snack(parsed.error ?? 'El Excel no contiene establecimientos validos.');
      return;
    }
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sincronizar establecimientos'),
        content: Text(
          'Se crearan o actualizaran ${parsed.rutas.length} establecimientos '
          'en TBL_RUTAS_ESTABLECIMIENTOS. Las rutas se arman despues '
          'combinando estos destinos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kRutasColor),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.sync),
            label: const Text('Sincronizar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _syncing = true);
    try {
      final result = await _service.sincronizarEstablecimientosDesdeExcel(
        empresaId: widget.empresaId,
        filas: parsed.rutas,
        sourceName: file.name,
      );
      _snack(
        'Establecimientos sincronizados: ${result.total} (${result.created} nuevos, ${result.updated} actualizados).',
      );
    } catch (e) {
      _snack('No se pudo sincronizar establecimientos: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _importarDesdeRutas() async {
    var desactivarOriginales = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Importar desde rutas existentes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Se leeran los establecimientos ya guardados dentro de TBL_RUTAS '
                'y se copiaran al maestro TBL_RUTAS_ESTABLECIMIENTOS.',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: desactivarOriginales,
                onChanged: (v) =>
                    setLocal(() => desactivarOriginales = v ?? true),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Ocultar rutas antiguas de un solo establecimiento',
                ),
                subtitle: const Text(
                  'Recomendado: deja esos destinos solo en Establecimientos y limpia la pestaña Rutas.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kRutasColor),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.move_down_outlined),
              label: const Text('Importar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _importing = true);
    try {
      final result = await _service.sincronizarEstablecimientosDesdeRutas(
        widget.empresaId,
        desactivarRutasDeUnEstablecimiento: desactivarOriginales,
      );
      _snack(
        'Importados desde rutas: ${result.total} (${result.created} nuevos, ${result.updated} actualizados, ${result.rutasDesactivadas} rutas ocultas, ${result.asignacionesLiberadas} asignaciones liberadas).',
      );
    } catch (e) {
      _snack('No se pudo importar desde rutas: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kRutasColor,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _EstablecimientoEditorScreen(
              empresaId: widget.empresaId,
              establecimiento: null,
            ),
          ),
        ),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Nuevo establecimiento'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: (_syncing || _importing)
                        ? null
                        : _importarDesdeRutas,
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.move_down_outlined),
                    label: Text(
                      _importing
                          ? 'Importando...'
                          : 'Importar de rutas existentes',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: (_syncing || _importing)
                        ? null
                        : _sincronizarExcel,
                    icon: _syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(
                      _syncing ? 'Sincronizando...' : 'Sincronizar Excel',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<RutaEstablecimientoDoc>>(
              stream: _service.streamEstablecimientos(widget.empresaId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final establecimientos = snapshot.data!;
                if (establecimientos.isEmpty) {
                  return const _EmptyHint(
                    icon: Icons.place_outlined,
                    titulo: 'No hay establecimientos todavía',
                    detalle:
                        'Carga el Excel o importa los destinos desde rutas existentes.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: establecimientos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final e = establecimientos[i];
                    final distancia = e.distanciaCentroKm;
                    final rango = e.rangoDistancia.trim();
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: e.activo
                              ? kRutasColor.withOpacity(0.15)
                              : Colors.grey.shade200,
                          foregroundColor: e.activo ? kRutasColor : Colors.grey,
                          child: const Icon(Icons.place_outlined),
                        ),
                        title: Text(
                          e.nombre,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${e.direccionVisible.isEmpty ? 'Sin dirección' : e.direccionVisible}'
                          '${e.geocodificada ? ' · con ubicación' : ' · sin ubicación'}'
                          '${distancia == null ? '' : ' · ${distancia.toStringAsFixed(2)} km'}'
                          '${rango.isEmpty ? '' : ' · $rango'}'
                          '${e.activo ? '' : ' · INACTIVO'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _EstablecimientoEditorScreen(
                              empresaId: widget.empresaId,
                              establecimiento: e,
                            ),
                          ),
                        ),
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

// ─── Pestaña: rutas armadas desde establecimientos ───────────────────────────

class _RutasListTab extends StatefulWidget {
  final String empresaId;

  const _RutasListTab({required this.empresaId});

  @override
  State<_RutasListTab> createState() => _RutasListTabState();
}

class _RutasListTabState extends State<_RutasListTab> {
  final _service = RutasService();
  bool _combining = false;

  Future<void> _abrirCombinarRutas() async {
    final rutas = (await _service.getRutas(
      widget.empresaId,
    )).where((r) => r.activa && r.stops.isNotEmpty).toList();
    if (!mounted) return;
    if (rutas.length < 2) {
      _snack(
        'Necesitas al menos dos rutas activas con establecimientos para combinar.',
      );
      return;
    }

    final codigoCtrl = TextEditingController(text: 'Ruta combinada');
    final seleccionadas = <String>{};
    var desactivarOriginales = true;

    final result =
        await showDialog<
          ({String codigo, Set<String> ids, bool desactivarOriginales})
        >(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
              title: const Text('Combinar rutas'),
              content: SizedBox(
                width: math.min(MediaQuery.of(ctx).size.width * 0.92, 560.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: codigoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de la nueva ruta',
                          hintText: 'Ej: Ruta Centro + USME',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: desactivarOriginales,
                        onChanged: null,
                        title: const Text('Desactivar rutas originales'),
                        subtitle: const Text(
                          'Obligatorio para no duplicar establecimientos en rutas activas.',
                        ),
                      ),
                      const Divider(),
                      for (final ruta in rutas)
                        CheckboxListTile(
                          value: seleccionadas.contains(ruta.id),
                          onChanged: (v) {
                            setLocal(() {
                              if (v == true) {
                                seleccionadas.add(ruta.id);
                              } else {
                                seleccionadas.remove(ruta.id);
                              }
                            });
                          },
                          title: Text(ruta.codigo),
                          subtitle: Text(
                            '${ruta.stops.length} establecimientos',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kRutasColor),
                  onPressed: seleccionadas.length < 2
                      ? null
                      : () => Navigator.pop(ctx, (
                          codigo: codigoCtrl.text.trim(),
                          ids: Set<String>.from(seleccionadas),
                          desactivarOriginales: desactivarOriginales,
                        )),
                  icon: const Icon(Icons.call_merge),
                  label: const Text('Crear combinada'),
                ),
              ],
            ),
          ),
        );

    codigoCtrl.dispose();
    if (result == null) return;

    setState(() => _combining = true);
    try {
      final byId = {for (final r in rutas) r.id: r};
      final seleccion = [
        for (final id in result.ids)
          if (byId[id] != null) byId[id]!,
      ];
      await _service.combinarRutas(
        empresaId: widget.empresaId,
        codigo: result.codigo,
        rutas: seleccion,
        desactivarOriginales: result.desactivarOriginales,
      );
      _snack('Ruta combinada creada con ${seleccion.length} rutas.');
    } catch (e) {
      _snack('No se pudo combinar rutas: $e');
    } finally {
      if (mounted) setState(() => _combining = false);
    }
  }

  Future<void> _cambiarEstadoRuta(RutaDoc ruta, bool activa) async {
    final accion = activa ? 'habilitar' : 'deshabilitar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${activa ? 'Habilitar' : 'Deshabilitar'} ${ruta.codigo}'),
        content: Text(
          activa
              ? 'La ruta volverá a estar disponible para asignaciones.'
              : 'Se cerrará la asignación vigente de esta ruta, si existe, y quedará fuera de operación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(activa ? 'Habilitar' : 'Deshabilitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.cambiarEstadoRuta(ruta, activa);
      _snack('Ruta ${activa ? 'habilitada' : 'deshabilitada'}.');
    } catch (e) {
      _snack('No se pudo $accion la ruta: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kRutasColor,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                _RutaEditorScreen(empresaId: widget.empresaId, ruta: null),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nueva ruta'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _combining ? null : _abrirCombinarRutas,
                    icon: _combining
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.call_merge),
                    label: Text(
                      _combining ? 'Combinando...' : 'Combinar rutas',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<RutaDoc>>(
              stream: _service.streamRutas(widget.empresaId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rutas = snapshot.data!;
                if (rutas.isEmpty) {
                  return const _EmptyHint(
                    icon: Icons.alt_route,
                    titulo: 'No hay rutas todavía',
                    detalle:
                        'Crea una ruta combinando uno o varios establecimientos.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: rutas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final ruta = rutas[i];
                    final geocodificadas = ruta.stops
                        .where((s) => s.geocodificada)
                        .length;
                    final stop = ruta.stops.isEmpty ? null : ruta.stops.first;
                    final distancia = stop?.distanciaCentroKm;
                    final rango = stop?.rangoDistancia.trim() ?? '';
                    return Card(
                      color: ruta.activa ? null : Colors.grey.shade100,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: ruta.activa
                              ? kRutasColor.withOpacity(0.15)
                              : Colors.grey.shade300,
                          foregroundColor: ruta.activa
                              ? kRutasColor
                              : Colors.grey.shade700,
                          child: Text(
                            ruta.numero == 9999 ? 'R' : '${ruta.numero}',
                          ),
                        ),
                        title: Text(
                          ruta.codigo,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${ruta.stops.length} establecimientos · '
                          '$geocodificadas con ubicación'
                          '${distancia == null ? '' : ' · ${distancia.toStringAsFixed(2)} km'}'
                          '${rango.isEmpty ? '' : ' · $rango'}'
                          '${ruta.activa ? '' : ' · INACTIVA'}',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(
                              label: Text(ruta.activa ? 'Activa' : 'Inactiva'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: ruta.activa
                                  ? kRutasColor.withOpacity(0.12)
                                  : Colors.grey.shade300,
                              labelStyle: TextStyle(
                                color: ruta.activa
                                    ? kRutasColor
                                    : Colors.grey.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            IconButton(
                              tooltip: ruta.activa
                                  ? 'Deshabilitar ruta'
                                  : 'Habilitar ruta',
                              onPressed: () =>
                                  _cambiarEstadoRuta(ruta, !ruta.activa),
                              icon: Icon(
                                ruta.activa
                                    ? Icons.toggle_on
                                    : Icons.toggle_off,
                                color: ruta.activa
                                    ? kRutasColor
                                    : Colors.grey.shade600,
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _RutaEditorScreen(
                              empresaId: widget.empresaId,
                              ruta: ruta,
                            ),
                          ),
                        ),
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

// ─── Pestaña: centro de control / mapa ───────────────────────────────────────

class _CentroControlTab extends StatefulWidget {
  final String empresaId;

  const _CentroControlTab({required this.empresaId});

  @override
  State<_CentroControlTab> createState() => _CentroControlTabState();
}

class _CentroControlTabState extends State<_CentroControlTab> {
  final _service = RutasService();
  GoogleMapController? _mapController;
  RutaConfigDoc? _config;
  String? _rutaId;
  String _origenId = '__centro__';
  bool _traffic = true;
  bool _calculandoRuta = false;
  RutaDirectionsResult? _directions;
  String _directionsError = '';

  LatLng get _centroOperaciones => LatLng(
    _config?.origenLat ?? _kCentroOperacionesLat,
    _config?.origenLng ?? _kCentroOperacionesLng,
  );

  String get _centroOperacionesNombre {
    final value = _config?.origenNombre.trim() ?? '';
    return value.isEmpty ? kRutaOrigenNombreDefault : value;
  }

  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }

  Future<void> _cargarConfig() async {
    final config = await _service.getConfig(widget.empresaId);
    if (mounted) setState(() => _config = config);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RutaDoc>>(
      stream: _service.streamRutas(widget.empresaId),
      builder: (context, rutasSnap) {
        if (rutasSnap.hasError) {
          return Center(child: Text('Error: ${rutasSnap.error}'));
        }
        if (!rutasSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rutas = rutasSnap.data!
            .where((r) => r.activa && r.stops.any((s) => s.geocodificada))
            .toList();
        if (rutas.isEmpty) {
          return const _EmptyHint(
            icon: Icons.map_outlined,
            titulo: 'No hay rutas georreferenciadas',
            detalle:
                'Sincroniza el Excel o edita rutas con latitud y longitud para verlas en el mapa.',
          );
        }

        final selected = _selectedRuta(rutas);
        return StreamBuilder<List<RutaUbicacionDoc>>(
          stream: _service.streamUbicaciones(widget.empresaId),
          builder: (context, locSnap) {
            final ubicaciones = locSnap.data ?? const <RutaUbicacionDoc>[];
            return Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final map = _buildMap(rutas, selected, ubicaciones);
                  final panel = _buildPanel(rutas, selected, ubicaciones);
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(child: map),
                        const SizedBox(width: 12),
                        SizedBox(width: 380, child: panel),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      SizedBox(height: 360, child: map),
                      const SizedBox(height: 12),
                      Expanded(child: panel),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  RutaDoc? _selectedRuta(List<RutaDoc> rutas) {
    if (rutas.isEmpty) return null;
    final id = _rutaId;
    if (id != null) {
      for (final ruta in rutas) {
        if (ruta.id == id) return ruta;
      }
    }
    return rutas.first;
  }

  String _driverValue(RutaUbicacionDoc u) => 'driver:${u.id}';

  RutaUbicacionDoc? _selectedDriver(List<RutaUbicacionDoc> ubicaciones) {
    if (!_origenId.startsWith('driver:')) return null;
    for (final u in ubicaciones) {
      if (_driverValue(u) == _origenId) return u;
    }
    return null;
  }

  String _origenLabel(List<RutaUbicacionDoc> ubicaciones) {
    final driver = _selectedDriver(ubicaciones);
    if (driver == null) return _centroOperacionesNombre;
    return driver.conductorNombre.isEmpty
        ? driver.userId
        : driver.conductorNombre;
  }

  void _limpiarCalculo() {
    _directions = null;
    _directionsError = '';
  }

  Future<void> _enfocarConductor(
    RutaUbicacionDoc conductor,
    List<RutaDoc> rutas,
    List<RutaUbicacionDoc> ubicaciones,
  ) async {
    RutaDoc? rutaConductor;
    for (final ruta in rutas) {
      if (ruta.id == conductor.rutaId) {
        rutaConductor = ruta;
        break;
      }
    }

    setState(() {
      _origenId = _driverValue(conductor);
      if (rutaConductor != null) _rutaId = rutaConductor.id;
      _limpiarCalculo();
    });

    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(conductor.lat, conductor.lng),
          zoom: 15.5,
        ),
      ),
    );

    if (rutaConductor != null && mounted) {
      await _calcularEtaConTrafico(rutaConductor, ubicaciones);
    }
  }

  Widget _buildMap(
    List<RutaDoc> rutas,
    RutaDoc? selected,
    List<RutaUbicacionDoc> ubicaciones,
  ) {
    final markers = <Marker>{};
    final polylines = <Polyline>{};
    final rutasMapa = selected == null ? rutas : [selected];

    LatLng center = _centroOperaciones;
    markers.add(
      Marker(
        markerId: const MarkerId('origen_operativo'),
        position: _centroOperaciones,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: _centroOperacionesNombre,
          snippet: _config?.origenDireccion ?? '',
        ),
      ),
    );
    for (final ruta in rutasMapa) {
      final points = <LatLng>[];
      for (var i = 0; i < ruta.stops.length; i++) {
        final stop = ruta.stops[i];
        if (!stop.geocodificada) continue;
        final pos = LatLng(stop.lat!, stop.lng!);
        center = pos;
        points.add(pos);
        markers.add(
          Marker(
            markerId: MarkerId('stop_${ruta.id}_$i'),
            position: pos,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(
              title: ruta.codigo,
              snippet: '${i + 1}. ${stop.nombre}',
            ),
          ),
        );
      }
      if (points.length > 1) {
        polylines.add(
          Polyline(
            polylineId: PolylineId('ruta_${ruta.id}'),
            points: points,
            color: kRutasColor,
            width: 5,
          ),
        );
      }
    }

    final directions = _directions;
    if (directions != null && directions.ok && directions.points.length > 1) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('ruta_calculada_maps'),
          points: directions.points.map((p) => LatLng(p.lat, p.lng)).toList(),
          color: Colors.blueAccent,
          width: 7,
        ),
      );
    }

    for (final u in ubicaciones) {
      final isSelectedDriver = _driverValue(u) == _origenId;
      markers.add(
        Marker(
          markerId: MarkerId('driver_${u.id}'),
          position: LatLng(u.lat, u.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isSelectedDriver
                ? BitmapDescriptor.hueAzure
                : BitmapDescriptor.hueBlue,
          ),
          zIndexInt: isSelectedDriver ? 20 : 10,
          infoWindow: InfoWindow(
            title: u.conductorNombre.isEmpty ? u.userId : u.conductorNombre,
            snippet: [
              if (u.rutaCodigo.isNotEmpty) u.rutaCodigo,
              DateFormat('HH:mm').format(u.updatedAt.toDate()),
            ].join(' · '),
          ),
          onTap: () => _enfocarConductor(u, rutas, ubicaciones),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: GoogleMap(
        onMapCreated: (controller) => _mapController = controller,
        initialCameraPosition: CameraPosition(target: center, zoom: 11),
        markers: markers,
        polylines: polylines,
        trafficEnabled: _traffic,
        mapToolbarEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
      ),
    );
  }

  Widget _buildPanel(
    List<RutaDoc> rutas,
    RutaDoc? selected,
    List<RutaUbicacionDoc> ubicaciones,
  ) {
    final selectedDriver = _selectedDriver(ubicaciones);
    final km = selected == null ? 0.0 : _kmEstimados(selected, selectedDriver);
    final etaNormal = km <= 0 ? 0 : (km / 22 * 60).round();
    final etaPesado = km <= 0 ? 0 : (km / 16 * 60).round();
    final directions = _directions?.ok == true ? _directions : null;
    final directionsKm = (directions?.distanceMeters ?? 0) / 1000;
    final origenValue = selectedDriver == null ? '__centro__' : _origenId;
    final visibles = selected == null
        ? ubicaciones
        : ubicaciones.where((u) => u.rutaId == selected.id).toList();

    return Card(
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text(
            'Centro de control',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: selected?.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Ruta en mapa',
              border: OutlineInputBorder(),
            ),
            items: rutas
                .map(
                  (r) => DropdownMenuItem(value: r.id, child: Text(r.codigo)),
                )
                .toList(),
            onChanged: (v) => setState(() {
              _rutaId = v;
              _limpiarCalculo();
            }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: origenValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Origen para calcular ETA',
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: '__centro__',
                child: Text(_centroOperacionesNombre),
              ),
              for (final u in ubicaciones)
                DropdownMenuItem(
                  value: _driverValue(u),
                  child: Text(
                    [
                      u.conductorNombre.isEmpty ? u.userId : u.conductorNombre,
                      if (u.rutaCodigo.isNotEmpty) u.rutaCodigo,
                    ].join(' · '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() {
              _origenId = v ?? '__centro__';
              _limpiarCalculo();
            }),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _traffic,
            onChanged: (v) => setState(() => _traffic = v),
            title: const Text('Capa de tráfico'),
            subtitle: const Text('Depende de la configuración de Google Maps.'),
          ),
          const Divider(),
          if (selected != null) ...[
            _MetricTile(
              icon: Icons.route_outlined,
              title: directions == null
                  ? '${selected.stops.length} establecimientos'
                  : '${directionsKm.toStringAsFixed(1)} km por calles',
              subtitle: directions == null
                  ? '${km.toStringAsFixed(1)} km estimados desde ${_origenLabel(ubicaciones)}'
                  : 'Ruta calculada por Google Maps desde ${_origenLabel(ubicaciones)}',
            ),
            _MetricTile(
              icon: Icons.schedule,
              title: directions == null
                  ? (etaNormal == 0
                        ? 'ETA pendiente'
                        : '${_fmtMin(etaNormal)} normal')
                  : '${_fmtSeconds(directions.durationTrafficSeconds)} con tráfico',
              subtitle: directions == null
                  ? (etaPesado == 0
                        ? 'Presiona calcular ruta para estimar por tráfico real.'
                        : '${_fmtMin(etaPesado)} con tráfico pesado estimado')
                  : '${_fmtSeconds(directions.durationSeconds)} normal · ${DateFormat('HH:mm').format(DateTime.now().add(Duration(seconds: directions.durationTrafficSeconds)))} llegada aprox.',
            ),
            if (_directionsError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _directionsError,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kRutasColor),
                onPressed: _calculandoRuta
                    ? null
                    : () => _calcularEtaConTrafico(selected, ubicaciones),
                icon: _calculandoRuta
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.traffic),
                label: Text(
                  _calculandoRuta
                      ? 'Calculando...'
                      : 'Calcular ruta con tráfico',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Establecimientos',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < selected.stops.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: kRutasColor.withOpacity(0.15),
                  foregroundColor: kRutasColor,
                  child: Text('${i + 1}'),
                ),
                title: Text(selected.stops[i].nombre),
                subtitle: Text(selected.stops[i].direccionVisible),
              ),
          ],
          const Divider(),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Último reporte de conductores',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text('${visibles.length}'),
            ],
          ),
          const SizedBox(height: 6),
          if (visibles.isEmpty)
            Text(
              'Cuando el conductor actualice ubicación o tome una foto, aparecerá aquí.',
              style: TextStyle(color: Colors.grey.shade700),
            )
          else
            for (final u in visibles.take(8))
              Builder(
                builder: (context) {
                  final selectedDriver = _driverValue(u) == _origenId;
                  return ListTile(
                    dense: true,
                    selected: selectedDriver,
                    selectedTileColor: kRutasColor.withOpacity(0.08),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.local_shipping,
                      color: selectedDriver ? kRutasColor : Colors.blue,
                    ),
                    title: Text(
                      u.conductorNombre.isEmpty ? u.userId : u.conductorNombre,
                      style: TextStyle(
                        fontWeight: selectedDriver
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (u.rutaCodigo.isNotEmpty) u.rutaCodigo,
                        if (u.vehiculo.isNotEmpty) u.vehiculo,
                        'GPS ${u.lat.toStringAsFixed(5)}, ${u.lng.toStringAsFixed(5)}',
                        DateFormat('dd/MM HH:mm').format(u.updatedAt.toDate()),
                      ].join(' · '),
                    ),
                    trailing: IconButton(
                      tooltip: 'Ver conductor en mapa',
                      onPressed: () => _enfocarConductor(u, rutas, ubicaciones),
                      icon: const Icon(Icons.center_focus_strong),
                    ),
                    onTap: () => _enfocarConductor(u, rutas, ubicaciones),
                  );
                },
              ),
        ],
      ),
    );
  }

  Future<void> _calcularEtaConTrafico(
    RutaDoc ruta,
    List<RutaUbicacionDoc> ubicaciones,
  ) async {
    final stops = ruta.stops.where((s) => s.geocodificada).toList();
    if (stops.isEmpty) {
      setState(() {
        _directions = null;
        _directionsError =
            'Esta ruta no tiene coordenadas para calcular el recorrido.';
      });
      return;
    }

    final driver = _selectedDriver(ubicaciones);
    final origin = driver == null
        ? RutaMapPoint(
            lat: _centroOperaciones.latitude,
            lng: _centroOperaciones.longitude,
          )
        : RutaMapPoint(lat: driver.lat, lng: driver.lng);
    final destinationStop = stops.last;
    final destination = RutaMapPoint(
      lat: destinationStop.lat!,
      lng: destinationStop.lng!,
    );
    final waypoints = stops.length <= 1
        ? const <RutaMapPoint>[]
        : stops
              .take(stops.length - 1)
              .take(23)
              .map((s) => RutaMapPoint(lat: s.lat!, lng: s.lng!))
              .toList();

    setState(() {
      _calculandoRuta = true;
      _directionsError = '';
    });
    try {
      final result = await calcularRutaConTrafico(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
      );
      if (!mounted) return;
      setState(() {
        _directions = result.ok ? result : null;
        _directionsError = result.ok
            ? ''
            : 'Maps no pudo calcular la ruta: ${result.error}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _directions = null;
        _directionsError = 'Maps no pudo calcular la ruta: $e';
      });
    } finally {
      if (mounted) setState(() => _calculandoRuta = false);
    }
  }

  double _kmEstimados(RutaDoc ruta, RutaUbicacionDoc? originDriver) {
    final geo = ruta.stops.where((s) => s.geocodificada).toList();
    if (geo.isEmpty) {
      return ruta.stops.fold<double>(
        0,
        (total, s) => total + (s.distanciaCentroKm ?? 0),
      );
    }
    if (originDriver == null &&
        geo.length == 1 &&
        geo.first.distanciaCentroKm != null) {
      return geo.first.distanciaCentroKm!;
    }

    var km = 0.0;
    var prevLat = originDriver?.lat ?? _centroOperaciones.latitude;
    var prevLng = originDriver?.lng ?? _centroOperaciones.longitude;
    for (final stop in geo) {
      final metros = RutasLogic.distanciaMetros(
        prevLat,
        prevLng,
        stop.lat,
        stop.lng,
      );
      if (metros > 0) km += metros / 1000;
      prevLat = stop.lat!;
      prevLng = stop.lng!;
    }
    return km;
  }

  String _fmtMin(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  String _fmtSeconds(int seconds) {
    if (seconds <= 0) return '0 min';
    return _fmtMin((seconds / 60).round());
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _MetricTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: kRutasColor),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
  );
}

// ─── Editor de establecimiento maestro ───────────────────────────────────────

class _EstablecimientoEditorScreen extends StatefulWidget {
  final String empresaId;
  final RutaEstablecimientoDoc? establecimiento;

  const _EstablecimientoEditorScreen({
    required this.empresaId,
    required this.establecimiento,
  });

  @override
  State<_EstablecimientoEditorScreen> createState() =>
      _EstablecimientoEditorScreenState();
}

class _EstablecimientoEditorScreenState
    extends State<_EstablecimientoEditorScreen> {
  final _service = RutasService();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _dirCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late bool _activo;
  bool _saving = false;
  bool _geocoding = false;

  bool get _isNew => widget.establecimiento == null;

  @override
  void initState() {
    super.initState();
    final e = widget.establecimiento;
    _nombreCtrl = TextEditingController(text: e?.nombre ?? '');
    _dirCtrl = TextEditingController(text: e?.direccionRaw ?? '');
    _latCtrl = TextEditingController(text: e?.lat?.toString() ?? '');
    _lngCtrl = TextEditingController(text: e?.lng?.toString() ?? '');
    _activo = e?.activo ?? true;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _dirCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _geocodificar() async {
    final dir = _dirCtrl.text.trim();
    if (dir.isEmpty) return;
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La geocodificación automática no está disponible en web. Ingresa lat/lng manualmente.',
          ),
        ),
      );
      return;
    }
    setState(() => _geocoding = true);
    try {
      final results = await geocoding.locationFromAddress(
        '$dir, Bogotá, Colombia',
      );
      if (results.isNotEmpty) {
        _latCtrl.text = results.first.latitude.toStringAsFixed(6);
        _lngCtrl.text = results.first.longitude.toStringAsFixed(6);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sin resultados para esa dirección.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo geocodificar: $e')));
      }
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final actual = widget.establecimiento;
      final doc = RutaEstablecimientoDoc(
        id: actual?.id ?? '',
        empresaId: widget.empresaId,
        nombre: _nombreCtrl.text.trim(),
        direccionRaw: _dirCtrl.text.trim(),
        direccionLimpia: actual?.direccionLimpia ?? '',
        lat: double.tryParse(_latCtrl.text.trim()),
        lng: double.tryParse(_lngCtrl.text.trim()),
        distanciaCentroKm: actual?.distanciaCentroKm,
        rangoDistancia: actual?.rangoDistancia ?? '',
        activo: _activo,
        createdAt: actual?.createdAt ?? Timestamp.now(),
      );
      await _service.guardarEstablecimiento(doc, isNew: _isNew);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isNew ? 'Establecimiento creado' : 'Establecimiento actualizado',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar establecimiento'),
        content: Text(
          '¿Eliminar "${widget.establecimiento?.nombre}" del maestro? '
          'Las rutas existentes conservan su copia actual.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.eliminarEstablecimiento(widget.establecimiento!.id);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Establecimiento eliminado')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kRutasColor,
        foregroundColor: Colors.white,
        title: Text(
          _isNew ? 'Nuevo establecimiento' : 'Editar establecimiento',
        ),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Eliminar',
              onPressed: _eliminar,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nombreCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Nombre del establecimiento',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _dirCtrl,
              decoration: const InputDecoration(labelText: 'Dirección'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Lat'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _lngCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Lng'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _geocoding ? null : _geocodificar,
                icon: _geocoding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: const Text('Geocodificar dirección'),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Establecimiento activo'),
              value: _activo,
              activeColor: kRutasColor,
              onChanged: (v) => setState(() => _activo = v),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kRutasColor),
              onPressed: _saving ? null : _guardar,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Guardando…' : 'Guardar establecimiento'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Editor de ruta (código + establecimientos + geocodificación persistida) ─

class _RutaEditorScreen extends StatefulWidget {
  final String empresaId;
  final RutaDoc? ruta;

  const _RutaEditorScreen({required this.empresaId, required this.ruta});

  @override
  State<_RutaEditorScreen> createState() => _RutaEditorScreenState();
}

class _RutaEditorScreenState extends State<_RutaEditorScreen> {
  final _service = RutasService();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codigoCtrl;
  late bool _activa;
  late List<RutaStop> _stops;
  List<RutaEstablecimientoDoc> _catalogo = [];
  int _catalogoActivosTotal = 0;
  bool _loadingCatalogo = true;
  bool _saving = false;

  bool get _isNew => widget.ruta == null;

  @override
  void initState() {
    super.initState();
    _codigoCtrl = TextEditingController(text: widget.ruta?.codigo ?? '');
    _activa = widget.ruta?.activa ?? true;
    _stops = [...?widget.ruta?.stops];
    _cargarCatalogo();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogo() async {
    try {
      final list = await _service.getEstablecimientos(widget.empresaId);
      final rutas = await _service.getRutas(widget.empresaId);
      final rutaActualId = widget.ruta?.id ?? '';
      final usadosEnOtrasRutas = <String>{};
      for (final ruta in rutas) {
        if (!ruta.activa || ruta.id == rutaActualId) continue;
        for (final stop in ruta.stops) {
          final key = _establecimientoKey(stop.nombre);
          if (key.isNotEmpty) usadosEnOtrasRutas.add(key);
        }
      }
      final activos = list.where((e) => e.activo).toList();
      if (!mounted) return;
      setState(() {
        _catalogoActivosTotal = activos.length;
        _catalogo = activos
            .where(
              (e) =>
                  !usadosEnOtrasRutas.contains(_establecimientoKey(e.nombre)),
            )
            .toList();
        _loadingCatalogo = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCatalogo = false);
    }
  }

  String _establecimientoKey(String nombre) => _normalizarTexto(nombre)
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  String _mensajeSinEstablecimientosDisponibles() {
    if (_catalogoActivosTotal == 0) {
      return 'Primero crea establecimientos en la pestaña Establecimientos.';
    }
    return 'No hay establecimientos disponibles. Los establecimientos activos ya están usados en otras rutas.';
  }

  Future<void> _agregarDesdeCatalogo() async {
    if (_loadingCatalogo) return;
    if (_catalogo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensajeSinEstablecimientosDisponibles())),
      );
      return;
    }

    final seleccion = <String>{};
    final existentes = _stops.map((s) => _establecimientoKey(s.nombre)).toSet();
    final filtroCtrl = TextEditingController();

    final result = await showDialog<List<RutaEstablecimientoDoc>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = _normalizarTexto(filtroCtrl.text);
          final visibles = _catalogo.where((e) {
            if (q.isEmpty) return true;
            return _normalizarTexto(e.nombre).contains(q) ||
                _normalizarTexto(e.direccionVisible).contains(q);
          }).toList();
          return AlertDialog(
            title: const Text('Agregar establecimientos a la ruta'),
            content: SizedBox(
              width: math.min(MediaQuery.of(ctx).size.width * 0.92, 620.0),
              height: math.min(MediaQuery.of(ctx).size.height * 0.68, 560.0),
              child: Column(
                children: [
                  TextField(
                    controller: filtroCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Buscar establecimiento',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visibles.isEmpty
                        ? const Center(child: Text('Sin resultados.'))
                        : ListView.builder(
                            itemCount: visibles.length,
                            itemBuilder: (_, i) {
                              final e = visibles[i];
                              final yaExiste = existentes.contains(
                                _establecimientoKey(e.nombre),
                              );
                              final checked = seleccion.contains(e.id);
                              return CheckboxListTile(
                                value: checked,
                                onChanged: yaExiste
                                    ? null
                                    : (v) {
                                        setLocal(() {
                                          if (v == true) {
                                            seleccion.add(e.id);
                                          } else {
                                            seleccion.remove(e.id);
                                          }
                                        });
                                      },
                                title: Text(e.nombre),
                                subtitle: Text(
                                  yaExiste
                                      ? 'Ya está en esta ruta'
                                      : e.direccionVisible,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kRutasColor),
                onPressed: seleccion.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, [
                        for (final e in _catalogo)
                          if (seleccion.contains(e.id)) e,
                      ]),
                icon: const Icon(Icons.add),
                label: Text('Agregar (${seleccion.length})'),
              ),
            ],
          );
        },
      ),
    );

    filtroCtrl.dispose();
    if (result == null || result.isEmpty) return;
    setState(() {
      for (final e in result) {
        _stops.add(e.toStop(orden: _stops.length));
      }
    });
  }

  Future<void> _reemplazarDesdeCatalogo(int index) async {
    if (_catalogo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensajeSinEstablecimientosDisponibles())),
      );
      return;
    }
    final existentesOtros = <String>{
      for (var i = 0; i < _stops.length; i++)
        if (i != index) _establecimientoKey(_stops[i].nombre),
    };
    final elegido = await showDialog<RutaEstablecimientoDoc>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reemplazar establecimiento'),
        content: SizedBox(
          width: math.min(MediaQuery.of(ctx).size.width * 0.92, 520.0),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _catalogo.length,
            itemBuilder: (_, i) {
              final e = _catalogo[i];
              final yaExiste = existentesOtros.contains(
                _establecimientoKey(e.nombre),
              );
              return ListTile(
                enabled: !yaExiste,
                title: Text(e.nombre),
                subtitle: Text(
                  yaExiste ? 'Ya está en esta ruta' : e.direccionVisible,
                ),
                onTap: yaExiste ? null : () => Navigator.pop(ctx, e),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (elegido == null) return;
    setState(() => _stops[index] = elegido.toStop(orden: index));
  }

  void _renumerar() {
    for (var i = 0; i < _stops.length; i++) {
      _stops[i] = _stops[i].copyWith(orden: i);
    }
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega al menos un establecimiento a la ruta.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    _renumerar();
    try {
      final vistos = <String>{};
      String? duplicado;
      for (final stop in _stops) {
        if (!vistos.add(_establecimientoKey(stop.nombre))) {
          duplicado = stop.nombre;
          break;
        }
      }
      if (duplicado != null) {
        throw ArgumentError(
          'La ruta no puede repetir el establecimiento "$duplicado".',
        );
      }
      final doc = RutaDoc(
        id: widget.ruta?.id ?? '',
        empresaId: widget.empresaId,
        codigo: _codigoCtrl.text.trim(),
        stops: _stops,
        activa: _activa,
        createdAt: widget.ruta?.createdAt ?? Timestamp.now(),
      );
      await _service.guardarRuta(doc, isNew: _isNew);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isNew ? 'Ruta creada' : 'Ruta actualizada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar ruta'),
        content: Text(
          '¿Eliminar "${widget.ruta?.codigo}"? No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.eliminarRuta(widget.ruta!.id);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ruta eliminada')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kRutasColor,
        foregroundColor: Colors.white,
        title: Text(_isNew ? 'Nueva ruta' : 'Editar ruta'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Eliminar',
              onPressed: _eliminar,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _codigoCtrl,
              decoration: const InputDecoration(
                labelText: 'Código / nombre (p.ej. "Ruta 1")',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ruta activa'),
              value: _activa,
              activeColor: kRutasColor,
              onChanged: (v) => setState(() => _activa = v),
            ),
            const Divider(),
            Row(
              children: [
                const Text(
                  'Establecimientos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _loadingCatalogo ? null : _agregarDesdeCatalogo,
                  icon: _loadingCatalogo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add),
                  label: const Text('Agregar desde maestro'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_stops.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('Sin establecimientos. Agrega al menos uno.'),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _stops.length,
                onReorder: (oldI, newI) {
                  setState(() {
                    if (newI > oldI) newI -= 1;
                    final item = _stops.removeAt(oldI);
                    _stops.insert(newI, item);
                    _renumerar();
                  });
                },
                itemBuilder: (_, i) {
                  final s = _stops[i];
                  return Card(
                    key: ValueKey('stop_${s.nombre}_$i'),
                    child: ListTile(
                      leading: const Icon(Icons.drag_handle),
                      title: Text(s.nombre),
                      subtitle: Text(
                        '${s.direccionVisible}\n'
                        '${s.geocodificada ? '📍 ${s.lat!.toStringAsFixed(5)}, ${s.lng!.toStringAsFixed(5)}' : '⚠ sin ubicación'}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Reemplazar desde maestro',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _reemplazarDesdeCatalogo(i),
                          ),
                          IconButton(
                            tooltip: 'Quitar de esta ruta',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => _stops.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kRutasColor),
              onPressed: _saving ? null : _guardar,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Guardando…' : 'Guardar ruta'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pestaña: configuración (ciclo de menú + ventanas + radio) ────────────────

class _ConfigTab extends StatefulWidget {
  final String empresaId;

  const _ConfigTab({required this.empresaId});

  @override
  State<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<_ConfigTab> {
  final _service = RutasService();
  RutaConfigDoc? _config;
  bool _loading = true;
  bool _saving = false;
  final _radioCtrl = TextEditingController();
  final _origenNombreCtrl = TextEditingController();
  final _origenDireccionCtrl = TextEditingController();
  final _origenLatCtrl = TextEditingController();
  final _origenLngCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _radioCtrl.dispose();
    _origenNombreCtrl.dispose();
    _origenDireccionCtrl.dispose();
    _origenLatCtrl.dispose();
    _origenLngCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final cfg = await _service.getConfig(widget.empresaId);
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _radioCtrl.text = cfg.radioValidacionMetros.toString();
      _origenNombreCtrl.text = cfg.origenNombre;
      _origenDireccionCtrl.text = cfg.origenDireccion;
      _origenLatCtrl.text = cfg.origenLat.toStringAsFixed(6);
      _origenLngCtrl.text = cfg.origenLng.toStringAsFixed(6);
      _loading = false;
    });
  }

  String _fmtTime(String hhmm) => hhmm;

  DateTime _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _finCalendarioMenus(DateTime hoy) {
    final finEsteAnio = DateTime(hoy.year, 8, 31);
    return hoy.isAfter(finEsteAnio)
        ? DateTime(hoy.year + 1, 8, 31)
        : finEsteAnio;
  }

  String _nombreMes(DateTime d) {
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final mes = meses[d.month - 1];
    return '${mes[0].toUpperCase()}${mes.substring(1)} ${d.year}';
  }

  List<DateTime> _mesesEntre(DateTime inicio, DateTime fin) {
    final out = <DateTime>[];
    var current = DateTime(inicio.year, inicio.month);
    final last = DateTime(fin.year, fin.month);
    while (!current.isAfter(last)) {
      out.add(current);
      current = DateTime(current.year, current.month + 1);
    }
    return out;
  }

  Widget _calendarioMenus(RutaConfigDoc cfg) {
    final hoy = _soloFecha(DateTime.now());
    final fin = _finCalendarioMenus(hoy);
    final base = cfg.cicloFechaBase.toDate();
    final meses = _mesesEntre(hoy, fin);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Calendario de menús',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Chip(
              avatar: const Icon(Icons.today, size: 18),
              label: Text(
                'Hoy: Menú ${RutasLogic.menuNumeroParaFecha(hoy, base)}',
              ),
            ),
            Text(
              'Hasta ${DateFormat('dd/MM/yyyy').format(fin)}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final max = constraints.maxWidth;
            final cardWidth = max >= 1220
                ? (max - 24) / 3
                : max >= 820
                ? (max - 12) / 2
                : max;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final mes in meses)
                  SizedBox(
                    width: cardWidth,
                    child: _calendarioMes(mes, hoy, fin, base),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _calendarioMes(
    DateTime mes,
    DateTime hoy,
    DateTime fin,
    DateTime base,
  ) {
    final first = DateTime(mes.year, mes.month);
    final daysInMonth = DateTime(mes.year, mes.month + 1, 0).day;
    final leading = first.weekday - 1;
    final cells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _nombreMes(mes),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: const [
                _DiaHeader('L'),
                _DiaHeader('M'),
                _DiaHeader('X'),
                _DiaHeader('J'),
                _DiaHeader('V'),
                _DiaHeader('S'),
                _DiaHeader('D'),
              ],
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.12,
              ),
              itemBuilder: (_, i) {
                final day = i - leading + 1;
                if (day < 1 || day > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final date = DateTime(mes.year, mes.month, day);
                final activo = !date.isBefore(hoy) && !date.isAfter(fin);
                final esHoy = date == hoy;
                final menu = RutasLogic.menuNumeroParaFecha(date, base);
                return Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: esHoy
                        ? kRutasColor.withOpacity(0.14)
                        : activo
                        ? Colors.white
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: esHoy
                          ? kRutasColor
                          : activo
                          ? Colors.grey.shade300
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: activo ? Colors.black87 : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      if (activo)
                        Text(
                          'Menú $menu',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: esHoy ? kRutasColor : Colors.black87,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
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
    );
  }

  Future<void> _editarVehiculo([RutaVehiculoDoc? vehiculo]) async {
    final placaCtrl = TextEditingController(text: vehiculo?.placa ?? '');
    final descCtrl = TextEditingController(text: vehiculo?.descripcion ?? '');
    var activo = vehiculo?.activo ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(vehiculo == null ? 'Agregar placa' : 'Editar placa'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: placaCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Placa',
                    hintText: 'Ej: BGO856',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descripción opcional',
                    hintText: 'Ej: Camión refrigerado',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: activo,
                  activeColor: kRutasColor,
                  onChanged: (v) => setLocal(() => activo = v),
                  title: const Text('Disponible para asignaciones'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kRutasColor),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    final placa = placaCtrl.text.trim().toUpperCase();
    final descripcion = descCtrl.text.trim();
    placaCtrl.dispose();
    descCtrl.dispose();
    if (ok != true) return;
    if (placa.isEmpty) {
      _snack('La placa es obligatoria.');
      return;
    }

    try {
      await _service.guardarVehiculo(
        RutaVehiculoDoc(
          id: vehiculo?.id ?? '',
          empresaId: widget.empresaId,
          placa: placa,
          descripcion: descripcion,
          activo: activo,
          createdAt: vehiculo?.createdAt ?? Timestamp.now(),
        ),
        isNew: vehiculo == null,
      );
      _snack('Placa guardada: $placa');
    } catch (e) {
      _snack('No se pudo guardar la placa: $e');
    }
  }

  Future<void> _eliminarVehiculo(RutaVehiculoDoc vehiculo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirar placa'),
        content: Text(
          '¿Retirar ${vehiculo.placa} de nuevas asignaciones? '
          'La placa y sus asignaciones anteriores se conservarán en el historial.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Retirar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.eliminarVehiculo(vehiculo.id);
      _snack('Placa retirada y conservada en el historial.');
    } catch (e) {
      _snack('No se pudo retirar la placa: $e');
    }
  }

  Future<void> _reactivarVehiculo(RutaVehiculoDoc vehiculo) async {
    try {
      await _service.reactivarVehiculo(vehiculo.id);
      _snack('Placa reactivada: ${vehiculo.placa}');
    } catch (e) {
      _snack('No se pudo reactivar la placa: $e');
    }
  }

  Widget _maestroVehiculos() {
    return StreamBuilder<List<RutaVehiculoDoc>>(
      stream: _service.streamVehiculos(widget.empresaId),
      builder: (context, snap) {
        final vehiculos = snap.data ?? const <RutaVehiculoDoc>[];
        final activos = vehiculos.where((v) => v.activo).length;
        final historicos = vehiculos.length - activos;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Maestro de placas',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Chip(
                  avatar: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: Text('$activos activas'),
                ),
                if (historicos > 0)
                  Chip(
                    avatar: const Icon(Icons.history, size: 18),
                    label: Text('$historicos en historial'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _editarVehiculo(),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar placa'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!snap.hasData)
              const LinearProgressIndicator(minHeight: 2)
            else if (vehiculos.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  'Agrega las placas una sola vez para seleccionarlas en asignaciones.',
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 780;
                  final width = wide
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final v in vehiculos)
                        SizedBox(
                          width: width,
                          child: Card(
                            child: ListTile(
                              leading: Icon(
                                Icons.local_shipping_outlined,
                                color: v.activo ? kRutasColor : Colors.grey,
                              ),
                              title: Text(
                                v.placa,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (v.descripcion.isNotEmpty) v.descripcion,
                                  if (v.activo)
                                    'Activa'
                                  else if (v.inactivatedAt != null)
                                    'Retirada el ${DateFormat('dd/MM/yyyy HH:mm').format(v.inactivatedAt!.toDate())}'
                                  else
                                    'Histórica',
                                ].join(' · '),
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'Editar',
                                    onPressed: () => _editarVehiculo(v),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  if (v.activo)
                                    IconButton(
                                      tooltip: 'Retirar y conservar historial',
                                      onPressed: () => _eliminarVehiculo(v),
                                      icon: const Icon(Icons.archive_outlined),
                                    )
                                  else
                                    IconButton(
                                      tooltip: 'Reactivar placa',
                                      onPressed: () => _reactivarVehiculo(v),
                                      icon: const Icon(Icons.restore),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickFechaBase() async {
    final actual = _config!.cicloFechaBase.toDate();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2030, 12, 31),
      initialDate: actual,
    );
    if (d == null) return;
    setState(() {
      _config = _config!.copyWith(cicloFechaBase: Timestamp.fromDate(d));
    });
  }

  Future<void> _pickHora(String comida, bool desde) async {
    final v = _config!.ventanaDe(comida);
    final actual = desde ? v.desde : v.hasta;
    final parts = actual.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 0,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final str =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final nuevas = Map<String, VentanaComida>.from(_config!.ventanas);
    nuevas[comida] = desde
        ? VentanaComida(desde: str, hasta: v.hasta)
        : VentanaComida(desde: v.desde, hasta: str);
    setState(() => _config = _config!.copyWith(ventanas: nuevas));
  }

  Future<void> _guardar() async {
    final origenLat = double.tryParse(
      _origenLatCtrl.text.trim().replaceAll(',', '.'),
    );
    final origenLng = double.tryParse(
      _origenLngCtrl.text.trim().replaceAll(',', '.'),
    );
    if (origenLat == null || origenLng == null) {
      _snack('La latitud y longitud del origen deben ser válidas.');
      return;
    }
    setState(() => _saving = true);
    try {
      final radio =
          int.tryParse(_radioCtrl.text.trim()) ?? kRadioValidacionMetrosDefault;
      final cfg = _config!.copyWith(
        radioValidacionMetros: radio,
        origenNombre: _origenNombreCtrl.text.trim().isEmpty
            ? kRutaOrigenNombreDefault
            : _origenNombreCtrl.text.trim(),
        origenDireccion: _origenDireccionCtrl.text.trim(),
        origenLat: origenLat,
        origenLng: origenLng,
      );
      await _service.guardarConfig(cfg);
      _config = cfg;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Configuración guardada')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _config == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final cfg = _config!;
    final fechaBase = cfg.cicloFechaBase.toDate();
    final menuHoy =
        ((DateTime.now()
                        .difference(
                          DateTime(
                            fechaBase.year,
                            fechaBase.month,
                            fechaBase.day,
                          ),
                        )
                        .inDays %
                    kMenuCount) +
                kMenuCount) %
            kMenuCount +
        1;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle('Origen de distribución'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                final fields = [
                  TextField(
                    controller: _origenNombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del origen',
                    ),
                  ),
                  TextField(
                    controller: _origenDireccionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dirección de salida',
                    ),
                  ),
                  TextField(
                    controller: _origenLatCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Latitud'),
                  ),
                  TextField(
                    controller: _origenLngCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Longitud'),
                  ),
                ];
                if (!wide) {
                  return Column(
                    children: [
                      for (var i = 0; i < fields.length; i++) ...[
                        fields[i],
                        if (i < fields.length - 1) const SizedBox(height: 8),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: fields[0]),
                    const SizedBox(width: 10),
                    Expanded(flex: 3, child: fields[1]),
                    const SizedBox(width: 10),
                    Expanded(child: fields[2]),
                    const SizedBox(width: 10),
                    Expanded(child: fields[3]),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _SectionTitle('Ciclo de menús (21 días)'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event, color: kRutasColor),
            title: const Text('Fecha base (día del "Menú 1")'),
            subtitle: Text(DateFormat('dd/MM/yyyy').format(fechaBase)),
            trailing: TextButton(
              onPressed: _pickFechaBase,
              child: const Text('Cambiar'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Hoy correspondería el Menú $menuHoy.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
        _calendarioMenus(cfg),
        const SizedBox(height: 12),
        _maestroVehiculos(),
        const SizedBox(height: 12),
        const _SectionTitle('Ventanas de tiempo de comida'),
        ...kComidasOrden.map((comida) {
          final v = cfg.ventanaDe(comida);
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      comida,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _pickHora(comida, true),
                    child: Text('Desde ${_fmtTime(v.desde)}'),
                  ),
                  const Text('—'),
                  TextButton(
                    onPressed: () => _pickHora(comida, false),
                    child: Text('Hasta ${_fmtTime(v.hasta)}'),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        const _SectionTitle('Validación de ubicación'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _radioCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText:
                    'Radio máximo (metros) para considerar "en el establecimiento"',
                helperText:
                    'Si la captura supera este radio, la evidencia se marca como fuera de rango.',
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kRutasColor),
          onPressed: _saving ? null : _guardar,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Guardando…' : 'Guardar configuración'),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Usuarios de la empresa (para asignaciones y roles)
// ══════════════════════════════════════════════════════════════════════════════

class _UsuarioOpcion {
  final String userId; // docId en TBL_USUARIOS (= cédula)
  final String cedula;
  final String nombre;
  final String cargo;
  final String rolRutas;

  /// Estado laboral en la empresa activa (Talento Humano). Un inhabilitado
  /// no se ofrece para nuevas asignaciones.
  final bool activo;

  const _UsuarioOpcion({
    required this.userId,
    required this.cedula,
    required this.nombre,
    this.cargo = '',
    this.rolRutas = '',
    this.activo = true,
  });

  String get label => cargo.trim().isEmpty ? nombre : '$nombre · $cargo';

  bool get esConductor {
    final rol = _normalizarTexto(rolRutas);
    final cargoNorm = _normalizarTexto(cargo);
    if (cargoNorm.isNotEmpty) {
      return cargoNorm.contains('conductor') && !cargoNorm.contains('ayudante');
    }
    return rol == kRutasRolConductor;
  }

  bool get esAyudanteDistribucion {
    final cargoNorm = _normalizarTexto(cargo);
    // Basta con que el cargo diga "ayudante": los cargos reales varían
    // ("Ayudante de distribución", "Ayudante logístico", "Ayudante ruta").
    return cargoNorm.contains('ayudante');
  }
}

String _firstString(Map<dynamic, dynamic> m, List<String> keys) {
  for (final key in keys) {
    final value = m[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _nombreUsuario(Map<String, dynamic> m, String fallback) {
  final directo = _firstString(m, const ['nombre', 'nombreCompleto']);
  if (directo.isNotEmpty) return directo;
  final nombres = [
    _firstString(m, const ['nombres', 'primerNombre']),
    _firstString(m, const ['apellidos', 'primerApellido']),
  ].where((e) => e.isNotEmpty).join(' ');
  return nombres.isEmpty ? fallback : nombres;
}

String _cargoUsuario(Map<String, dynamic> m, String empresaId) {
  final detalle = m['empresasDetalle'];
  if (detalle is Map) {
    final scoped = detalle[empresaId];
    if (scoped is Map) {
      final cargo = _firstString(scoped, const [
        'cargo',
        'cargoNombre',
        'cargo_nombre',
        'cargoId',
      ]);
      if (cargo.isNotEmpty) return cargo;
    }
  }
  return _firstString(m, const [
    'cargo',
    'cargoNombre',
    'cargo_nombre',
    'cargoId',
  ]);
}

/// Activo = no inhabilitado en Talento Humano para esta empresa
/// (`empresasDetalle.{empresaId}.estadoLaboral`) y con `estado` global válido.
bool _usuarioActivo(Map<String, dynamic> m, String empresaId) {
  final detalle = m['empresasDetalle'];
  if (detalle is Map) {
    final scoped = detalle[empresaId];
    if (scoped is Map) {
      final laboral = _firstString(scoped, const [
        'estadoLaboral',
        'estado',
      ]).toLowerCase();
      if (laboral == 'inactivo') return false;
    }
  }
  final global = (m['estado'] ?? '').toString().trim().toLowerCase();
  return global.isEmpty || global == 'activo';
}

Future<List<_UsuarioOpcion>> _cargarUsuariosEmpresa(
  String empresaId, {
  bool incluirTodos = false,
}) async {
  final db = FirebaseFirestore.instance;
  Query<Map<String, dynamic>> q = db.collection('TBL_USUARIOS');
  if (!incluirTodos) {
    q = q.where('empresas', arrayContains: empresaId);
  }
  final rolesSnap = await db
      .collection('TBL_RUTAS_ROLES')
      .where('empresaId', isEqualTo: empresaId)
      .get();
  final roles = <String, String>{};
  for (final d in rolesSnap.docs) {
    final rol = (d.data()['rol'] ?? '').toString().trim().toLowerCase();
    final userId = (d.data()['userId'] ?? '').toString().trim();
    final cedula = (d.data()['cedula'] ?? '').toString().trim();
    if (userId.isNotEmpty) roles[userId] = rol;
    if (cedula.isNotEmpty) roles[cedula] = rol;
  }

  final snap = await q.get();
  final list = snap.docs.map((d) {
    final m = d.data();
    final cedula = (m['cedula'] ?? d.id).toString().trim();
    return _UsuarioOpcion(
      userId: d.id,
      cedula: cedula.isEmpty ? d.id : cedula,
      nombre: _nombreUsuario(m, d.id),
      cargo: _cargoUsuario(m, empresaId),
      rolRutas: roles[d.id] ?? roles[cedula] ?? '',
      activo: _usuarioActivo(m, empresaId),
    );
  }).toList();
  list.sort((a, b) => a.nombre.compareTo(b.nombre));
  return list;
}

class _UsoAppRutasTab extends StatefulWidget {
  final String empresaId;

  const _UsoAppRutasTab({required this.empresaId});

  @override
  State<_UsoAppRutasTab> createState() => _UsoAppRutasTabState();
}

class _UsoAppRutasTabState extends State<_UsoAppRutasTab> {
  late Future<List<_UsuarioOpcion>> _usuariosFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _usuariosFuture = _cargarUsuariosEmpresa(widget.empresaId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_UsuarioOpcion>>(
      future: _usuariosFuture,
      builder: (context, usersSnap) {
        if (usersSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (usersSnap.hasError) {
          return Center(
            child: Text('Error cargando usuarios: ${usersSnap.error}'),
          );
        }
        final operativos = (usersSnap.data ?? const <_UsuarioOpcion>[])
            .where((u) => u.esConductor || u.esAyudanteDistribucion)
            .toList();

        return StreamBuilder<List<LoginSessionDoc>>(
          stream: SessionAuditService().streamEmpresaSessions(widget.empresaId),
          builder: (context, sessionsSnap) {
            final sessions = sessionsSnap.data ?? const <LoginSessionDoc>[];
            final latestByUser = _latestSessionByUser(sessions);
            final filtered = _filterUsers(operativos);
            final loggedUsers = operativos
                .where((u) => _latestForUser(u, latestByUser) != null)
                .length;
            final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
            final operativeKeys = <String>{
              for (final u in operativos) ...[
                if (u.userId.trim().isNotEmpty) u.userId.trim(),
                if (u.cedula.trim().isNotEmpty) u.cedula.trim(),
              ],
            };
            final todayCount = sessions
                .where((s) => _sessionBelongsTo(s, operativeKeys))
                .where(
                  (s) =>
                      DateFormat('yyyy-MM-dd').format(s.loginAt.toDate()) ==
                      todayKey,
                )
                .length;
            final recent = sessions
                .where((s) => _sessionBelongsTo(s, operativeKeys))
                .take(50)
                .toList();
            final isMobile = MediaQuery.of(context).size.width < 760;

            return Padding(
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Uso de la app por personal operativo',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Chip(
                        avatar: const Icon(Icons.badge_outlined, size: 18),
                        label: Text(
                          '${operativos.length} conductores/ayudantes',
                        ),
                      ),
                      Chip(
                        avatar: const Icon(Icons.login_rounded, size: 18),
                        label: Text('$todayCount ingresos hoy'),
                      ),
                      Chip(
                        avatar: const Icon(Icons.verified_user, size: 18),
                        label: Text('$loggedUsers con registro'),
                      ),
                      Chip(
                        avatar: const Icon(Icons.person_off_outlined, size: 18),
                        label: Text(
                          '${operativos.length - loggedUsers} sin ingreso',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar conductor o ayudante',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: sessionsSnap.hasError
                        ? Center(
                            child: Text(
                              'Error cargando ingresos: ${sessionsSnap.error}',
                            ),
                          )
                        : !sessionsSnap.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : isMobile
                        ? _cards(filtered, latestByUser)
                        : Row(
                            children: [
                              Expanded(
                                flex: 7,
                                child: _table(filtered, latestByUser),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(width: 380, child: _recentPanel(recent)),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<_UsuarioOpcion> _filterUsers(List<_UsuarioOpcion> users) {
    final query = _normalizarTexto(_query);
    if (query.isEmpty) return users;
    return users.where((u) {
      return _normalizarTexto(u.nombre).contains(query) ||
          _normalizarTexto(u.cedula).contains(query) ||
          _normalizarTexto(u.cargo).contains(query) ||
          _normalizarTexto(u.userId).contains(query);
    }).toList();
  }

  Map<String, LoginSessionDoc> _latestSessionByUser(
    List<LoginSessionDoc> sessions,
  ) {
    final out = <String, LoginSessionDoc>{};
    for (final session in sessions) {
      for (final key in [
        session.userId.trim(),
        session.cedula.trim(),
      ].where((v) => v.isNotEmpty)) {
        final current = out[key];
        if (current == null ||
            session.loginAt.toDate().isAfter(current.loginAt.toDate())) {
          out[key] = session;
        }
      }
    }
    return out;
  }

  LoginSessionDoc? _latestForUser(
    _UsuarioOpcion user,
    Map<String, LoginSessionDoc> latestByUser,
  ) {
    return latestByUser[user.userId.trim()] ?? latestByUser[user.cedula.trim()];
  }

  bool _sessionBelongsTo(LoginSessionDoc session, Set<String> userKeys) {
    return userKeys.contains(session.userId.trim()) ||
        userKeys.contains(session.cedula.trim());
  }

  Widget _table(
    List<_UsuarioOpcion> users,
    Map<String, LoginSessionDoc> latestByUser,
  ) {
    if (users.isEmpty) {
      return const Center(child: Text('No hay conductores o ayudantes.'));
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: PagedDataTable(
            etiqueta: 'registros',
            tabla: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFEAF7EF)),
              columns: const [
                DataColumn(label: Text('Persona')),
                DataColumn(label: Text('Cargo')),
                DataColumn(label: Text('Último ingreso')),
                DataColumn(label: Text('Plataforma')),
                DataColumn(label: Text('Tipo')),
              ],
              rows: [
                for (final user in users)
                  _row(user, _latestForUser(user, latestByUser)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DataRow _row(_UsuarioOpcion user, LoginSessionDoc? latest) {
    return DataRow(
      cells: [
        DataCell(
          SizedBox(
            width: 280,
            child: Row(
              children: [
                UserAvatar(
                  userId: user.userId,
                  nameHint: user.nombre,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        user.cedula,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 230,
            child: Text(
              user.cargo.isEmpty ? '-' : user.cargo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Text(latest == null ? 'Sin registro' : _fmtLoginAt(latest.loginAt)),
        ),
        DataCell(Text(latest?.platform ?? '-')),
        DataCell(Text(latest == null ? '-' : _sourceLabel(latest.source))),
      ],
    );
  }

  Widget _cards(
    List<_UsuarioOpcion> users,
    Map<String, LoginSessionDoc> latestByUser,
  ) {
    if (users.isEmpty) {
      return const Center(child: Text('No hay conductores o ayudantes.'));
    }
    return ListView.separated(
      itemCount: users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final user = users[index];
        final latest = _latestForUser(user, latestByUser);
        return Card(
          child: ListTile(
            leading: UserAvatar(userId: user.userId, nameHint: user.nombre),
            title: Text(
              user.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${user.cedula}\n'
              '${user.cargo.isEmpty ? '-' : user.cargo}\n'
              'Último ingreso: ${latest == null ? 'Sin registro' : _fmtLoginAt(latest.loginAt)}',
            ),
            isThreeLine: true,
            trailing: latest == null
                ? const Icon(Icons.person_off_outlined, color: Colors.black45)
                : const Icon(Icons.check_circle, color: kRutasColor),
          ),
        );
      },
    );
  }

  Widget _recentPanel(List<LoginSessionDoc> sessions) {
    return Card(
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.history, color: kRutasColor),
            title: Text(
              'Ingresos recientes',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text('Conductores y ayudantes'),
          ),
          const Divider(height: 1),
          Expanded(
            child: sessions.isEmpty
                ? const Center(child: Text('Sin ingresos registrados.'))
                : ListView.separated(
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = sessions[i];
                      return ListTile(
                        dense: true,
                        leading: UserAvatar(
                          userId: s.userId,
                          nameHint: s.nombre,
                          radius: 16,
                        ),
                        title: Text(
                          s.nombre.isEmpty ? s.userId : s.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_fmtLoginAt(s.loginAt)} · ${s.platform} · ${_sourceLabel(s.source)}',
                          maxLines: 2,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _fmtLoginAt(Timestamp ts) =>
      DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());

  String _sourceLabel(String source) {
    switch (source) {
      case 'password':
        return 'Contraseña';
      case 'biometria':
        return 'Biometría';
      case 'sesion_guardada':
        return 'Sesión guardada';
      default:
        return source.isEmpty ? '-' : source;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Pestaña: Asignaciones (personal por ruta, con histórico)
// ══════════════════════════════════════════════════════════════════════════════

class _AsignacionesTab extends StatefulWidget {
  final String empresaId;
  final String adminUserId;
  final bool modoDesarrollador;

  const _AsignacionesTab({
    required this.empresaId,
    required this.adminUserId,
    this.modoDesarrollador = false,
  });

  @override
  State<_AsignacionesTab> createState() => _AsignacionesTabState();
}

class _AsignacionesTabState extends State<_AsignacionesTab> {
  final _service = RutasService();
  late Future<List<_UsuarioOpcion>> _usuariosFuture;
  late Future<List<RutaVehiculoDoc>> _vehiculosFuture;

  /// Cédulas inhabilitadas en Talento Humano, para marcar las asignaciones
  /// que quedaron con personal retirado.
  Set<String> _inactivos = {};

  @override
  void initState() {
    super.initState();
    _usuariosFuture = _recargarUsuarios();
    _vehiculosFuture = _service.getVehiculos(widget.empresaId);
  }

  Future<List<_UsuarioOpcion>> _recargarUsuarios() async {
    final usuarios = await _cargarUsuariosEmpresa(
      widget.empresaId,
      incluirTodos: widget.modoDesarrollador,
    );
    final inactivos = <String>{
      for (final u in usuarios)
        if (!u.activo) ...[
          _normalizarLlaveAsignacion(u.userId),
          _normalizarLlaveAsignacion(u.cedula),
        ],
    }..remove('');
    if (mounted) setState(() => _inactivos = inactivos);
    return usuarios;
  }

  bool _estaInhabilitado(String cedula) =>
      _inactivos.contains(_normalizarLlaveAsignacion(cedula));

  Future<void> _asignar(RutaDoc ruta, RutaAsignacionDoc? actual) async {
    // Se relee en cada apertura: alguien pudo entrar o quedar inhabilitado en
    // Talento Humano con esta pantalla abierta.
    _usuariosFuture = _recargarUsuarios();
    final usuarios = await _usuariosFuture;
    final vehiculos = await _vehiculosFuture;
    final asignacionesActivas = await _service.getAsignacionesActivas(
      widget.empresaId,
    );
    final rutasActuales = await _service.getRutas(widget.empresaId);
    final rutaIdsValidos = rutasActuales.map((r) => r.id).toSet();
    final asignacionesValidas = asignacionesActivas
        .where((a) => rutaIdsValidos.contains(a.rutaId))
        .toList();
    if (!mounted) return;
    if (usuarios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay usuarios en esta empresa.')),
      );
      return;
    }

    final ocupados = _usuariosOcupadosEnOtrasRutas(
      asignacionesValidas,
      ruta.id,
    );
    // La asignación normal muestra solo personal disponible. El relevo es el
    // flujo explícito para mover personas que ya están en otra ruta.
    final conductores = usuarios
        .where(
          (u) =>
              u.activo &&
              (widget.modoDesarrollador || u.esConductor) &&
              !_usuarioOcupado(u, ocupados),
        )
        .toList();
    final ayudantes = usuarios
        .where(
          (u) =>
              u.activo &&
              (widget.modoDesarrollador || u.esAyudanteDistribucion) &&
              !_usuarioOcupado(u, ocupados),
        )
        .toList();
    if (conductores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay conductores disponibles. Revisa roles o libera una ruta.',
          ),
        ),
      );
      return;
    }

    final conductorActual = _matchUsuario(usuarios, actual?.conductorCedula);
    final ayudanteActual = _matchUsuario(usuarios, actual?.ayudanteCedula);
    final ayudante2Actual = _matchUsuario(usuarios, actual?.ayudante2Cedula);
    final conductorItems = _withActual(conductores, conductorActual);
    final ayudanteItems = _withActual(ayudantes, ayudanteActual);
    final ayudante2Items = _withActual(ayudantes, ayudante2Actual);

    _UsuarioOpcion? conductor = _matchUsuario(
      conductorItems,
      actual?.conductorCedula,
    );
    _UsuarioOpcion? ayudante = _matchUsuario(
      ayudanteItems,
      actual?.ayudanteCedula,
    );
    _UsuarioOpcion? ayudante2 = _matchUsuario(
      ayudante2Items,
      actual?.ayudante2Cedula,
    );
    var vehiculo = (actual?.vehiculo ?? '').trim().toUpperCase();
    final placasOcupadas = _placasOcupadasEnOtrasRutas(
      asignacionesValidas,
      ruta.id,
    );
    final placas =
        [
              for (final v in vehiculos.where((v) => v.activo))
                v.placa.trim().toUpperCase(),
              if (vehiculo.isNotEmpty) vehiculo,
            ]
            .where((v) => v.isNotEmpty)
            .where((v) => v == vehiculo || !placasOcupadas.contains(v))
            .toSet()
            .toList()
          ..sort();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Asignar ${ruta.codigo}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<_UsuarioOpcion>(
                  initialValue: conductor,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Conductor'),
                  items: conductorItems
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(
                            u.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => conductor = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<_UsuarioOpcion>(
                  initialValue: ayudante,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Ayudante de distribución (opcional)',
                  ),
                  items: [
                    const DropdownMenuItem<_UsuarioOpcion>(
                      value: null,
                      child: Text('— Sin ayudante —'),
                    ),
                    ...ayudanteItems.map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text(u.nombre, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setLocal(() => ayudante = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<_UsuarioOpcion>(
                  initialValue: ayudante2,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Segundo ayudante (opcional)',
                  ),
                  items: [
                    const DropdownMenuItem<_UsuarioOpcion>(
                      value: null,
                      child: Text('— Sin segundo ayudante —'),
                    ),
                    ...ayudante2Items.map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text(u.nombre, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setLocal(() => ayudante2 = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: vehiculo.isEmpty ? null : vehiculo,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Placa / vehículo',
                    helperText: placas.isEmpty
                        ? 'Agrega placas en Configuración inicial > Maestro de placas.'
                        : null,
                  ),
                  items: placas
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(p, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: placas.isEmpty
                      ? null
                      : (v) => setLocal(() => vehiculo = v ?? ''),
                ),
                if (!widget.modoDesarrollador && ayudantes.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'No hay usuarios con cargo "Ayudante De Distribución" en esta empresa.',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed:
                  conductor == null ||
                      _mismaPersona(conductor, ayudante) ||
                      _mismaPersona(conductor, ayudante2) ||
                      _mismaPersona(ayudante, ayudante2)
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || conductor == null) return;
    await _service.asignarRuta(
      RutaAsignacionDoc(
        empresaId: widget.empresaId,
        rutaId: ruta.id,
        rutaCodigo: ruta.codigo,
        conductorCedula: conductor!.userId,
        conductorNombre: conductor!.nombre,
        ayudanteCedula: ayudante?.userId ?? '',
        ayudanteNombre: ayudante?.nombre ?? '',
        ayudante2Cedula: ayudante2?.userId ?? '',
        ayudante2Nombre: ayudante2?.nombre ?? '',
        vehiculo: vehiculo.trim(),
        asignadoPor: widget.adminUserId,
        vigenteDesde: Timestamp.now(),
        createdAt: Timestamp.now(),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${ruta.codigo} asignada a ${conductor!.nombre}'),
        ),
      );
    }
  }

  Future<void> _abrirRelevo(
    List<RutaDoc> rutas,
    Map<String, RutaAsignacionDoc> porRuta,
  ) async {
    _usuariosFuture = _recargarUsuarios();
    final usuarios = await _usuariosFuture;
    final vehiculos = await _vehiculosFuture;
    if (!mounted) return;

    // En el relevo se puede elegir a CUALQUIER persona activa (incluidas las
    // que ya están en otra ruta): al aplicar se libera su ruta anterior.
    final conductores = usuarios
        .where((u) => u.activo && (widget.modoDesarrollador || u.esConductor))
        .toList();
    final ayudantes = usuarios
        .where(
          (u) =>
              u.activo &&
              (widget.modoDesarrollador || u.esAyudanteDistribucion),
        )
        .toList();
    final rutasActivas = rutas.where((r) => r.activa).toList()
      ..sort((a, b) => a.codigo.compareTo(b.codigo));
    final placas = [
      for (final v in vehiculos.where((v) => v.activo))
        v.placa.trim().toUpperCase(),
    ].where((p) => p.isNotEmpty).toSet().toList()..sort();

    if (conductores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay conductores disponibles.')),
      );
      return;
    }
    if (rutasActivas.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No hay rutas activas.')));
      return;
    }

    _UsuarioOpcion? conductor;
    _UsuarioOpcion? ayudante;
    _UsuarioOpcion? ayudante2;
    String? placa;
    RutaDoc? destino;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Relevo de personal'),
          content: SizedBox(
            width: math.min(MediaQuery.of(ctx).size.width * 0.92, 560.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<_UsuarioOpcion>(
                    initialValue: conductor,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Conductor del relevo',
                    ),
                    items: conductores
                        .map(
                          (u) => DropdownMenuItem(
                            value: u,
                            child: Text(
                              u.nombre,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() => conductor = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<_UsuarioOpcion>(
                    initialValue: ayudante,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Ayudante (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<_UsuarioOpcion>(
                        value: null,
                        child: Text('— Sin ayudante —'),
                      ),
                      ...ayudantes.map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(
                            u.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setLocal(() => ayudante = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<_UsuarioOpcion>(
                    initialValue: ayudante2,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Segundo ayudante (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<_UsuarioOpcion>(
                        value: null,
                        child: Text('— Sin segundo ayudante —'),
                      ),
                      ...ayudantes.map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(
                            u.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setLocal(() => ayudante2 = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: placa,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Placa / vehículo (opcional)',
                      helperText: placas.isEmpty
                          ? 'Agrega placas en Configuración inicial.'
                          : null,
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('— Sin placa —'),
                      ),
                      ...placas.map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(p, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) => setLocal(() => placa = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<RutaDoc>(
                    initialValue: destino,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Ruta destino',
                    ),
                    items: rutasActivas.map((r) {
                      final ocup = porRuta[r.id];
                      final estado = ocup == null
                          ? 'LIBRE'
                          : _conductorLabel(ocup);
                      return DropdownMenuItem(
                        value: r,
                        child: Text(
                          '${r.codigo} · $estado',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setLocal(() => destino = v),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Se moverá al personal elegido a esa ruta y se liberará '
                    'cualquier ruta donde estuviera. Se conserva el histórico.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kRutasColor),
              onPressed:
                  conductor == null ||
                      destino == null ||
                      _mismaPersona(conductor, ayudante) ||
                      _mismaPersona(conductor, ayudante2) ||
                      _mismaPersona(ayudante, ayudante2)
                  ? null
                  : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Aplicar relevo'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || conductor == null || destino == null) return;
    try {
      await _service.relevarPersonalARuta(
        destino: destino!,
        empresaId: widget.empresaId,
        conductorCedula: conductor!.userId,
        conductorNombre: conductor!.nombre,
        ayudanteCedula: ayudante?.userId ?? '',
        ayudanteNombre: ayudante?.nombre ?? '',
        ayudante2Cedula: ayudante2?.userId ?? '',
        ayudante2Nombre: ayudante2?.nombre ?? '',
        vehiculo: placa ?? '',
        asignadoPor: widget.adminUserId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Relevo aplicado: ${conductor!.nombre} → ${destino!.codigo}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo aplicar relevo: $e')));
    }
  }

  Set<String> _usuariosOcupadosEnOtrasRutas(
    List<RutaAsignacionDoc> asignaciones,
    String rutaActualId,
  ) {
    final out = <String>{};
    for (final asignacion in asignaciones) {
      if (asignacion.rutaId == rutaActualId) continue;
      for (final id in [
        asignacion.conductorCedula,
        asignacion.ayudanteCedula,
        asignacion.ayudante2Cedula,
      ]) {
        final normalizado = _normalizarLlaveAsignacion(id);
        if (normalizado.isNotEmpty) out.add(normalizado);
      }
    }
    return out;
  }

  bool _usuarioOcupado(_UsuarioOpcion usuario, Set<String> ocupados) {
    return ocupados.contains(_normalizarLlaveAsignacion(usuario.userId)) ||
        ocupados.contains(_normalizarLlaveAsignacion(usuario.cedula));
  }

  Set<String> _placasOcupadasEnOtrasRutas(
    List<RutaAsignacionDoc> asignaciones,
    String rutaActualId,
  ) {
    final out = <String>{};
    for (final a in asignaciones) {
      if (a.rutaId == rutaActualId) continue;
      final placa = a.vehiculo.trim().toUpperCase();
      if (placa.isNotEmpty) out.add(placa);
    }
    return out;
  }

  String _normalizarLlaveAsignacion(String value) {
    return value.trim().toLowerCase();
  }

  bool _mismaPersona(_UsuarioOpcion? a, _UsuarioOpcion? b) {
    if (a == null || b == null) return false;
    final idsA = {
      _normalizarLlaveAsignacion(a.userId),
      _normalizarLlaveAsignacion(a.cedula),
    }..remove('');
    return idsA.contains(_normalizarLlaveAsignacion(b.userId)) ||
        idsA.contains(_normalizarLlaveAsignacion(b.cedula));
  }

  List<_UsuarioOpcion> _withActual(
    List<_UsuarioOpcion> base,
    _UsuarioOpcion? actual,
  ) {
    final out = [...base];
    if (actual != null &&
        !out.any(
          (u) => u.userId == actual.userId || u.cedula == actual.cedula,
        )) {
      out.insert(0, actual);
    }
    return out;
  }

  _UsuarioOpcion? _matchUsuario(List<_UsuarioOpcion> usuarios, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final u in usuarios) {
      if (u.userId == id || u.cedula == id) return u;
    }
    return null;
  }

  Future<void> _liberar(RutaDoc ruta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Liberar ${ruta.codigo}'),
        content: const Text(
          'Se cerrará la asignación vigente (queda en el histórico). '
          '¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Liberar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.liberarRuta(widget.empresaId, ruta.id);
  }

  Future<void> _verHistorial(RutaDoc ruta) async {
    final hist = await _service.historialAsignaciones(
      widget.empresaId,
      ruta.id,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Histórico — ${ruta.codigo}'),
        content: SizedBox(
          width: 420,
          child: hist.isEmpty
              ? const Text('Sin asignaciones registradas.')
              : ListView(
                  shrinkWrap: true,
                  children: hist.map((a) {
                    final desde = DateFormat(
                      'dd/MM/yyyy',
                    ).format(a.vigenteDesde.toDate());
                    final hasta = a.vigenteHasta == null
                        ? 'vigente'
                        : DateFormat(
                            'dd/MM/yyyy',
                          ).format(a.vigenteHasta!.toDate());
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        a.activa ? Icons.play_circle : Icons.history,
                        color: a.activa ? kRutasColor : Colors.grey,
                      ),
                      title: Text(
                        a.conductorNombre.isEmpty
                            ? a.conductorCedula
                            : a.conductorNombre,
                      ),
                      subtitle: Text(
                        '$desde → $hasta'
                        '${_ayudanteLabel(a) == '—' ? '' : ' · Ayudantes: ${_ayudanteLabel(a)}'}'
                        '${a.vehiculo.isEmpty ? '' : ' · ${a.vehiculo}'}',
                      ),
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RutaDoc>>(
      stream: _service.streamRutas(widget.empresaId),
      builder: (context, rutasSnap) {
        if (!rutasSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rutas = rutasSnap.data!
            .where((r) => r.activa && r.stops.isNotEmpty)
            .toList();
        if (rutas.isEmpty) {
          return const _EmptyHint(
            icon: Icons.assignment_ind,
            titulo: 'No hay rutas',
            detalle:
                'Crea una ruta activa con al menos un establecimiento antes de asignar personal.',
          );
        }
        return StreamBuilder<List<RutaAsignacionDoc>>(
          stream: _service.streamAsignacionesActivas(widget.empresaId),
          builder: (context, asigSnap) {
            final porRuta = <String, RutaAsignacionDoc>{};
            for (final a in asigSnap.data ?? const <RutaAsignacionDoc>[]) {
              // Si el conductor quedó inhabilitado en Talento Humano la ruta
              // vuelve a "Pendiente": no se muestra personal retirado.
              if (_estaInhabilitado(a.conductorCedula)) continue;
              porRuta[a.rutaId] = a;
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 780) {
                  return _asignacionesCompactas(rutas, porRuta);
                }
                return _asignacionesTabla(rutas, porRuta, constraints.maxWidth);
              },
            );
          },
        );
      },
    );
  }

  Widget _asignacionesTabla(
    List<RutaDoc> rutas,
    Map<String, RutaAsignacionDoc> porRuta,
    double maxWidth,
  ) {
    final asignadas = rutas.where((r) => porRuta[r.id] != null).length;
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Asignaciones por ruta',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Chip(
                  avatar: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: Text('$asignadas asignadas'),
                ),
                Chip(
                  avatar: const Icon(Icons.pending_actions, size: 18),
                  label: Text('${rutas.length - asignadas} pendientes'),
                ),
                OutlinedButton.icon(
                  onPressed: rutas.isEmpty
                      ? null
                      : () => _abrirRelevo(rutas, porRuta),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Relevo'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: math.max(maxWidth - 24, 1120),
                ),
                child: PagedDataTable(
                  etiqueta: 'registros',
                  tabla: DataTable(
                    headingRowColor: WidgetStatePropertyAll(
                      kRutasColor.withOpacity(0.08),
                    ),
                    columnSpacing: 18,
                    horizontalMargin: 12,
                    dataRowMinHeight: 58,
                    dataRowMaxHeight: 76,
                    columns: const [
                      DataColumn(label: Text('Ruta')),
                      DataColumn(label: Text('Establecimientos')),
                      DataColumn(label: Text('Conductor')),
                      DataColumn(label: Text('Ayudante')),
                      DataColumn(label: Text('Placa')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: [
                      for (final ruta in rutas)
                        _asignacionRow(ruta, porRuta[ruta.id]),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _asignacionRow(RutaDoc ruta, RutaAsignacionDoc? asig) {
    return DataRow(
      color: WidgetStateProperty.resolveWith(
        (_) => asig == null ? Colors.orange.withOpacity(0.03) : null,
      ),
      cells: [
        DataCell(
          SizedBox(
            width: 150,
            child: Text(
              ruta.codigo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        DataCell(
          Tooltip(
            message: ruta.stops.map((s) => s.nombre).join('\n'),
            child: SizedBox(
              width: 240,
              child: Text(
                _establecimientosResumen(ruta),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 190,
            child: Text(
              _conductorLabel(asig),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: asig == null ? Colors.orange.shade800 : null,
                fontWeight: asig == null ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 180,
            child: Text(
              _ayudanteLabel(asig),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 90,
            child: Text(
              asig?.vehiculo.trim().isNotEmpty == true ? asig!.vehiculo : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(_estadoAsignacionChip(asig != null)),
        DataCell(_accionesAsignacion(ruta, asig, compact: true)),
      ],
    );
  }

  Widget _asignacionesCompactas(
    List<RutaDoc> rutas,
    Map<String, RutaAsignacionDoc> porRuta,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: rutas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final ruta = rutas[i];
        final asig = porRuta[ruta.id];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: kRutasColor.withOpacity(0.15),
                      foregroundColor: kRutasColor,
                      child: Text(ruta.numero == 9999 ? 'R' : '${ruta.numero}'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        ruta.codigo,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    _estadoAsignacionChip(asig != null),
                  ],
                ),
                const SizedBox(height: 8),
                _kv('Establec.', _establecimientosResumen(ruta)),
                _kv('Conductor', _conductorLabel(asig)),
                if (asig != null) ...[
                  _kv('Ayudante', _ayudanteLabel(asig)),
                  _kv(
                    'Vehículo',
                    asig.vehiculo.trim().isEmpty ? '—' : asig.vehiculo,
                  ),
                ],
                const SizedBox(height: 4),
                _accionesAsignacion(ruta, asig),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _accionesAsignacion(
    RutaDoc ruta,
    RutaAsignacionDoc? asig, {
    bool compact = false,
  }) {
    if (compact) {
      return Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: asig == null ? 'Asignar' : 'Cambiar',
            onPressed: () => _asignar(ruta, asig),
            icon: const Icon(Icons.edit_outlined),
          ),
          if (asig != null)
            IconButton(
              tooltip: 'Liberar',
              onPressed: () => _liberar(ruta),
              icon: const Icon(Icons.lock_open),
            ),
          IconButton(
            tooltip: 'Histórico',
            onPressed: () => _verHistorial(ruta),
            icon: const Icon(Icons.history),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      children: [
        TextButton.icon(
          onPressed: () => _asignar(ruta, asig),
          icon: const Icon(Icons.edit, size: 18),
          label: Text(asig == null ? 'Asignar' : 'Cambiar'),
        ),
        if (asig != null)
          TextButton.icon(
            onPressed: () => _liberar(ruta),
            icon: const Icon(Icons.lock_open, size: 18),
            label: const Text('Liberar'),
          ),
        TextButton.icon(
          onPressed: () => _verHistorial(ruta),
          icon: const Icon(Icons.history, size: 18),
          label: const Text('Histórico'),
        ),
      ],
    );
  }

  String _establecimientosResumen(RutaDoc ruta) {
    if (ruta.stops.isEmpty) return 'Sin establecimientos';
    final nombres = ruta.stops.map((s) => s.nombre.trim()).toList();
    if (nombres.length <= 2) return nombres.join(' · ');
    return '${nombres.take(2).join(' · ')} +${nombres.length - 2} más';
  }

  String _conductorLabel(RutaAsignacionDoc? asig) {
    if (asig == null) return 'Sin asignar';
    return asig.conductorNombre.isEmpty
        ? asig.conductorCedula
        : asig.conductorNombre;
  }

  String _ayudanteLabel(RutaAsignacionDoc? asig) {
    if (asig == null) return '—';
    final nombres = <String>[];
    if (!_estaInhabilitado(asig.ayudanteCedula)) {
      final primero = asig.ayudanteNombre.isNotEmpty
          ? asig.ayudanteNombre
          : asig.ayudanteCedula;
      if (primero.isNotEmpty) nombres.add(primero);
    }
    if (!_estaInhabilitado(asig.ayudante2Cedula)) {
      final segundo = asig.ayudante2Nombre.isNotEmpty
          ? asig.ayudante2Nombre
          : asig.ayudante2Cedula;
      if (segundo.isNotEmpty) nombres.add(segundo);
    }
    return nombres.isEmpty ? '—' : nombres.join(' · ');
  }

  Widget _estadoAsignacionChip(bool asignada) {
    final color = asignada ? kRutasColor : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        asignada ? 'Asignada' : 'Pendiente',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            '$k:',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// CONSOLA CALIDAD (web + móvil responsive): revisión y aprobación de evidencias
// ══════════════════════════════════════════════════════════════════════════════

class _CalidadHome extends StatefulWidget {
  final String userId;
  final String empresaId;
  final bool puedeEliminar;

  const _CalidadHome({
    required this.userId,
    required this.empresaId,
    this.puedeEliminar = false,
  });

  @override
  State<_CalidadHome> createState() => _CalidadHomeState();
}

class _CalidadHomeState extends State<_CalidadHome>
    with SingleTickerProviderStateMixin {
  final _service = RutasService();
  late final TabController _tabController;
  int _tabIndex = 0;

  DateTime? _fecha = DateTime.now(); // "Hoy" por defecto
  String? _estado = kEvidPendiente; // pendientes por aprobar por defecto
  String? _comida;
  String? _rutaId;

  List<RutaDoc> _rutas = [];
  RutaConfigDoc? _config;
  String _revisorNombre = '';

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );
  bool _generando = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging &&
            _tabIndex != _tabController.index) {
          setState(() => _tabIndex = _tabController.index);
        }
      });
    _cargarBase();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarBase() async {
    try {
      final rutas = await _service.getRutas(widget.empresaId);
      final cfg = await _service.getConfig(widget.empresaId);
      var nombre = widget.userId;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .doc(widget.userId)
            .get();
        final m = doc.data();
        if (m != null) {
          final n = [
            (m['nombres'] ?? '').toString().trim(),
            (m['apellidos'] ?? '').toString().trim(),
          ].where((e) => e.isNotEmpty).join(' ');
          if (n.isNotEmpty) nombre = n;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _rutas = rutas;
        _config = cfg;
        _revisorNombre = nombre;
      });
    } catch (_) {}
  }

  bool get _esHoy {
    final f = _fecha;
    if (f == null) return false;
    final n = DateTime.now();
    return f.year == n.year && f.month == n.month && f.day == n.day;
  }

  Future<void> _pickFecha() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2030, 12, 31),
      initialDate: _fecha ?? DateTime.now(),
    );
    if (d != null) setState(() => _fecha = d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kRutasColor,
        foregroundColor: Colors.white,
        title: const Text('Rutas — Revisión (Calidad)'),
        actions: [
          if (_generando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.fact_check_outlined), text: 'Evidencias'),
            Tab(icon: Icon(Icons.assignment_ind), text: 'Asignaciones'),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _tabIndex == 0 ? _accionesExportar() : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          Column(
            children: [
              _filtros(),
              const Divider(height: 1),
              Expanded(child: _grid()),
            ],
          ),
          _CalidadAsignacionesView(
            empresaId: widget.empresaId,
            rutas: _rutas,
            initialFecha: _fecha ?? DateTime.now(),
          ),
        ],
      ),
    );
  }

  Widget _accionesExportar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.extended(
          heroTag: 'rutas_pdf',
          backgroundColor: kRutasColor,
          foregroundColor: Colors.white,
          onPressed: _generando ? null : _seleccionarInforme,
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('PDF'),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'rutas_zip',
          backgroundColor: Colors.blueGrey.shade700,
          foregroundColor: Colors.white,
          onPressed: _generando ? null : _generarZip,
          icon: const Icon(Icons.folder_zip),
          label: const Text('ZIP'),
        ),
      ],
    );
  }

  Future<void> _seleccionarInforme() async {
    final rango = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Informe diario'),
              onTap: () => Navigator.pop(ctx, 'diario'),
            ),
            ListTile(
              leading: const Icon(Icons.view_week_outlined),
              title: const Text('Informe semanal'),
              onTap: () => Navigator.pop(ctx, 'semanal'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Informe mensual'),
              onTap: () => Navigator.pop(ctx, 'mensual'),
            ),
          ],
        ),
      ),
    );
    if (rango != null) await _generarInforme(rango);
  }

  Future<void> _generarInforme(String rango) async {
    final base = _fecha ?? DateTime.now();
    DateTime desde;
    DateTime hasta;
    switch (rango) {
      case 'semanal':
        hasta = base;
        desde = base.subtract(const Duration(days: 6));
        break;
      case 'mensual':
        desde = DateTime(base.year, base.month, 1);
        hasta = DateTime(base.year, base.month + 1, 0);
        break;
      default: // diario
        desde = base;
        hasta = base;
    }
    setState(() => _generando = true);
    try {
      final res = await _functions.httpsCallable('rutasGenerarInforme').call({
        'empresaId': widget.empresaId,
        'fechaDesde': RutasLogic.fechaKey(desde),
        'fechaHasta': RutasLogic.fechaKey(hasta),
        'rutaId': _rutaId,
        'titulo':
            'Informe de Rutas (${rango[0].toUpperCase()}${rango.substring(1)})',
      });
      final url = (res.data as Map?)?['url']?.toString();
      if (url != null && url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        _snack('No hay datos para el informe en ese periodo.');
      }
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'No se pudo generar el informe.');
    } catch (e) {
      _snack('No se pudo generar el informe: $e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _generarZip() async {
    setState(() => _generando = true);
    try {
      final res = await _functions.httpsCallable('rutasGenerarZip').call({
        'empresaId': widget.empresaId,
        'fecha': _fecha == null ? null : RutasLogic.fechaKey(_fecha!),
        'estado': _estado,
        'comida': _comida,
        'rutaId': _rutaId,
      });
      final data = res.data as Map?;
      final url = data?['url']?.toString();
      final total = data?['total'];
      if (url != null && url.isNotEmpty) {
        _snack('ZIP listo ($total fotos). Abriendo…');
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        _snack('No hay fotos para generar el ZIP con los filtros actuales.');
      }
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'No se pudo generar el ZIP.');
    } catch (e) {
      _snack('No se pudo generar el ZIP: $e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Widget _filtros() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ChoiceChip(
            label: const Text('Hoy'),
            selected: _esHoy,
            selectedColor: kRutasColor.withOpacity(0.2),
            onSelected: (_) => setState(() => _fecha = DateTime.now()),
          ),
          ChoiceChip(
            label: const Text('Todas las fechas'),
            selected: _fecha == null,
            selectedColor: kRutasColor.withOpacity(0.2),
            onSelected: (_) => setState(() => _fecha = null),
          ),
          OutlinedButton.icon(
            onPressed: _pickFecha,
            icon: const Icon(Icons.event, size: 18),
            label: Text(
              _fecha == null
                  ? 'Elegir fecha'
                  : DateFormat('dd/MM/yyyy').format(_fecha!),
            ),
          ),
          _dropdown<String?>(
            label: 'Estado',
            value: _estado,
            items: {
              null: 'Todos',
              for (final e in kEvidEstados) e: kEvidEstadoLabels[e] ?? e,
            },
            onChanged: (v) => setState(() => _estado = v),
          ),
          _dropdown<String?>(
            label: 'Comida',
            value: _comida,
            items: {
              null: 'Todas',
              for (final c in kComidasOrden) c: (c == kComidaCena ? 'Cena' : c),
            },
            onChanged: (v) => setState(() => _comida = v),
          ),
          _dropdown<String?>(
            label: 'Ruta',
            value: _rutaId,
            items: {null: 'Todas', for (final r in _rutas) r.id: r.codigo},
            onChanged: (v) => setState(() => _rutaId = v),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          border: const OutlineInputBorder(),
        ),
        items: items.entries
            .map(
              (e) => DropdownMenuItem<T>(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _grid() {
    return StreamBuilder<List<RutaEvidenciaDoc>>(
      stream: _service.streamEvidencias(
        empresaId: widget.empresaId,
        fecha: _fecha == null ? null : RutasLogic.fechaKey(_fecha!),
        estado: _estado,
        comida: _comida,
        rutaId: _rutaId,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final evid = snap.data!;
        if (evid.isEmpty) {
          return const _EmptyHint(
            icon: Icons.photo_library_outlined,
            titulo: 'Sin evidencias',
            detalle: 'No hay fotos para los filtros seleccionados.',
          );
        }
        return LayoutBuilder(
          builder: (_, c) {
            final w = c.maxWidth;
            int cols = 2;
            if (w >= 1400) {
              cols = 6;
            } else if (w >= 1100) {
              cols = 5;
            } else if (w >= 850) {
              cols = 4;
            } else if (w >= 600) {
              cols = 3;
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.72,
              ),
              itemCount: evid.length,
              itemBuilder: (_, i) => _RevCard(
                evidencia: evid[i],
                onTap: () => _abrirEvidencia(evid[i]),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _abrirEvidencia(RutaEvidenciaDoc e) async {
    final cfg = _config;
    final fueraDeRango =
        cfg != null &&
        e.distanciaMetros >= 0 &&
        e.distanciaMetros > cfg.radioValidacionMetros;
    final captura = e.createdAt.toDate();
    final fecha = DateFormat('dd/MM/yyyy').format(captura);
    final horaCaptura = DateFormat('HH:mm:ss').format(captura);
    final ventana = cfg?.ventanaDe(e.comida);
    final tiempoDesdeInicio = ventana == null
        ? ''
        : _tiempoDesdeInicioVentana(captura, ventana.desde);
    var quarterTurns = 0;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final size = MediaQuery.of(ctx).size;
          final url = e.downloadURL ?? '';

          Widget imagePane() => Container(
            color: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.7,
                    maxScale: 5,
                    child: Center(
                      child: url.isEmpty
                          ? const Icon(
                              Icons.broken_image,
                              size: 72,
                              color: Colors.white70,
                            )
                          : Image.network(
                              url,
                              fit: BoxFit.contain,
                              frameBuilder:
                                  (
                                    context,
                                    child,
                                    frame,
                                    wasSynchronouslyLoaded,
                                  ) => RotatedBox(
                                    quarterTurns: quarterTurns,
                                    child: child,
                                  ),
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const CircularProgressIndicator(
                                  color: Colors.white,
                                );
                              },
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image,
                                size: 72,
                                color: Colors.white70,
                              ),
                            ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Rotar imagen',
                        onPressed: url.isEmpty
                            ? null
                            : () => setLocal(
                                () => quarterTurns = (quarterTurns + 1) % 4,
                              ),
                        icon: const Icon(Icons.rotate_90_degrees_cw),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Ver imagen grande',
                        onPressed: url.isEmpty
                            ? null
                            : () => _abrirImagenGrande(
                                e,
                                initialQuarterTurns: quarterTurns,
                              ),
                        icon: const Icon(Icons.open_in_full),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          Widget detailsPane() => Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${e.rutaCodigo} · ${e.paradaNombre}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _RevEstadoChip(estado: e.estado),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _row('Comida', '${e.comida} · Menú ${e.menuNumero}'),
                      _row(
                        'Conductor',
                        e.conductorNombre.isEmpty
                            ? e.conductorCedula
                            : e.conductorNombre,
                      ),
                      if (e.ayudanteNombre.isNotEmpty)
                        _row('Ayudante', e.ayudanteNombre),
                      if (e.ayudante2Nombre.isNotEmpty)
                        _row('Segundo ayudante', e.ayudante2Nombre),
                      if (e.vehiculo.isNotEmpty) _row('Vehículo', e.vehiculo),
                      _row('Fecha', fecha),
                      _row('Hora captura', horaCaptura),
                      if (ventana != null)
                        _row('Ventana', '${ventana.desde} a ${ventana.hasta}'),
                      if (tiempoDesdeInicio.isNotEmpty)
                        _row('Tiempo', tiempoDesdeInicio),
                      if (e.capturaLat != null && e.capturaLng != null)
                        _row(
                          'GPS',
                          '${e.capturaLat!.toStringAsFixed(5)}, ${e.capturaLng!.toStringAsFixed(5)}',
                        ),
                      if (e.distanciaMetros >= 0)
                        _row(
                          'Distancia',
                          '${e.distanciaMetros.toStringAsFixed(0)} m'
                              '${fueraDeRango ? '  FUERA DE RANGO' : ''}',
                          valueColor: fueraDeRango ? Colors.red : null,
                        ),
                      if (e.rechazada && e.motivoRechazo.isNotEmpty)
                        _row(
                          'Motivo rechazo',
                          e.motivoRechazo,
                          valueColor: Colors.red,
                        ),
                      if (e.aprobada && e.revisadoPor.isNotEmpty)
                        _row('Revisado por', e.revisadoPor),
                      if (e.revisadoEn != null)
                        _row(
                          'Hora revisión',
                          DateFormat(
                            'dd/MM/yyyy HH:mm:ss',
                          ).format(e.revisadoEn!.toDate()),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cerrar'),
                      ),
                      if (widget.puedeEliminar)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _eliminarEvidencia(e);
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Eliminar'),
                        ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: e.rechazada
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _rechazar(e);
                              },
                        icon: const Icon(Icons.close),
                        label: const Text('Rechazar'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        onPressed: e.aprobada
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _aprobar(e);
                              },
                        icon: const Icon(Icons.check),
                        label: const Text('Aprobar'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );

          return Dialog(
            clipBehavior: Clip.antiAlias,
            insetPadding: EdgeInsets.symmetric(
              horizontal: size.width >= 700 ? 24 : 8,
              vertical: 14,
            ),
            child: SizedBox(
              width: math.min(size.width - 16, 1180.0),
              height: size.height * 0.92,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 860;
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(flex: 7, child: imagePane()),
                        SizedBox(width: 390, child: detailsPane()),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(flex: 5, child: imagePane()),
                      Expanded(flex: 4, child: detailsPane()),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _abrirImagenGrande(
    RutaEvidenciaDoc e, {
    int initialQuarterTurns = 0,
  }) async {
    final url = e.downloadURL ?? '';
    if (url.isEmpty) return;
    var quarterTurns = initialQuarterTurns % 4;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  maxScale: 6,
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: quarterTurns,
                      child: Image.network(url, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: Wrap(
                  spacing: 8,
                  children: [
                    IconButton.filled(
                      tooltip: 'Rotar imagen',
                      onPressed: () =>
                          setLocal(() => quarterTurns = (quarterTurns + 1) % 4),
                      icon: const Icon(Icons.rotate_90_degrees_cw),
                    ),
                    IconButton.filled(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _aprobar(RutaEvidenciaDoc e) async {
    try {
      await _service.aprobarEvidencia(
        evidenciaId: e.id,
        revisadoPor: widget.userId,
      );
      if (_estado == kEvidPendiente && mounted) {
        setState(() => _estado = null);
      }
      _snack('Evidencia aprobada: ${e.paradaNombre} · ${e.comida}');
    } catch (err) {
      _snack('Error al aprobar: $err');
    }
  }

  Future<void> _rechazar(RutaEvidenciaDoc e) async {
    final ctrl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar evidencia'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motivo del rechazo',
            hintText: 'Ej: foto borrosa, no se ve el establecimiento, etc.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (motivo == null || motivo.isEmpty) return;
    try {
      await _service.rechazarEvidencia(
        evidencia: e,
        revisadoPor: widget.userId,
        revisadoPorNombre: _revisorNombre,
        motivo: motivo,
      );
      _snack('Evidencia rechazada. Se notificó a quien subió la foto.');
    } catch (err) {
      _snack('Error al rechazar: $err');
    }
  }

  Future<void> _eliminarEvidencia(RutaEvidenciaDoc e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar evidencia'),
        content: Text(
          'Se borrara la foto y el registro de ${e.paradaNombre} · ${e.comida}. '
          'Esta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.eliminarEvidencia(e);
      _snack('Evidencia eliminada: ${e.paradaNombre} · ${e.comida}');
    } catch (err) {
      _snack('Error al eliminar evidencia: $err');
    }
  }

  String _tiempoDesdeInicioVentana(DateTime captura, String desde) {
    final parts = desde.split(':');
    if (parts.length != 2) return '';
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return '';
    final inicio = DateTime(
      captura.year,
      captura.month,
      captura.day,
      hour,
      minute,
    );
    final minutos = captura.difference(inicio).inMinutes;
    if (minutos < 0) return '${minutos.abs()} min antes de la ventana';
    if (minutos < 60) return '$minutos min desde el inicio';
    final horas = minutos ~/ 60;
    final resto = minutos % 60;
    return resto == 0
        ? '$horas h desde el inicio'
        : '$horas h $resto min desde el inicio';
  }

  Widget _row(String k, String v, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            '$k:',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(v, style: TextStyle(color: valueColor)),
        ),
      ],
    ),
  );

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _CalidadAsignacionesView extends StatefulWidget {
  final String empresaId;
  final List<RutaDoc> rutas;
  final DateTime initialFecha;

  const _CalidadAsignacionesView({
    required this.empresaId,
    required this.rutas,
    required this.initialFecha,
  });

  @override
  State<_CalidadAsignacionesView> createState() =>
      _CalidadAsignacionesViewState();
}

class _CalidadAsignacionesViewState extends State<_CalidadAsignacionesView> {
  final _service = RutasService();
  late DateTime _fecha;
  String? _rutaId;
  bool _loading = true;
  List<RutaAsignacionDoc> _asignacionesFecha = [];
  List<RutaAsignacionDoc> _historial = [];

  @override
  void initState() {
    super.initState();
    _fecha = DateTime(
      widget.initialFecha.year,
      widget.initialFecha.month,
      widget.initialFecha.day,
    );
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final asignaciones = await _service.asignacionesEnFecha(
        empresaId: widget.empresaId,
        fecha: _fecha,
      );
      final historial = await _service.getAsignacionesEmpresa(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _asignacionesFecha = asignaciones;
        _historial = historial;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar asignaciones: $e')),
      );
    }
  }

  Future<void> _pickFecha() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2030, 12, 31),
      initialDate: _fecha,
    );
    if (d == null) return;
    setState(() => _fecha = DateTime(d.year, d.month, d.day));
    await _cargar();
  }

  Map<String, RutaAsignacionDoc> get _porRutaEnFecha {
    final map = <String, RutaAsignacionDoc>{};
    for (final a in _asignacionesFecha) {
      final actual = map[a.rutaId];
      if (actual == null ||
          a.vigenteDesde.toDate().isAfter(actual.vigenteDesde.toDate())) {
        map[a.rutaId] = a;
      }
    }
    return map;
  }

  List<RutaDoc> get _rutasVisibles {
    final list = widget.rutas
        .where(
          (r) =>
              r.stops.isNotEmpty ||
              _historial.any((a) => a.rutaId == r.id) ||
              _asignacionesFecha.any((a) => a.rutaId == r.id),
        )
        .where((r) => _rutaId == null || r.id == _rutaId)
        .toList();
    list.sort((a, b) => a.numero.compareTo(b.numero));
    return list;
  }

  bool _cubreFecha(RutaAsignacionDoc a) {
    final inicio = DateTime(_fecha.year, _fecha.month, _fecha.day);
    final fin = inicio.add(const Duration(days: 1));
    final desde = a.vigenteDesde.toDate();
    final hasta = a.vigenteHasta?.toDate();
    return desde.isBefore(fin) && (hasta == null || !hasta.isBefore(inicio));
  }

  String _fmtPeriodo(RutaAsignacionDoc a) {
    final desde = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(a.vigenteDesde.toDate());
    final hasta = a.vigenteHasta == null
        ? 'vigente'
        : DateFormat('dd/MM/yyyy HH:mm').format(a.vigenteHasta!.toDate());
    return '$desde -> $hasta';
  }

  String _establecimientosResumen(RutaDoc ruta) {
    if (ruta.stops.isEmpty) return 'Sin establecimientos';
    final nombres = ruta.stops.map((s) => s.nombre.trim()).toList();
    if (nombres.length <= 2) return nombres.join(' · ');
    return '${nombres.take(2).join(' · ')} +${nombres.length - 2} más';
  }

  String _conductorLabel(RutaAsignacionDoc? asig) {
    if (asig == null) return 'Sin asignación';
    return asig.conductorNombre.isEmpty
        ? asig.conductorCedula
        : asig.conductorNombre;
  }

  String _ayudanteLabel(RutaAsignacionDoc? asig) {
    if (asig == null) return '-';
    final nombres = <String>[
      if (asig.ayudanteNombre.isNotEmpty)
        asig.ayudanteNombre
      else if (asig.ayudanteCedula.isNotEmpty)
        asig.ayudanteCedula,
      if (asig.ayudante2Nombre.isNotEmpty)
        asig.ayudante2Nombre
      else if (asig.ayudante2Cedula.isNotEmpty)
        asig.ayudante2Cedula,
    ];
    return nombres.isEmpty ? '-' : nombres.join(' · ');
  }

  Widget _estadoChip(RutaAsignacionDoc? asig) {
    final color = asig == null ? Colors.orange : kRutasColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        asig == null ? 'Sin asignación' : 'Asignada',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _verHistorial(RutaDoc ruta) async {
    final hist = _historial.where((a) => a.rutaId == ruta.id).toList()
      ..sort((a, b) => b.vigenteDesde.compareTo(a.vigenteDesde));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Histórico — ${ruta.codigo}'),
        content: SizedBox(
          width: math.min(MediaQuery.of(ctx).size.width * 0.92, 620.0),
          height: math.min(MediaQuery.of(ctx).size.height * 0.7, 520.0),
          child: hist.isEmpty
              ? const Text('Esta ruta no tiene historial de asignaciones.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fecha consultada: ${DateFormat('dd/MM/yyyy').format(_fecha)}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: hist.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final a = hist[i];
                          final cubre = _cubreFecha(a);
                          return ListTile(
                            leading: Icon(
                              cubre ? Icons.check_circle : Icons.history,
                              color: cubre ? kRutasColor : Colors.grey,
                            ),
                            title: Text(
                              _conductorLabel(a),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${_fmtPeriodo(a)}\n'
                              'Ayudante: ${_ayudanteLabel(a)}'
                              '${a.vehiculo.trim().isEmpty ? '' : ' · Placa: ${a.vehiculo}'}',
                            ),
                            isThreeLine: true,
                            trailing: cubre
                                ? const Chip(label: Text('En fecha'))
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    final asignadas = _rutasVisibles
        .where((r) => _porRutaEnFecha[r.id] != null)
        .length;
    final pendientes = _rutasVisibles.length - asignadas;
    final routeIds = widget.rutas.map((r) => r.id).toSet();
    final routeValue = _rutaId != null && routeIds.contains(_rutaId)
        ? _rutaId
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _pickFecha,
            icon: const Icon(Icons.event, size: 18),
            label: Text(DateFormat('dd/MM/yyyy').format(_fecha)),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: routeValue,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Ruta',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todas'),
                ),
                for (final ruta in widget.rutas)
                  DropdownMenuItem<String?>(
                    value: ruta.id,
                    child: Text(ruta.codigo, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _rutaId = v),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _loading ? null : _cargar,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: const Text('Actualizar'),
          ),
          Chip(
            avatar: const Icon(Icons.assignment_turned_in_outlined, size: 18),
            label: Text('$asignadas asignadas'),
          ),
          Chip(
            avatar: const Icon(Icons.pending_actions, size: 18),
            label: Text('$pendientes sin asignación'),
          ),
        ],
      ),
    );
  }

  Widget _tabla() {
    final rutas = _rutasVisibles;
    final porRuta = _porRutaEnFecha;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rutas.isEmpty) {
      return const _EmptyHint(
        icon: Icons.assignment_ind,
        titulo: 'Sin rutas',
        detalle: 'No hay rutas para consultar con el filtro seleccionado.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: math.max(constraints.maxWidth - 24, 1120),
                ),
                child: PagedDataTable(
                  etiqueta: 'registros',
                  tabla: DataTable(
                    headingRowColor: WidgetStatePropertyAll(
                      kRutasColor.withOpacity(0.08),
                    ),
                    columnSpacing: 18,
                    horizontalMargin: 12,
                    dataRowMinHeight: 58,
                    dataRowMaxHeight: 82,
                    columns: const [
                      DataColumn(label: Text('Ruta')),
                      DataColumn(label: Text('Establecimientos')),
                      DataColumn(label: Text('Conductor')),
                      DataColumn(label: Text('Ayudante')),
                      DataColumn(label: Text('Placa')),
                      DataColumn(label: Text('Vigencia')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Historial')),
                    ],
                    rows: [
                      for (final ruta in rutas)
                        _rowAsignacion(ruta, porRuta[ruta.id]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  DataRow _rowAsignacion(RutaDoc ruta, RutaAsignacionDoc? asig) {
    return DataRow(
      color: WidgetStateProperty.resolveWith(
        (_) => asig == null ? Colors.orange.withOpacity(0.03) : null,
      ),
      cells: [
        DataCell(
          SizedBox(
            width: 140,
            child: Text(
              ruta.codigo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        DataCell(
          Tooltip(
            message: ruta.stops.map((s) => s.nombre).join('\n'),
            child: SizedBox(
              width: 240,
              child: Text(
                _establecimientosResumen(ruta),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 190,
            child: Text(
              _conductorLabel(asig),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: asig == null ? Colors.orange.shade800 : null,
                fontWeight: asig == null ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 180,
            child: Text(
              _ayudanteLabel(asig),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Text(asig?.vehiculo.trim().isNotEmpty == true ? asig!.vehiculo : '-'),
        ),
        DataCell(
          SizedBox(
            width: 190,
            child: Text(
              asig == null ? '-' : _fmtPeriodo(asig),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(_estadoChip(asig)),
        DataCell(
          IconButton(
            tooltip: 'Ver historial de asignaciones',
            onPressed: () => _verHistorial(ruta),
            icon: const Icon(Icons.history),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(),
        const Divider(height: 1),
        Expanded(child: _tabla()),
      ],
    );
  }
}

class _RevCard extends StatelessWidget {
  final RutaEvidenciaDoc evidencia;
  final VoidCallback onTap;

  const _RevCard({required this.evidencia, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final url = evidencia.thumbURL ?? evidencia.downloadURL ?? '';
    final comidaColor = _colorComida(evidencia.comida);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: comidaColor, width: 3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: url.isEmpty
                  ? const ColoredBox(
                      color: Color(0x11000000),
                      child: Center(child: Icon(Icons.image_not_supported)),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0x11000000),
                        child: Center(child: Icon(Icons.broken_image)),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    evidencia.rutaCodigo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    evidencia.paradaNombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    evidencia.comida == kComidaCena ? 'Cena' : evidencia.comida,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  _RevEstadoChip(estado: evidencia.estado),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevEstadoChip extends StatelessWidget {
  final String estado;

  const _RevEstadoChip({required this.estado});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (estado) {
      case kEvidAprobada:
        color = Colors.green;
        break;
      case kEvidRechazada:
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        kEvidEstadoLabels[estado] ?? estado,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widgets auxiliares
// ══════════════════════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: kRutasColor,
      ),
    ),
  );
}

class _DiaHeader extends StatelessWidget {
  final String text;
  const _DiaHeader(this.text);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Center(
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade700,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String detalle;

  const _EmptyHint({
    required this.icon,
    required this.titulo,
    required this.detalle,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            titulo,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(detalle, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _EnConstruccion extends StatelessWidget {
  final String titulo;
  final String detalle;

  const _EnConstruccion({required this.titulo, required this.detalle});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: kRutasColor,
      foregroundColor: Colors.white,
      title: Text(titulo),
    ),
    body: _EmptyHint(
      icon: Icons.construction,
      titulo: titulo,
      detalle: detalle,
    ),
  );
}
