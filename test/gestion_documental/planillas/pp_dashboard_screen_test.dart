import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signature/signature.dart';
import 'package:todo/gestion_documental/gd_firmas_screen.dart';
import 'package:todo/gestion_documental/gd_models.dart';
import 'package:todo/gestion_documental/gd_service.dart';
import 'package:todo/gestion_documental/planillas/pp_dashboard_screen.dart';
import 'package:todo/gestion_documental/planillas/pp_models.dart';
import 'package:todo/gestion_documental/planillas/pp_service.dart';

import '../../support/memory_firestore.dart';

class _FirmasService extends Fake implements GdService {
  @override
  Stream<FirmaUsuarioDoc?> streamFirmaUsuario({
    required String empresaId,
    required String userId,
  }) => Stream.value(null);
}

class _PlanillasService extends Fake implements PpService {
  _PlanillasService(this.planillas);

  final List<PpPlanilla> planillas;

  @override
  Future<void> limpiarCamposFirmaBinaria({
    required String empresaId,
    String? planillaId,
  }) async {}

  @override
  Stream<List<PpPlanilla>> streamPlanillasPorEmpresa(
    String empresaId, {
    PpEstado? estado,
  }) => Stream.value([
    for (final planilla in planillas)
      if (planilla.empresaId == empresaId &&
          (estado == null || planilla.estado == estado))
        planilla,
  ]);
}

PpPlanilla _planilla(String nombre, PpEstado estado, {DateTime? firma}) =>
    PpPlanilla(
      planillaId: nombre,
      empresaId: 'A',
      loteId: '',
      nombreArchivoOriginal: '$nombre.pdf',
      nombrePlanillaDetectado: nombre,
      valorDetectado: 1285000,
      estado: estado,
      cargadoPor: 'tesoreria',
      firmadoEn: firma == null ? null : Timestamp.fromDate(firma),
    );

void main() {
  for (final (ancho, plataforma, escala) in [
    (390.0, TargetPlatform.android, 1.8),
    (390.0, TargetPlatform.iOS, 1.8),
    (768.0, TargetPlatform.windows, 1.4),
    (1024.0, TargetPlatform.windows, 1.4),
    (1366.0, TargetPlatform.windows, 1.4),
  ]) {
    testWidgets('Volver y firma se pueden pulsar a $ancho px ($plataforma)', (
      tester,
    ) async {
      final db = MemoryFirestore();
      db.documents['TBL_USUARIOS/admin'] = {
        'empresaId': 'A',
        'rolPlanillas': 'admin_doc',
      };
      addTearDown(db.close);
      await tester.binding.setSurfaceSize(Size(ancho, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: plataforma),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 28),
              viewPadding: const EdgeInsets.only(top: 28),
              textScaler: TextScaler.linear(escala),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (moduleContext) => PpDashboardScreen(
                      userId: 'admin',
                      empresaId: 'A',
                      firestore: db,
                      service: _PlanillasService([]),
                      onOpenIdentity: () => Navigator.of(moduleContext).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GdFirmasScreen(
                            userId: 'admin',
                            empresaId: 'A',
                            service: _FirmasService(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Abrir planillas'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir planillas'));
      await tester.pumpAndSettle();

      final volver = find.byType(BackButton);
      final firmaCompacta = find.byTooltip('Mi identidad digital');
      final firma = firmaCompacta.evaluate().isNotEmpty
          ? firmaCompacta
          : find.text('MI IDENTIDAD DIGITAL');
      expect(volver.hitTestable(), findsOneWidget);
      expect(firma.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(volver).right,
        lessThan(tester.getRect(firma).left),
      );
      expect(tester.getRect(volver).top, greaterThanOrEqualTo(28));

      await tester.tap(firma);
      await tester.pumpAndSettle();
      final lienzo = find.byType(Signature);
      final volverDeFirma = find.byTooltip('Volver');
      expect(lienzo.hitTestable(), findsOneWidget);
      expect(volverDeFirma.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(volverDeFirma).bottom,
        lessThan(tester.getRect(lienzo).top),
      );
      await tester.drag(lienzo, const Offset(30, 15));
      await tester.tap(volverDeFirma);
      await tester.pumpAndSettle();
      expect(find.text('PLANILLAS DE PAGO'), findsOneWidget);
      await tester.tap(volver);
      await tester.pumpAndSettle();
      expect(find.text('Abrir planillas'), findsOneWidget);
    });
  }

  final hoy = DateUtils.dateOnly(DateTime.now());
  for (final (ancho, plataforma) in [
    (390.0, TargetPlatform.android),
    (390.0, TargetPlatform.iOS),
    (768.0, TargetPlatform.windows),
    (1024.0, TargetPlatform.windows),
    (1366.0, TargetPlatform.windows),
  ]) {
    testWidgets(
      'bandeja con filtro por rol y fechas a $ancho px ($plataforma)',
      (tester) async {
        final db = MemoryFirestore();
        db.documents['TBL_USUARIOS/auditor'] = {
          'empresaId': 'A',
          'rolPlanillas': 'auditoria',
        };
        final service = _PlanillasService([
          _planilla('Carga reciente', PpEstado.en_revision_auditoria),
          _planilla('Envío histórico', PpEstado.aprobada_auditoria),
          _planilla('Firma pendiente', PpEstado.pendiente_firma_gerencia),
          _planilla('Firma de hoy', PpEstado.firmada, firma: hoy),
          _planilla(
            'Firma anterior',
            PpEstado.firmada,
            firma: DateTime(hoy.year, hoy.month, hoy.day - 1),
          ),
        ]);
        addTearDown(db.close);
        await tester.binding.setSurfaceSize(Size(ancho, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: plataforma),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: PpDashboardScreen(
              userId: 'auditor',
              empresaId: 'A',
              firestore: db,
              service: service,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(FilterChip), findsOneWidget);
        expect(find.text('Firma pendiente'), findsOneWidget);
        await tester.tap(find.text('Por atender'));
        await tester.pumpAndSettle();
        expect(find.text('Carga reciente'), findsOneWidget);
        expect(find.text('Envío histórico'), findsOneWidget);
        expect(find.text('Firma pendiente'), findsNothing);
        await tester.tap(find.text('Por atender'));
        await tester.pumpAndSettle();
        expect(find.text('Firma pendiente'), findsOneWidget);

        await tester.tap(find.text('FIRMADAS'));
        await tester.pumpAndSettle();
        expect(find.text('Firma de hoy'), findsOneWidget);
        expect(find.text('Firma anterior'), findsOneWidget);
        expect(find.text('Desde'), findsNothing);
        await tester.tap(find.text('Fechas de firma'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Desde'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text('Firma de hoy'), findsOneWidget);
        expect(find.text('Firma anterior'), findsNothing);
        await tester.tap(find.text('Fechas de firma activas'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Limpiar fechas'));
        await tester.pumpAndSettle();
        expect(find.text('Firma anterior'), findsOneWidget);

        await tester.tap(find.text('DESDE EXCEL'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
