import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

import '../core/area_directory.dart' show areaClave;
import '../core/grupos_trabajo.dart';
import '../interventoria/interventoria_models.dart';
import '../interventoria/interventoria_revision_maestro.dart';
import '../interventoria/interventoria_service.dart';
import 'cobertura_personal_logic.dart';

/// Modelo de Excel para cargar la cobertura de todo el personal a la vez.
///
/// Se descarga con el personal actual, se edita en Excel (sedes de operación,
/// sedes de trabajo y grupos) y se vuelve a subir. Solo cambia lo que difiere
/// de lo guardado, y la pantalla muestra cada cambio antes de aplicarlo.
const String kHojaCobertura = 'Cobertura';
const String kHojaInstrucciones = 'Instrucciones';
const String kHojaSedes = 'Sedes';
const String kHojaGrupos = 'Grupos';

const List<String> kColumnasCobertura = [
  'CEDULA',
  'NOMBRE',
  'CARGO',
  'CENTRO DE COSTOS',
  'SU CARGO USA GRUPOS',
  'ESTADO ACTUAL',
  'SEDES DE OPERACION',
  'SEDES DE TRABAJO',
  'GRUPOS',
];

const String _separador = '; ';

String _unir(Iterable<String> nombres) =>
    (nombres.toList()..sort()).join(_separador);

/// Construye el modelo con todo el personal activo y lo que tiene hoy.
Uint8List construirPlantillaCobertura({
  required List<InterventoriaUsuario> usuarios,
  required List<CentroCostoRef> centros,
}) {
  final excel = xl.Excel.createExcel();
  final nombreDe = {for (final c in centros) c.centroId: c.nombre};
  String nombre(String id) => nombreDe[id] ?? id;

  // Instrucciones (hoja por defecto).
  excel.rename('Sheet1', kHojaInstrucciones);
  final ins = excel[kHojaInstrucciones];
  for (final linea in const [
    'MODELO DE COBERTURA DEL PERSONAL',
    '',
    'Para qué sirve: define a qué establecimientos atiende cada persona. De '
        'eso depende a quién le llega cada subsanación de Interventoría.',
    '',
    'Cómo se usa:',
    '1. Ve a la hoja "$kHojaCobertura". Cada fila es una persona.',
    '2. Edita SOLO las tres últimas columnas: SEDES DE OPERACION, SEDES DE '
        'TRABAJO y GRUPOS. Las demás son de consulta.',
    '3. Varias sedes o grupos se separan con punto y coma. Ej.: Picota; La Mesa.',
    '4. Escribe las sedes tal como están en la hoja "$kHojaSedes" y los grupos '
        'como G1, G7 (hoja "$kHojaGrupos").',
    '5. No cambies la CEDULA ni los títulos de las columnas. No borres filas: '
        'las filas que no cambies se ignoran.',
    '6. Guarda el archivo (.xlsx) y súbelo en la aplicación: Admin › Maestros '
        'por módulo › Tareas y notificaciones › Cobertura › Importar Excel.',
    '7. La aplicación muestra cada cambio antes de aplicarlo.',
    '',
    'Reglas que conviene recordar:',
    '- Administrador (una sola sede): sede de operación y de trabajo = su sede '
        'y GRUPOS vacío. Sus grupos no le suman sedes.',
    '- Coordinador, director, supervisor: el grupo que atiende, o sus sedes una '
        'a una si no atiende todo el grupo.',
    '- Una celda vacía en una de las tres columnas editables significa "ninguna".',
    '- Si el nombre de una sede o un grupo no existe, esa fila se rechaza y '
        'la aplicación dice cuál.',
  ]) {
    ins.appendRow([xl.TextCellValue(linea)]);
  }

  // Hoja principal.
  final hoja = excel[kHojaCobertura];
  hoja.appendRow([for (final c in kColumnasCobertura) xl.TextCellValue(c)]);
  final ordenados = [...usuarios]
    ..sort((a, b) {
      final porCargo = a.cargo.toLowerCase().compareTo(b.cargo.toLowerCase());
      return porCargo != 0
          ? porCargo
          : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
  for (final u in ordenados) {
    final d = diagnosticarCobertura(u);
    hoja.appendRow([
      xl.TextCellValue(u.id),
      xl.TextCellValue(u.nombre),
      xl.TextCellValue(u.cargo),
      xl.TextCellValue(u.centroId.isEmpty ? '' : nombre(u.centroId)),
      xl.TextCellValue(u.usaGrupos ? 'SI' : 'NO'),
      xl.TextCellValue(d.estado.etiqueta),
      xl.TextCellValue(_unir(u.centrosOperacionIds.map(nombre))),
      xl.TextCellValue(_unir(u.centrosTrabajoIds.map(nombre))),
      xl.TextCellValue(_unir(u.grupos)),
    ]);
  }

  // Catálogos para copiar nombres exactos.
  final sedes = excel[kHojaSedes];
  sedes.appendRow([
    xl.TextCellValue('SEDE (copia este nombre)'),
    xl.TextCellValue('GRUPO'),
    xl.TextCellValue('ID'),
  ]);
  final porNombre = [...centros]
    ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  for (final c in porNombre) {
    sedes.appendRow([
      xl.TextCellValue(c.nombre),
      xl.TextCellValue(normalizarGrupoCentroCosto(c.grupo)),
      xl.TextCellValue(c.centroId),
    ]);
  }
  final grupos = excel[kHojaGrupos];
  grupos.appendRow([xl.TextCellValue('GRUPO'), xl.TextCellValue('SEDES')]);
  final porGrupo = centrosPorGrupo(centros);
  final claves = porGrupo.keys.toList()..sort();
  for (final g in claves) {
    grupos.appendRow([
      xl.TextCellValue(g),
      xl.TextCellValue(_unir(porGrupo[g]!.map(nombre))),
    ]);
  }
  return Uint8List.fromList(excel.encode()!);
}

/// Un cambio que la importación aplicaría, para mostrarlo antes de confirmar.
class DetalleCambioCobertura {
  const DetalleCambioCobertura({
    required this.cedula,
    required this.nombre,
    required this.resumen,
  });

  final String cedula;
  final String nombre;

  /// "Operación: Picota → Picota, La Mesa · Grupos: G7 → (ninguno)".
  final String resumen;
}

class ResultadoImportacionCobertura {
  const ResultadoImportacionCobertura({
    this.cambios = const [],
    this.detalles = const [],
    this.errores = const [],
    this.filas = 0,
    this.sinCambio = 0,
  });

  final List<CambioCobertura> cambios;
  final List<DetalleCambioCobertura> detalles;

  /// Filas rechazadas, con el motivo. No se aplican.
  final List<String> errores;

  /// Filas leídas con cédula.
  final int filas;
  final int sinCambio;

  bool get hayCambios => cambios.isNotEmpty;
}

String _texto(xl.CellValue? v) {
  if (v == null) return '';
  if (v is xl.TextCellValue) return v.value.toString().trim();
  if (v is xl.IntCellValue) return v.value.toString();
  if (v is xl.DoubleCellValue) {
    final d = v.value;
    return d == d.truncateToDouble() ? d.toInt().toString() : d.toString();
  }
  return v.toString().trim();
}

String _canon(String s) => areaClave(s);

List<String> _partir(String celda) => [
  for (final p in celda.split(RegExp(r'[;\n\r|]')))
    if (p.trim().isNotEmpty) p.trim(),
];

/// Lee el Excel devuelto y calcula qué cambiaría frente a lo guardado.
ResultadoImportacionCobertura leerImportacionCobertura({
  required Uint8List bytes,
  required List<InterventoriaUsuario> usuarios,
  required List<CentroCostoRef> centros,
}) {
  final xl.Excel excel;
  try {
    excel = xl.Excel.decodeBytes(bytes);
  } catch (_) {
    return const ResultadoImportacionCobertura(
      errores: ['El archivo no es un Excel (.xlsx) válido.'],
    );
  }
  final hoja = excel.tables[kHojaCobertura];
  if (hoja == null || hoja.rows.isEmpty) {
    return const ResultadoImportacionCobertura(
      errores: ['No encuentro la hoja "Cobertura". Usa el modelo descargado.'],
    );
  }

  // Columnas por título.
  final titulos = [for (final c in hoja.rows.first) _canon(_texto(c?.value))];
  int col(String nombre) => titulos.indexOf(_canon(nombre));
  final cCedula = col('CEDULA');
  final cOp = col('SEDES DE OPERACION');
  final cTr = col('SEDES DE TRABAJO');
  final cGr = col('GRUPOS');
  if (cCedula < 0 || (cOp < 0 && cTr < 0 && cGr < 0)) {
    return const ResultadoImportacionCobertura(
      errores: [
        'Faltan columnas del modelo (CEDULA y SEDES DE OPERACION, SEDES DE '
            'TRABAJO o GRUPOS). No cambies los títulos.',
      ],
    );
  }

  // Sedes por nombre normalizado (o por id).
  final porNombre = <String, Set<String>>{};
  for (final c in centros) {
    porNombre.putIfAbsent(_canon(c.nombre), () => {}).add(c.centroId);
    porNombre.putIfAbsent(_canon(c.centroId), () => {}).add(c.centroId);
  }
  final nombreDe = {for (final c in centros) c.centroId: c.nombre};
  String nombreSede(String id) => nombreDe[id] ?? id;
  final porId = {for (final u in usuarios) u.id: u};

  final errores = <String>[];
  final cambios = <CambioCobertura>[];
  final detalles = <DetalleCambioCobertura>[];
  final vistas = <String>{};
  var filas = 0;
  var sinCambio = 0;

  String celda(List<xl.Data?> fila, int i) =>
      i < 0 || i >= fila.length ? '' : _texto(fila[i]?.value);

  for (var r = 1; r < hoja.rows.length; r++) {
    final fila = hoja.rows[r];
    final cedula = celda(fila, cCedula);
    if (cedula.isEmpty) continue;
    filas++;
    final etiqueta = 'Fila ${r + 1} (cédula $cedula)';
    final u = porId[cedula];
    if (u == null) {
      errores.add('$etiqueta: no es una persona activa de la empresa.');
      continue;
    }
    if (!vistas.add(cedula)) {
      errores.add(
        '$etiqueta: la cédula está repetida; se usó la primera fila.',
      );
      continue;
    }

    final fallos = <String>[];
    Set<String>? sedes(int c, String que) {
      if (c < 0) return null;
      final out = <String>{};
      for (final n in _partir(celda(fila, c))) {
        final ids = porNombre[_canon(n)];
        if (ids == null) {
          fallos.add('la sede "$n" ($que) no existe');
        } else if (ids.length > 1) {
          fallos.add('la sede "$n" ($que) está repetida en el catálogo');
        } else {
          out.add(ids.single);
        }
      }
      return out;
    }

    final op = sedes(cOp, 'operación');
    final tr = sedes(cTr, 'trabajo');
    Set<String>? gr;
    if (cGr >= 0) {
      gr = {};
      for (final g in _partir(celda(fila, cGr))) {
        final clave = claveGrupoTrabajo(g);
        if (!RegExp(r'^G\d+$').hasMatch(clave)) {
          fallos.add('el grupo "$g" no es válido (usa G1, G7…)');
        } else {
          gr.add(clave);
        }
      }
    }
    if (fallos.isNotEmpty) {
      errores.add('$etiqueta: ${fallos.join('; ')}. No se cambió.');
      continue;
    }

    bool distinto(Set<String>? nuevo, Set<String> actual) =>
        nuevo != null &&
        (nuevo.length != actual.length || !nuevo.containsAll(actual));
    final cambiaOp = distinto(op, u.centrosOperacionIds);
    final cambiaTr = distinto(tr, u.centrosTrabajoIds);
    final cambiaGr = distinto(gr, u.grupos);
    if (!cambiaOp && !cambiaTr && !cambiaGr) {
      sinCambio++;
      continue;
    }
    String lista(Iterable<String> ids) {
      final n = ids.map(nombreSede).toList()..sort();
      return n.isEmpty ? '(ninguna)' : n.join(', ');
    }

    cambios.add(
      CambioCobertura(
        userId: u.id,
        nombre: u.nombre,
        fijarOperacion: cambiaOp ? op : null,
        fijarTrabajo: cambiaTr ? tr : null,
        fijarGrupos: cambiaGr ? gr : null,
      ),
    );
    detalles.add(
      DetalleCambioCobertura(
        cedula: u.id,
        nombre: u.nombre,
        resumen: [
          if (cambiaOp)
            'Operación: ${lista(u.centrosOperacionIds)} → ${lista(op!)}',
          if (cambiaTr)
            'Trabajo: ${lista(u.centrosTrabajoIds)} → ${lista(tr!)}',
          if (cambiaGr)
            'Grupos: ${u.grupos.isEmpty ? '(ninguno)' : (u.grupos.toList()..sort()).join(', ')}'
                ' → ${gr!.isEmpty ? '(ninguno)' : (gr.toList()..sort()).join(', ')}',
        ].join(' · '),
      ),
    );
  }
  return ResultadoImportacionCobertura(
    cambios: cambios,
    detalles: detalles,
    errores: errores,
    filas: filas,
    sinCambio: sinCambio,
  );
}
