import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_offline.dart';

void main() {
  group('FotoPendiente', () {
    test('ida y vuelta conserva a dónde va la foto', () {
      const p = FotoPendiente(
        id: 'v1_100',
        visitaId: 'v1',
        empresaId: 'e1',
        destino: kFotoDestinoFila,
        tablaId: 'ext',
        filaId: 'fija_2',
        nombre: 'ext_100.jpg',
        archivo: '/tmp/v1_100.jpg',
        creadaMs: 100,
        conMarca: true,
      );
      final r = FotoPendiente.fromMap(p.toMap());
      expect(r.visitaId, 'v1');
      expect(r.destino, kFotoDestinoFila);
      expect(r.tablaId, 'ext');
      expect(r.filaId, 'fija_2');
      expect(r.conMarca, isTrue);
      expect(r.creadaMs, 100);
    });

    test('la carpeta de Storage es la misma que la subida en línea', () {
      FotoPendiente de(String destino) => FotoPendiente(
        id: 'x',
        visitaId: 'v',
        empresaId: 'e',
        destino: destino,
        itemId: 'it7',
        tablaId: 't',
        filaId: 'f',
        nombre: 'n.jpg',
        archivo: 'a',
        creadaMs: 1,
      );
      expect(de(kFotoDestinoItem).carpeta, 'it7');
      expect(de(kFotoDestinoFila).carpeta, 't_f');
      expect(de(kFotoDestinoAdicional).carpeta, 'adicionales');
    });
  });

  test('un error de red se distingue de uno de permisos', () {
    expect(
      VisitasOffline.esErrorDeRed(Exception('network-request-failed')),
      isTrue,
    );
    expect(
      VisitasOffline.esErrorDeRed(Exception('permission-denied')),
      isFalse,
    );
  });
}
