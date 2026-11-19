import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'planeacion_service.dart';

class PlaneacionImportacion {
  const PlaneacionImportacion(this.menus, this.errores, this.advertencias);
  final List<PlaneacionDato> menus;
  final List<String> errores, advertencias;
}

/// Lee únicamente DatosMenú. No ejecuta fórmulas, vínculos ni instrucciones del
/// archivo, ni crea productos. La correspondencia usa códigos de Compras.
PlaneacionImportacion interpretarMenusPlaneacion(
  Uint8List bytes,
  List<PlaneacionDato> productos,
) {
  if (bytes.length > 15 * 1024 * 1024) {
    throw const FormatException('El archivo supera 15 MB.');
  }
  final zip = ZipDecoder().decodeBytes(bytes);
  String archivo(String nombre) {
    final f = zip.findFile(nombre);
    if (f == null || f.size > 25 * 1024 * 1024) {
      throw FormatException('Archivo Excel inválido: $nombre.');
    }
    return utf8.decode(f.content as List<int>);
  }

  final sharedFile = zip.findFile('xl/sharedStrings.xml');
  final strings = sharedFile == null
      ? <String>[]
      : XmlDocument.parse(archivo('xl/sharedStrings.xml'))
            .findAllElements('si')
            .map((si) => si.findAllElements('t').map((t) => t.innerText).join())
            .toList();
  final libro = XmlDocument.parse(archivo('xl/workbook.xml'));
  final hoja = libro
      .findAllElements('sheet')
      .where((s) => s.getAttribute('name') == 'DatosMenú')
      .firstOrNull;
  if (hoja == null) {
    throw const FormatException(
      'Falta la hoja DatosMenú del formato de Planeación.',
    );
  }
  final relaciones = XmlDocument.parse(archivo('xl/_rels/workbook.xml.rels'));
  final relacion = relaciones
      .findAllElements('Relationship')
      .where((r) => r.getAttribute('Id') == hoja.getAttribute('r:id'))
      .firstOrNull;
  final target = relacion?.getAttribute('Target');
  if (target == null || target.contains('..')) {
    throw const FormatException('Hoja de Excel inválida.');
  }
  final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
  final xml = XmlDocument.parse(archivo(path));
  final codigos = <String, List<PlaneacionDato>>{};
  for (final p in productos) {
    codigos
        .putIfAbsent('${p['codigo'] ?? ''}'.trim().toUpperCase(), () => [])
        .add(p);
  }
  final menus = <String, PlaneacionDato>{};
  final errores = <String>[], avisos = <String>{};
  final rows = xml.findAllElements('row').toList();
  if (rows.length > 10000) {
    throw const FormatException('La hoja supera 10.000 filas.');
  }
  for (final row in rows) {
    if (row.getAttribute('r') == '1') continue;
    final celdas = <String, String>{};
    for (final c in row.findElements('c')) {
      final col = (c.getAttribute('r') ?? '').replaceAll(RegExp(r'\d'), '');
      final raw =
          c.getElement('v')?.innerText ??
          c.findAllElements('t').map((t) => t.innerText).join();
      final index = int.tryParse(raw);
      celdas[col] =
          c.getAttribute('t') == 's' &&
              index != null &&
              index >= 0 &&
              index < strings.length
          ? strings[index]
          : raw;
    }
    if ((celdas['A'] ?? '').trim().isEmpty &&
        (celdas['E'] ?? '').trim().isEmpty) {
      continue;
    }
    final fila = row.getAttribute('r');
    final menu = (celdas['A'] ?? '').trim(),
        codigo = (celdas['E'] ?? '').trim();
    final candidatos = codigos[codigo.toUpperCase()] ?? [];
    if (menu.isEmpty || candidatos.length != 1) {
      errores.add(
        'Fila $fila: código $codigo sin correspondencia única en Compras.',
      );
      continue;
    }
    final p = candidatos.single;
    final um = unidadPlaneacion(celdas['L']);
    if (um.isEmpty || um != unidadPlaneacion(p['unidadMedida'])) {
      errores.add(
        'Fila $fila: unidad ${celdas['L']} diferente de ${p['unidadMedida']} para $codigo.',
      );
      continue;
    }
    final gramaje = num.tryParse(celdas['K'] ?? '');
    if (gramaje == null || !gramaje.isFinite || gramaje <= 0) {
      errores.add('Fila $fila: gramaje de compra inválido.');
      continue;
    }
    num cantidad;
    if (um == 'kg' || um == 'l') {
      cantidad = gramaje / 1000;
    } else if (um == 'und') {
      // El Excel fuerza una unidad por ración. La excepción del huevo para
      // tortas se expresaba dividiendo kilogramos por 0,055 kg/unidad.
      if ((celdas['G'] ?? '').trim().toLowerCase() ==
          'huevo de gallina tortas') {
        cantidad = gramaje / 55;
        avisos.add(
          'Huevo para tortas: conversión explícita de 55 g por unidad. Verifica esta equivalencia antes de importar.',
        );
      } else {
        cantidad = 1;
        avisos.add(
          'Productos en Und: se conserva una unidad por ración como en el Excel. Revisa porciones y empaques.',
        );
      }
    } else {
      errores.add('Fila $fila: unidad $um sin conversión definida.');
      continue;
    }
    final tiempo = (celdas['B'] ?? '').trim(),
        preparacion = (celdas['D'] ?? '').trim();
    if (tiempo.isEmpty || preparacion.isEmpty) {
      errores.add('Fila $fila: falta tiempo o preparación.');
      continue;
    }
    final m = menus.putIfAbsent(
      menu,
      () => {
        'codigo': 'MENU $menu',
        'nombre': 'Menú $menu',
        'activo': true,
        'ingredientes': <PlaneacionDato>[],
      },
    );
    (m['ingredientes'] as List<PlaneacionDato>).add({
      'productoCodigo': p['codigo'],
      'unidad': um,
      'cantidadPorRacion': cantidad,
      'tiempo': tiempo,
      'preparacion': preparacion,
    });
  }
  if (menus.isEmpty && errores.isEmpty) {
    errores.add('La hoja no contiene recetas.');
  }
  for (final m in menus.values) {
    if ((m['ingredientes'] as List).length > 150) {
      errores.add('${m['codigo']}: supera 150 ingredientes.');
    }
  }
  avisos.add(
    'Kg y litros: gramaje de compra ÷ 1.000. Comprueba especialmente la unidad de leche en polvo y los insumos desechables.',
  );
  return PlaneacionImportacion(menus.values.toList(), errores, avisos.toList());
}
