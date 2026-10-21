import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../login/auth_gate.dart';
import '../services/auth_prefs.dart';
import 'visitas_dashboard_screen.dart';
import 'visitas_local_service.dart';
import 'visitas_local_store.dart';
import 'visitas_models.dart';
import 'visitas_service.dart';

Future<bool> desbloquearVisitasLocal(String userId, String empresaId) async {
  final store = VisitasLocalStore.instance;
  final grant = await store.acceso();
  final auth = FirebaseAuth.instance.currentUser;
  if (grant == null ||
      grant.userId != userId ||
      grant.empresaId != empresaId ||
      !grant.vigente(DateTime.now()) ||
      (auth != null && auth.uid != grant.uid)) {
    throw const VisitasException(
      'No hay acceso local vigente para esta cuenta y empresa. Conéctate para prepararlo.',
    );
  }
  if (!await AuthPrefs.instance.authenticateBiometric(
    reason: 'Desbloquea tus visitas descargadas',
  )) {
    return false;
  }
  await store.registrarDesbloqueo(grant);
  return true;
}

Future<void> revalidarAccesoLocal(Map<String, dynamic> p) async {
  final store = VisitasLocalStore.instance;
  final revision = store.revisionAcceso;
  final auth = FirebaseAuth.instance.currentUser;
  if (auth?.uid != p['uid']) {
    throw const VisitasException(
      'Inicia sesión con la cuenta de esta descarga.',
    );
  }
  try {
    await auth!.getIdTokenResult(true).timeout(const Duration(seconds: 10));
    final r = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('visitasRevalidarOffline')
        .call({'reservaId': p['reservaId']})
        .timeout(const Duration(seconds: 10));
    if (FirebaseAuth.instance.currentUser?.uid != p['uid']) {
      throw const VisitasException('La sesión cambió durante la validación.');
    }
    await store.autorizar(
      Map<String, dynamic>.from(r.data as Map),
      revisionEsperada: revision,
    );
  } on FirebaseFunctionsException catch (e) {
    if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
      await VisitasLocalStore.instance.revocarAcceso();
    }
    rethrow;
  } on FirebaseAuthException catch (e) {
    if ([
      'user-disabled',
      'user-not-found',
      'invalid-user-token',
      'user-token-expired',
    ].contains(e.code)) {
      await VisitasLocalStore.instance.revocarAcceso();
    }
    rethrow;
  }
}

/// A network failure must not prevent using an already authorized download.
Future<void> prepararAperturaLocal(Map<String, dynamic> p) async {
  try {
    await revalidarAccesoLocal(p);
  } on TimeoutException {
    // Unlock below still checks the bounded local grant and device credential.
  } on FirebaseFunctionsException catch (e) {
    if (!['unavailable', 'deadline-exceeded'].contains(e.code)) rethrow;
  } on FirebaseAuthException catch (e) {
    if (e.code != 'network-request-failed') rethrow;
  }
}

/// Restricted offline entry: no Home, company switcher or routes to other modules.
class VisitasLocalScreen extends StatelessWidget {
  final String userId, empresaId;
  const VisitasLocalScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Visitas descargadas'),
      actions: [
        IconButton(
          tooltip: 'Bloquear',
          icon: const Icon(Icons.lock_outline),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthGate()),
              (_) => false,
            );
          },
        ),
        IconButton(
          tooltip: 'Entrar con internet',
          icon: const Icon(Icons.login),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => const AuthGate(soloOnline: true),
              ),
              (_) => false,
            );
          },
        ),
      ],
    ),
    body: SafeArea(
      child: VisitasDescargadasTab(
        userId: userId,
        empresaId: empresaId,
        local: true,
      ),
    ),
  );
}

class VisitasDescargadasTab extends StatefulWidget {
  final String userId, empresaId;
  final bool local;
  final VisitasLocalStore? store;
  const VisitasDescargadasTab({
    super.key,
    required this.userId,
    required this.empresaId,
    this.local = false,
    this.store,
  });
  @override
  State<VisitasDescargadasTab> createState() => _VisitasDescargadasTabState();
}

class _VisitasDescargadasTabState extends State<VisitasDescargadasTab> {
  late final _store = widget.store ?? VisitasLocalStore.instance;
  late Future<List<Map<String, dynamic>>> _packages;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _packages = _store.listar(widget.userId, widget.empresaId);
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) _error = _mensajeLegible(e);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _reload();
      });
    }
  }

  /// Muestra solo el motivo, sin el rastro técnico de la excepción.
  String _mensajeLegible(Object e) {
    if (e is FirebaseFunctionsException) {
      final m = (e.message ?? '').trim();
      if (m.isNotEmpty) return m;
    }
    if (e is VisitasException) return e.toString();
    return e.toString().split('\n').first.trim();
  }

  Future<void> _download() async {
    final svc = VisitasService();
    // Server preparation revalidates ownership, membership and effective role.
    final list = await svc
        .streamVisitas(widget.empresaId, profesionalId: widget.userId)
        .first
        .timeout(const Duration(seconds: 15));
    final existing = await _packages;
    final choices = list
        .where(
          (v) =>
              v.estado == kVisitaProgramada &&
              !existing.any((p) => p['visitaId'] == v.id),
        )
        .toList();
    if (!mounted) return;
    final v = await showDialog<VisitaProfesional>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descargar visita'),
        content: SizedBox(
          width: 480,
          child: choices.isEmpty
              ? const Text(
                  'No hay visitas programadas nuevas para descargar.',
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final v in choices)
                      ListTile(
                        title: Text(v.establecimiento),
                        subtitle: Text(
                          '${v.fechaProgramada.day}/${v.fechaProgramada.month}/${v.fechaProgramada.year} · ${v.areaNombre}',
                        ),
                        onTap: () => Navigator.pop(ctx, v),
                      ),
                  ],
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
    if (v == null) return;
    final cargo = await svc.cargoDe(
      empresaId: widget.empresaId,
      userId: widget.userId,
    );
    final formatos = v.formatoAsignado != null
        ? [v.formatoAsignado!]
        : await svc.formatosDeVisita(v, cargo: cargo);
    if (!mounted) return;
    final f = await showDialog<VisitaFormato>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Formato para esta visita'),
        content: SizedBox(
          width: 480,
          child: formatos.isEmpty
              ? const Text('No hay formatos disponibles para tu cargo.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in formatos)
                      ListTile(
                        title: Text(f.nombre),
                        onTap: () => Navigator.pop(ctx, f),
                      ),
                  ],
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
    if (f == null) return;
    await prepararVisitaLocal(svc, v, f);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Listo para trabajar sin conexión. También puedes entrar después de reiniciar el equipo.',
          ),
        ),
      );
    }
  }

  Future<void> _open(Map<String, dynamic> p) async {
    if (!widget.local) await prepararAperturaLocal(p);
    if (!await desbloquearVisitasLocal(widget.userId, widget.empresaId)) return;
    if (!mounted) return;
    final svc = VisitasLocalService(p);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => pantallaVisitaDescargada(svc)),
      );
    } finally {
      await svc.disposeLocal();
    }
  }

  Future<void> _sync(Map<String, dynamic> p) async {
    try {
      await sincronizarVisitaLocal(p);
    } catch (e) {
      if (e is FirebaseFunctionsException &&
          ['permission-denied', 'unauthenticated'].contains(e.code)) {
        await _store.revocarAcceso();
      }
      await _store.guardar({...p, 'error': e.toString()});
      rethrow;
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _packages,
    builder: (context, snap) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Trabaja sin conexión',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          widget.local
              ? 'Acceso local limitado a las visitas de esta cuenta y empresa. Los cambios se guardan en este equipo.'
              : 'Descarga antes de salir. El formato, las fotos y las firmas se guardan en el equipo hasta que envíes la visita finalizada. Acceso local: siete días.',
        ),
        const SizedBox(height: 12),
        if (!widget.local)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _run(_download),
              icon: const Icon(Icons.download),
              label: const Text('Preparar visita sin conexión'),
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null || snap.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error ?? 'No se pudo leer la descarga: ${snap.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (!snap.hasData && !snap.hasError)
          const Center(child: CircularProgressIndicator()),
        if (snap.hasData && snap.data!.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Todavía no hay visitas descargadas en este equipo.'),
          ),
        for (final p in snap.data ?? <Map<String, dynamic>>[]) _card(p),
      ],
    ),
  );
  Widget _card(Map<String, dynamic> p) {
    final v = VisitaProfesional.fromMap(
      p['visitaId'],
      Map<String, dynamic>.from(p['visita']),
    );
    final sent = p['sincronizada'] == true;
    final done = v.estado == kVisitaTerminada;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              v.establecimiento,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              '${v.areaNombre} · ${v.fechaProgramada.day}/${v.fechaProgramada.month}/${v.fechaProgramada.year}',
            ),
            const SizedBox(height: 8),
            Text(
              sent
                  ? 'Sincronizada y confirmada por el servidor'
                  : done
                  ? 'Finalizada en el equipo · pendiente de enviar'
                  : v.estado == kVisitaEnCurso
                  ? 'En curso · guardada en este equipo'
                  : 'Preparada para trabajar sin conexión',
            ),
            if (p['error'] != null)
              Text(
                p['error'].toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(() => _open(p)),
                  child: Text(done ? 'Revisar acta local' : 'Abrir visita'),
                ),
                if (done && !sent)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(() => _sync(p)),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Sincronizar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Online entry points honor existing downloads, avoiding a second competing draft.
class VisitaEntradaScreen extends StatefulWidget {
  final VisitasService svc;
  final String visitaId, empresaId, userId, nombreUsuario;
  const VisitaEntradaScreen({
    super.key,
    required this.svc,
    required this.visitaId,
    required this.empresaId,
    required this.userId,
    required this.nombreUsuario,
  });
  @override
  State<VisitaEntradaScreen> createState() => _VisitaEntradaScreenState();
}

class _VisitaEntradaScreenState extends State<VisitaEntradaScreen> {
  late final Future<Widget> _page;
  VisitasLocalService? _local;
  @override
  void initState() {
    super.initState();
    _page = _resolve();
  }

  Future<Widget> _resolve() async {
    if (VisitasLocalStore.disponible) {
      final packages = await VisitasLocalStore.instance.listar(
        widget.userId,
        widget.empresaId,
      );
      final p = packages
          .where((p) => p['visitaId'] == widget.visitaId)
          .firstOrNull;
      if (p != null) {
        await prepararAperturaLocal(p);
        if (!await desbloquearVisitasLocal(widget.userId, widget.empresaId)) {
          throw const VisitasException('No se desbloqueó la visita.');
        }
        _local = VisitasLocalService(p);
        return pantallaVisitaDescargada(_local!);
      }
    }
    return pantallaEjecutarVisita(
      widget.svc,
      widget.visitaId,
      widget.empresaId,
      widget.userId,
      widget.nombreUsuario,
    );
  }

  @override
  void dispose() {
    _local?.disposeLocal();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
    future: _page,
    builder: (_, s) =>
        s.data ??
        Scaffold(
          appBar: AppBar(title: const Text('Visita')),
          body: Center(
            child: s.hasError
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(s.error.toString()),
                  )
                : const CircularProgressIndicator(),
          ),
        ),
  );
}

Widget imagenVisita(
  String url, {
  double? width,
  double? height,
  BoxFit? fit,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  if (!url.startsWith('local:')) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
  return FutureBuilder<Uint8List>(
    future: () async {
      final store = VisitasLocalStore.instance;
      final grant = await store.acceso();
      if (grant == null || !grant.vigente(DateTime.now())) {
        throw StateError('Acceso local no disponible.');
      }
      return store.foto(grant.userId, grant.empresaId, url.substring(6));
    }(),
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return Image.memory(
          snapshot.data!,
          width: width,
          height: height,
          fit: fit,
        );
      }
      return SizedBox(
        width: width,
        height: height,
        child: const Icon(Icons.image_outlined),
      );
    },
  );
}
