import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/gestion_documental/gd_formato_plantilla.dart';
import 'package:todo/gestion_documental/gd_formato_plantilla_word.dart';
import 'package:todo/gestion_documental/gd_service.dart';
import 'package:todo/services/task_service.dart';

import '../support/memory_firestore.dart';

class _Storage extends Fake implements FirebaseStorage {
  bool fallar = false;
  final archivos = <String, Uint8List>{};
  @override
  Reference ref([String? path]) {
    if (fallar) throw StateError('Storage no disponible');
    return _Reference(this, path!);
  }
}

class _Reference extends Fake implements Reference {
  @override
  final _Storage storage;
  final String path;
  _Reference(this.storage, this.path);
  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) {
    storage.archivos[path] = data;
    return _Upload();
  }

  @override
  Future<String> getDownloadURL() async => 'https://example.test/$path';
}

class _Snapshot extends Fake implements TaskSnapshot {}

class _Upload extends Fake implements UploadTask {
  @override
  Future<T> then<T>(
    FutureOr<T> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) => Future<TaskSnapshot>.value(_Snapshot()).then(onValue, onError: onError);
}

void main() {
  late MemoryFirestore db;
  late GdService service;
  late _Storage storage;
  late Uint8List archivo;
  late int requests;
  late int httpStatus;
  final datos = GdPlantillaFormatoDatos(
    empresaNombre: 'Empresa A',
    titulo: 'Formato',
    codigo: 'COM-001',
    area: 'Compras',
    version: 'v1',
    fecha: DateTime(2026),
  );
  setUp(() {
    db = MemoryFirestore();
    requests = 0;
    httpStatus = 200;
    archivo = gdGenerarPlantillaFormatoWord(datos);
    storage = _Storage();
    service = GdService(
      db: db,
      storage: storage,
      taskService: TaskService(db: db, storage: storage),
      httpClient: MockClient((request) async {
        requests++;
        return http.Response.bytes(archivo, httpStatus);
      }),
    );
    db.documents['TBL_USUARIOS/calidad'] = {
      'empresaId': 'B',
      'cargo': 'Cargo de otra empresa',
      'empresasDetalle': {
        'A': {'cargo': 'Director de Calidad'},
      },
    };
    db.documents['TBL_USUARIOS/lector'] = {
      'empresaId': 'A',
      'empresas': ['A', 'B'],
      'appsPorEmpresa': true,
      'empresasDetalle': <String, dynamic>{
        'A': <String, dynamic>{
          'activo': true,
          'apps': ['bibliotecadocumentaldashboard'],
          'rolDocumental': 'consulta',
          'cargo': 'Supervisor de Calidad',
        },
        'B': <String, dynamic>{
          'activo': true,
          'apps': ['bibliotecadocumentaldashboard'],
          'rolDocumental': 'admin_doc',
        },
      },
    };
    db.documents['TBL_DOCUMENTOS/doc'] = {
      'empresaId': 'A',
      'categoria': 'Procedimiento',
      'estado': 'vigente',
      'versionActual': 'v1',
      'versionVigenteId': 'ver',
      'aprobadoPor': 'otro-aprobador',
    };
    db.documents['TBL_DOCUMENTOS_VERSIONES/ver'] = {
      'empresaId': 'A',
      'docId': 'doc',
      'estado': 'vigente',
      'etiqueta': 'v1',
      'esVigente': true,
      'nombreArchivo': 'programa.docx',
      'urlPdf': 'https://example.test/programa.docx',
      'aprobadoPor': 'calidad',
      'aprobadoEn': Timestamp.fromDate(DateTime(2026, 10, 10)),
      'validadoNombre': 'Calidad Original',
    };
  });
  tearDown(() => db.close());

  Future<(Uint8List, String)> descargar({String empresaId = 'A'}) =>
      service.descargarArchivoVersion(
        docId: 'doc',
        versionId: 'ver',
        empresaId: empresaId,
        actorId: 'lector',
      );

  test(
    'Word ya validado descarga el sello de esa versión sin escrituras',
    () async {
      final (bytes, nombre) = await descargar();
      final zip = ZipDecoder().decodeBytes(bytes);
      final encabezado = utf8.decode(
        zip.findFile('word/header1.xml')!.content as List<int>,
      );
      expect(encabezado, contains('Director de Calidad'));
      expect(encabezado, isNot(contains('Pendiente')));
      expect(encabezado, isNot(contains('otro-aprobador')));
      expect(nombre, 'programa.docx');
      expect(db.writes, 0);
    },
  );

  test('la descarga conserva el cargo guardado al validar', () async {
    db.documents['TBL_DOCUMENTOS_VERSIONES/ver']!['validadoCargo'] =
        'Jefe de Calidad';
    final (bytes, _) = await descargar();
    final xml = utf8.decode(
      ZipDecoder().decodeBytes(bytes).findFile('word/header1.xml')!.content
          as List<int>,
    );
    expect(xml, contains('Jefe de Calidad'));
    expect(xml, isNot(contains('Director de Calidad')));
    expect(db.writes, 0);
  });
  test(
    'no toma el cargo de otra empresa ni vuelve a poner el nombre',
    () async {
      db.documents['TBL_USUARIOS/calidad']!['empresasDetalle'] = {};
      final (bytes, _) = await descargar();
      final xml = utf8.decode(
        ZipDecoder().decodeBytes(bytes).findFile('word/header1.xml')!.content
            as List<int>,
      );
      expect(xml, contains('Cargo no registrado'));
      expect(xml, isNot(contains('Cargo de otra empresa')));
      expect(xml, isNot(contains('Calidad Original')));
    },
  );
  test('Excel ya validado se actualiza también en la descarga', () async {
    archivo = gdGenerarPlantillaFormato(datos);
    db.documents['TBL_DOCUMENTOS_VERSIONES/ver']!['nombreArchivo'] =
        'programa.xlsx';
    final (bytes, nombre) = await descargar();
    final zip = ZipDecoder().decodeBytes(bytes);
    final hoja = utf8.decode(
      zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(hoja, contains('Director de Calidad'));
    expect(hoja, isNot(contains('Pendiente')));
    expect(nombre, 'programa.xlsx');
    expect(db.writes, 0);
  });

  test(
    'no pone un sello en un borrador aunque conserve metadatos antiguos',
    () async {
      db.documents['TBL_USUARIOS/lector']!['empresasDetalle']['A']['rolDocumental'] =
          'redactor';
      db.documents['TBL_DOCUMENTOS_VERSIONES/ver']!['estado'] = 'borrador';
      final (bytes, _) = await descargar();
      expect(bytes, archivo);
      expect(db.writes, 0);
    },
  );

  test(
    'lector no accede a borradores y una empresa no toma versiones de otra',
    () async {
      db.documents['TBL_DOCUMENTOS_VERSIONES/ver']!['estado'] = 'borrador';
      await expectLater(descargar(), throwsA(isA<GdException>()));
      await expectLater(descargar(empresaId: 'B'), throwsA(isA<GdException>()));
      expect(requests, 0);
    },
  );

  test('revocación de app o persona inactiva impide la descarga', () async {
    final detalle =
        db.documents['TBL_USUARIOS/lector']!['empresasDetalle']['A'];
    detalle['apps'] = <String>[];
    await expectLater(descargar(), throwsA(isA<GdException>()));
    detalle['apps'] = ['bibliotecadocumentaldashboard'];
    detalle['activo'] = false;
    await expectLater(descargar(), throwsA(isA<GdException>()));
    expect(requests, 0);
  });

  test('sin evidencia de aprobación no inventa un sello', () async {
    db.documents['TBL_DOCUMENTOS_VERSIONES/ver']!.remove('aprobadoPor');
    await expectLater(descargar(), throwsA(isA<GdException>()));
    expect(db.writes, 0);
  });

  test(
    'Word/Excel ilegible o descarga fallida no publica ni da un check',
    () async {
      db.documents['TBL_USUARIOS/lector']!['empresasDetalle']['A']['rolDocumental'] =
          'revisor';
      db.documents['TBL_DOCUMENTOS/doc']!['estado'] = 'en_revision';
      db.documents['TBL_DOCUMENTOS_VERSIONES/ver']!['estado'] = 'en_revision';
      Future<void> validar() => service.validarFormatoInstitucional(
        docId: 'doc',
        versionId: 'ver',
        empresaId: 'A',
        actorId: 'lector',
        rolDocumental: 'revisor',
        nombreActor: 'Calidad',
      );
      archivo = Uint8List.fromList([1, 2, 3]);
      for (final extension in ['docx', 'xlsx']) {
        db.documents['TBL_DOCUMENTOS_VERSIONES/ver']!['nombreArchivo'] =
            'archivo.$extension';
        await expectLater(
          validar(),
          throwsA(
            isA<GdException>().having(
              (e) => e.mensaje,
              'mensaje',
              contains('sigue en revisión'),
            ),
          ),
        );
      }
      httpStatus = 503;
      await expectLater(validar(), throwsA(isA<GdException>()));
      expect(db.documents['TBL_DOCUMENTOS/doc']!['estado'], 'en_revision');
      expect(db.writes, 0);
    },
  );

  test(
    'validar guarda el Office sellado, conserva el original y publica esa URL',
    () async {
      db.documents['TBL_USUARIOS/lector']!['empresasDetalle']['A']['rolDocumental'] =
          'revisor';
      db.documents['TBL_DOCUMENTOS/doc']!['estado'] = 'en_revision';
      db.documents['TBL_DOCUMENTOS_VERSIONES/ver']!['estado'] = 'en_revision';
      await service.validarFormatoInstitucional(
        docId: 'doc',
        versionId: 'ver',
        empresaId: 'A',
        actorId: 'lector',
        rolDocumental: 'revisor',
        nombreActor: 'Ana Calidad',
      );
      final version = db.documents['TBL_DOCUMENTOS_VERSIONES/ver']!;
      expect(version['estado'], 'vigente');
      expect(
        version['archivoOriginalUrl'],
        'https://example.test/programa.docx',
      );
      expect(
        version['urlPdf'],
        'https://example.test/${storage.archivos.keys.single}',
      );
      expect(version['validadoNombre'], 'Ana Calidad');
      expect(version['selloEnArchivo'], true);
      final guardado = ZipDecoder().decodeBytes(storage.archivos.values.single);
      final texto = utf8.decode(
        guardado.findFile('word/header1.xml')!.content as List<int>,
      );
      expect(texto, contains('Supervisor de Calidad'));
      expect(version['validadoCargo'], 'Supervisor de Calidad');
      expect(texto, isNot(contains('Pendiente')));
      expect(db.documents['TBL_DOCUMENTOS/doc']!['versionVigenteId'], 'ver');
    },
  );

  test('si falla Storage, no marca el formato como validado', () async {
    storage.fallar = true;
    db.documents['TBL_USUARIOS/lector']!['empresasDetalle']['A']['rolDocumental'] =
        'revisor';
    db.documents['TBL_DOCUMENTOS/doc']!['estado'] = 'en_revision';
    db.documents['TBL_DOCUMENTOS_VERSIONES/ver']!['estado'] = 'en_revision';
    await expectLater(
      service.validarFormatoInstitucional(
        docId: 'doc',
        versionId: 'ver',
        empresaId: 'A',
        actorId: 'lector',
        rolDocumental: 'revisor',
        nombreActor: 'Calidad',
      ),
      throwsA(isA<GdException>()),
    );
    expect(db.writes, 0);
  });
}
