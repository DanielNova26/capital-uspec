import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:todo/services/company_branding_service.dart';
import 'package:todo/visitas/visitas_informe_pdf.dart';
import 'package:todo/visitas/visitas_models.dart';

import '../support/memory_firestore.dart';

void main() {
  final logoA = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
  final logoB = Uint8List.fromList([137, 80, 78, 71, 4, 5, 6]);
  late MemoryFirestore db;
  setUp(() {
    CompanyBrandingService.clearLogoCache('A');
    CompanyBrandingService.clearLogoCache('B');
    db = MemoryFirestore()
      ..documents.addAll({
        'TBL_EMPRESAS/A': {
          'logoUrl': 'https://storage.example/logo-a.png?token=empresa-a',
        },
        'TBL_EMPRESAS/B': {
          'logoUrl': 'https://storage.example/logo-b.png?token=empresa-b',
        },
      });
  });

  tearDown(() => db.close());

  test(
    'el logo descargado se incorpora como imagen al PDF de la visita',
    () async {
      final png = Uint8List.fromList(
        img.encodePng(
          img.fill(
            img.Image(width: 80, height: 40),
            color: img.ColorRgb8(10, 80, 160),
          ),
        ),
      );
      final service = CompanyBrandingService(
        db: db,
        client: MockClient((_) async => http.Response.bytes(png, 200)),
      );
      const formato = VisitaFormato(
        id: 'f',
        empresaId: 'A',
        areaId: 'calidad',
        areaNombre: 'Calidad',
        nombre: 'Visita de Calidad',
      );
      final visita = VisitaProfesional(
        id: 'v',
        empresaId: 'A',
        formatoId: 'f',
        formatoNombre: formato.nombre,
        formatoAsignado: formato,
        areaId: 'calidad',
        areaNombre: 'Calidad',
        centroId: 'c',
        centroNombre: 'Centro',
        profesionalId: 'p',
        profesionalNombre: 'Profesional',
        asignadoPorId: 'j',
        asignadoPorNombre: 'Jefe',
        fechaProgramada: DateTime(2026, 10, 23),
        estado: kVisitaTerminada,
      );
      final logo = await service.loadLogoBytes('A');
      expect(logo, png);
      final bytes = await generarInformeVisita(
        v: visita,
        formato: formato,
        empresaNombre: 'Empresa A',
        logo: logo,
      );
      expect(
        RegExp(r'/Subtype\s*/Image\b').hasMatch(String.fromCharCodes(bytes)),
        isTrue,
        reason: 'El PDF debe incorporar el logo descargado como imagen.',
      );
    },
  );

  test(
    'descarga el logo por HTTP compatible con navegador y conserva sus bytes',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/logo-a.png');
        expect(request.url.queryParameters['token'], 'empresa-a');
        return http.Response.bytes(logoA, 200);
      });
      final service = CompanyBrandingService(db: db, client: client);
      expect(await service.loadLogoBytes(' A '), logoA);
    },
  );

  test(
    'la caché pertenece a cada empresa y se invalida al cambiar el logo',
    () async {
      var peticiones = 0;
      final service = CompanyBrandingService(
        db: db,
        client: MockClient((request) async {
          peticiones++;
          return http.Response.bytes(
            request.url.path.contains('a.png') ? logoA : logoB,
            200,
          );
        }),
      );
      expect(await service.loadLogoBytes('A'), logoA);
      expect(await service.loadLogoBytes('B'), logoB);
      expect(await service.loadLogoBytes('A'), logoA);
      expect(peticiones, 2);
      CompanyBrandingService.clearLogoCache('A');
      db.documents['TBL_EMPRESAS/A']!['logoUrl'] =
          'https://storage.example/logo-b.png';
      expect(await service.loadLogoBytes('A'), logoB);
      expect(peticiones, 3);
    },
  );

  for (final estado in [401, 403, 404, 500, 200]) {
    test(
      'respuesta $estado vacía o fallida no se guarda y permite reintentar',
      () async {
        var intentos = 0;
        final service = CompanyBrandingService(
          db: db,
          client: MockClient((_) async {
            intentos++;
            return intentos == 1
                ? http.Response('', estado)
                : http.Response.bytes(logoA, 200);
          }),
        );
        expect(await service.loadLogoBytes('A'), isNull);
        expect(await service.loadLogoBytes('A'), logoA);
        expect(intentos, 2);
      },
    );
  }

  test('un fallo de conexión no se memoriza', () async {
    var intentos = 0;
    final service = CompanyBrandingService(
      db: db,
      client: MockClient((_) async {
        if (++intentos == 1) throw http.ClientException('sin conexión');
        return http.Response.bytes(logoA, 200);
      }),
    );
    expect(await service.loadLogoBytes('A'), isNull);
    expect(await service.loadLogoBytes('A'), logoA);
  });

  test(
    'sin configuración no usa el logo de otra empresa ni el de la aplicación',
    () async {
      db.documents['TBL_EMPRESAS/B'] = {};
      var peticiones = 0;
      final service = CompanyBrandingService(
        db: db,
        client: MockClient((_) async {
          peticiones++;
          return http.Response.bytes(logoA, 200);
        }),
      );
      expect(await service.loadLogoBytes('A'), logoA);
      expect(await service.loadLogoBytes('B'), isNull);
      expect(await service.loadLogoBytes(''), isNull);
      expect(peticiones, 1);
    },
  );
}
