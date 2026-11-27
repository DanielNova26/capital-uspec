import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/firestore_user_repository.dart';
import 'package:todo/talento_humano/carnet_filtros.dart';
import 'package:todo/talento_humano/carnet_marca.dart';
import 'package:todo/talento_humano/carnet_pdf.dart';
import 'package:todo/talento_humano/carnet_service.dart';
import '../support/memory_firestore.dart';

class _Users extends Fake implements FirestoreUserRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'genera el lote completo con foto y conserva sus QR al reimprimir',
    () async {
      final db = MemoryFirestore();
      addTearDown(db.close);
      final candidatos = List.generate(70, (i) {
        db.documents['TBL_USUARIOS/$i'] = {'empresaId': 'ALFA'};
        db.documents['TBL_USUARIOS/$i/hoja_de_vida/datos'] = {
          'tipoSangre': 'O+',
        };
        return CarnetCandidato(
          userId: '$i',
          cedula: '100$i',
          nombres: 'Persona $i',
          apellidos: 'Prueba',
          cargo: 'Auxiliar',
          fotoUrl: i.isEven ? 'https://foto' : '',
        );
      });
      final filtrados = candidatos
          .where(const CarnetFiltros(foto: CarnetFiltroEstado.con).incluye)
          .toList();
      expect(filtrados, hasLength(35));
      final service = CarnetService(db: db, users: _Users());
      final personas = await service.prepararLote(
        candidatos: filtrados,
        empresaId: 'ALFA',
      );
      expect(personas, hasLength(35));
      expect(personas.last.userId, '68');
      expect(personas.every((p) => p.rh == 'O+'), isTrue);
      expect(personas.map((p) => p.token).toSet(), hasLength(35));
      expect(db.writes, 35);
      final reimpresion = await service.prepararLote(
        candidatos: filtrados,
        empresaId: 'ALFA',
      );
      expect(reimpresion.map((p) => p.token), personas.map((p) => p.token));
      expect(db.writes, 35);
      const marca = CarnetMarca(
        empresaId: 'ALFA',
        empresaNombre: 'Unión Temporal ALFA',
      );
      final hoja = await buildCarnetsHojaPdf(
        personas: personas,
        marca: marca,
        recursos: const CarnetRecursos(),
      );
      final individual = await buildCarnetsIndividualesPdf(
        personas: personas,
        marca: marca,
        recursos: const CarnetRecursos(),
      );
      expect(String.fromCharCodes(hoja.take(5)), '%PDF-');
      expect(String.fromCharCodes(individual.take(5)), '%PDF-');
      final salida = Directory('build/carnet_muestra')
        ..createSync(recursive: true);
      File('${salida.path}/lote_35_hojas.pdf').writeAsBytesSync(hoja);
      File(
        '${salida.path}/lote_35_individual.pdf',
      ).writeAsBytesSync(individual);
    },
  );
}
