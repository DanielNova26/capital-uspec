import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/compras/compras_catalog_logic.dart';
import 'package:todo/compras/compras_excel_export.dart';
import 'package:todo/compras/compras_models.dart';

/// Excel de Consultas > Productos separado por marca y proveedor (25 sep
/// 2026): una fila por producto, marca y proveedor, para escribir las cartas.
void main() {
  final cero = Timestamp.fromMillisecondsSinceEpoch(0);

  DocAdjunto doc(String estado) =>
      DocAdjunto(url: 'https://x/doc.pdf', estadoCalidad: estado);

  MarcaDoc marca(String id, String nombre, {DocAdjunto? ficha}) => MarcaDoc(
    id: id,
    empresaId: 'e1',
    codigo: id,
    descripcion: nombre,
    documentosAsociados: {'fichaTecnica': ?ficha},
    createdAt: cero,
  );

  ProductoDoc producto(String id, String nombre, List<MarcaRef> marcas) =>
      ProductoDoc(
        id: id,
        empresaId: 'e1',
        nombre: nombre,
        unidadMedida: 'KG',
        categoria: 'Abarrotes',
        marcas: marcas,
        createdAt: cero,
      );

  FichaTecnicaDoc ficha(
    String id, {
    required String proveedor,
    required String productoId,
    String marcaId = '',
    String marcaNombre = '',
    String estado = 'aprobado',
  }) => FichaTecnicaDoc(
    id: id,
    empresaId: 'e1',
    proveedorId: 'prov-$proveedor',
    proveedorNombre: proveedor,
    productoId: productoId,
    productoNombre: '',
    marcaId: marcaId,
    marcaNombre: marcaNombre,
    documentoActual: doc(estado),
    creadoPor: 'u1',
    createdAt: cero,
  );

  String estado(String clave, DocAdjunto? d) => d?.tieneDoc != true
      ? 'Falta'
      : d!.aprobado
      ? 'Completo'
      : 'Pendiente';

  final marcas = {
    'm1': marca('m1', 'PALMARIUM', ficha: doc('aprobado')),
    'm2': marca('m2', 'SOLYSOYA'),
  };
  const refPalmarium = MarcaRef(
    marcaId: 'm1',
    codigo: 'm1',
    descripcion: 'PALMARIUM',
  );
  const refSolysoya = MarcaRef(
    marcaId: 'm2',
    codigo: 'm2',
    descripcion: 'SOLYSOYA',
  );

  group('filasProductoMarcaProveedor', () {
    test('una fila por marca y proveedor con ficha', () {
      final filas = filasProductoMarcaProveedor(
        productos: [
          producto('p1', 'ACEITE', [refPalmarium, refSolysoya]),
        ],
        marcasPorId: marcas,
        fichasTecnicas: [
          ficha('f1', proveedor: 'LUHOMAR', productoId: 'p1', marcaId: 'm1'),
          ficha(
            'f2',
            proveedor: 'SAN MIGUEL',
            productoId: 'p1',
            marcaId: 'm1',
            estado: 'pendiente',
          ),
        ],
        estadoDocumento: estado,
      );
      expect(
        filas.map((f) => '${f.marca}|${f.proveedor}|${f.fichaProveedor}'),
        [
          'PALMARIUM|LUHOMAR|Completo',
          'PALMARIUM|SAN MIGUEL|Pendiente',
          // La marca sin proveedor también sale: es lo que falta pedir.
          'SOLYSOYA|$kSinProveedorConFicha|$kSinFichaProveedor',
        ],
      );
      expect(filas.first.fichaMarca, 'Completo');
      expect(filas.last.fichaMarca, 'Falta');
      expect(filas.first.celdas, hasLength(kColumnasProductoProveedor.length));
    });

    test('dos fichas del mismo proveedor y marca son una sola fila', () {
      final filas = filasProductoMarcaProveedor(
        productos: [
          producto('p1', 'ACEITE', [refPalmarium]),
        ],
        marcasPorId: marcas,
        fichasTecnicas: [
          ficha('f1', proveedor: 'LUHOMAR', productoId: 'p1', marcaId: 'm1'),
          ficha('f2', proveedor: 'LUHOMAR', productoId: 'p1', marcaId: 'm1'),
        ],
        estadoDocumento: estado,
      );
      expect(filas, hasLength(1));
    });

    test('producto sin marca: sale la ficha del proveedor y "sin marca"', () {
      final filas = filasProductoMarcaProveedor(
        productos: [
          producto('p2', 'ACELGA', const []),
          producto('p3', 'AMONIO CUATERNARIO', const []),
        ],
        marcasPorId: marcas,
        fichasTecnicas: [ficha('f3', proveedor: 'ASOPENCAR', productoId: 'p2')],
        estadoDocumento: estado,
      );
      expect(filas.map((f) => '${f.producto}|${f.marca}|${f.proveedor}'), [
        'ACELGA|Sin marca|ASOPENCAR',
        'AMONIO CUATERNARIO|Sin marcas vinculadas|$kSinProveedorConFicha',
      ]);
      expect(filas.first.fichaMarca, kNoAplicaSinMarca);
      expect(filas.first.fichaProveedor, 'Completo');
    });
  });

  group('construirExcelHojas', () {
    final bytes = construirExcelHojas(const [
      HojaExcelConsulta(
        nombre: 'Por proveedor',
        columnas: ['Nombre', 'Proveedor'],
        filas: [
          ['ACEITE', 'LUHOMAR'],
          ['ACEITE', 'SAN MIGUEL'],
        ],
      ),
      HojaExcelConsulta(
        nombre: 'Resumen por producto',
        columnas: ['Nombre'],
        filas: [
          ['ACEITE'],
        ],
      ),
    ]);

    test('las hojas y las filas quedan como se pidieron', () {
      final libro = xl.Excel.decodeBytes(bytes);
      expect(libro.tables.keys, ['Por proveedor', 'Resumen por producto']);
      final hoja = libro['Por proveedor'];
      expect(hoja.rows, hasLength(3));
      expect(hoja.rows[2][1]?.value.toString(), 'SAN MIGUEL');
      final estilo = hoja.rows.first.first?.cellStyle;
      expect(estilo?.isBold, isTrue);
    });

    test('cada hoja trae filtro por columna y encabezado fijo', () {
      final zip = ZipDecoder().decodeBytes(bytes);
      String leer(String n) =>
          utf8.decode(zip.findFile(n)!.content as List<int>);
      final hoja1 = leer('xl/worksheets/sheet1.xml');
      expect(hoja1, contains('<autoFilter ref="A1:B3"/>'));
      expect(hoja1, contains('state="frozen"'));
      expect(leer('xl/worksheets/sheet2.xml'), contains('A1:A2'));
      expect(leer('xl/workbook.xml'), contains('_xlnm._FilterDatabase'));
    });

    test('letras de columna de Excel', () {
      expect(letraColumnaExcel(1), 'A');
      expect(letraColumnaExcel(7), 'G');
      expect(letraColumnaExcel(27), 'AA');
    });
  });
}
