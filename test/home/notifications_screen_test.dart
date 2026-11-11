import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:todo/home/notifications_screen.dart';
import 'package:todo/home/widgets/home_shared_widgets.dart';

import '../support/memory_firestore.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CO'));

  testWidgets('el encabezado de agenda acomoda el botón con texto ampliado', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: SizedBox(
              width: 245,
              child: SectionHeader(
                title: 'Calendario de Actividades',
                trailing: IconButton(
                  tooltip: 'Actualizar planes de mejora',
                  onPressed: () {},
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Actualizar planes de mejora'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
    testWidgets('reutiliza los avisos y pagina el historial a $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final db = MemoryFirestore();
      addTearDown(db.close);
      const path = 'TBL_NOTIFICACIONES/persona/notifications';
      final now = DateTime.now();
      for (var i = 0; i < 41; i++) {
        db.documents['$path/aviso_$i'] = {
          'empresaId': 'empresa-a',
          'title': 'Registro $i',
          'createdAt': Timestamp.fromDate(now.subtract(Duration(seconds: i))),
          'read': true,
        };
      }
      db.documents['$path/pendiente'] = {
        'empresaId': 'empresa-a',
        'title': 'Pendiente histórico',
        'createdAt': now.toIso8601String(),
      };
      db.documents['$path/visto'] = {
        'empresaId': 'empresa-a',
        'title': 'Leído histórico',
        'createdAt': Timestamp.fromDate(now.add(const Duration(seconds: 2))),
        'visto': true,
      };
      db.documents['$path/otra_empresa'] = {
        'empresaId': 'empresa-b',
        'title': 'Otra empresa',
        'createdAt': Timestamp.fromDate(now.add(const Duration(seconds: 3))),
      };
      db.documents['$path/sin_fecha'] = {
        'empresaId': 'empresa-a',
        'title': 'Aviso sin fecha',
      };
      final notifications = ValueNotifier<NotificationSnapshot>(
        AsyncSnapshot.withData(
          ConnectionState.active,
          await db.collection(path).get(),
        ),
      );
      addTearDown(notifications.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1000),
              textScaler: const TextScaler.linear(1.6),
            ),
            child: NotificationsScreen(
              userId: 'persona',
              empresaId: 'empresa-a',
              notifications: notifications,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pendiente histórico'), findsOneWidget);
      expect(find.text('Leído histórico'), findsNothing);
      expect(find.text('Otra empresa'), findsNothing);
      expect(find.text('Aviso sin fecha'), findsNothing);

      await tester.tap(find.text('HISTORIAL'));
      await tester.pumpAndSettle();
      expect(find.text('Leído histórico'), findsOneWidget);
      expect(find.text('Registro 40'), findsNothing);

      final more = find.text('Ver más notificaciones');
      final list = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(more, 1200, scrollable: list);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('Registro 40'), findsOneWidget);

      db.documents['$path/pendiente']!['read'] = true;
      notifications.value = AsyncSnapshot.withData(
        ConnectionState.active,
        await db.collection(path).get(),
      );
      await tester.tap(find.text('NUEVAS'));
      await tester.pumpAndSettle();
      expect(find.text('Sin novedades'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
