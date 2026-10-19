import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/notification_monitor_panel.dart';
import 'package:todo/admin/notification_monitor_service.dart';
import 'package:todo/interventoria/interventoria_service.dart';

class _Falso implements NotificationMonitorService {
  @override
  Future<void> reasignar({
    required String empresaId,
    required AvisoMonitor aviso,
    required InterventoriaPersona persona,
    required String creadorId,
  }) async {}

  @override
  Future<void> quitarAsignacion({
    required String empresaId,
    required AvisoMonitor aviso,
  }) async {}

  @override
  Future<DatosMonitor> cargar({required String empresaId, int dias = 7}) async {
    AvisoMonitor aviso(String id, String user, String sede) =>
        AvisoMonitor.fromMap({
          'id': id,
          'userId': user,
          'titulo': 'Hallazgo en $sede',
          'tipo': 'task_assigned',
          'modulo': 'interventoria',
          'hallazgoId': 'h',
          'cargoResponsable': 'Coordinador de calidad',
          'numeral': '2.14',
          'sedeId': sede,
          'sedeNombre': sede,
          'entrega': 'delivered',
          'creadaMs': DateTime.now().millisecondsSinceEpoch,
        });
    return DatosMonitor(
      avisos: [aviso('1', '10', 'Guateque'), aviso('2', '11', 'Guateque')],
      usuarios: {
        '10': const InterventoriaUsuario(
          id: '10',
          nombre: 'Ana Moniquirá',
          cargo: 'Administrador',
          centroId: '',
          areaId: '',
          centrosAsignadosIds: {'Moniquira'},
        ),
        '11': const InterventoriaUsuario(
          id: '11',
          nombre: 'Luis Guateque',
          cargo: 'Administrador',
          centroId: '',
          areaId: '',
          centrosAsignadosIds: {'Guateque'},
        ),
      },
      truncado: false,
      dias: dias,
    );
  }
}

void main() {
  for (final ancho in [390.0, 768.0, 1024.0, 1366.0]) {
    testWidgets('monitor sin desbordes a $ancho con texto 1.6', (tester) async {
      tester.view.physicalSize = Size(ancho, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(ancho, 900),
              textScaler: const TextScaler.linear(1.6),
            ),
            child: Scaffold(
              body: AdminNotificationMonitorPanel(
                userId: 'admin',
                empresaId: 'e1',
                service: _Falso(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Llegaron a otra sede'), findsOneWidget);
      expect(find.textContaining('Alertas (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, 'Ana');
      await tester.pump();
      expect(find.textContaining('Cubre 1 sede'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Reasignar a quien cubre la sede'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('¿Por qué le llegó?'), findsWidgets);
      await tester.scrollUntilVisible(
        find.textContaining('Por establecimiento'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );

      for (final vista in ['Por establecimiento', 'Por persona', 'Detalle']) {
        await tester.tap(find.textContaining(vista).first);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: vista);
      }
    });
  }
}
