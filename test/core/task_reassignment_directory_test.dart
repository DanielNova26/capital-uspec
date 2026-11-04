import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/task_reassignment_directory.dart';

void main() {
  final areas = <String, Map<String, dynamic>>{
    'area-doc': {'empresaId': 'e', 'areaId': 'e_calidad', 'nombre': 'Calidad'},
    'e_compras': {'nombre': 'Compras'},
    'ajena': {'empresaId': 'otra', 'nombre': 'Reservada'},
  };
  final cargos = <String, Map<String, dynamic>>{
    'cargo-doc': {
      'cargoId': 'inspector',
      'nombre': 'Inspector de Calidad',
      'areaId': 'area-doc',
    },
    'jefe': {'nombre': 'Jefe', 'areaId': 'e_calidad'},
    'jefe-compras': {'nombre': 'Jefe', 'areaId': 'e_compras'},
    'no-opera': {
      'nombre': 'No operativo',
      'areaId': 'e_calidad',
      'recibeAsignaciones': false,
    },
    'externo': {
      'empresaId': 'otra',
      'nombre': 'Externo',
      'areaId': 'e_compras',
    },
  };
  Map<String, dynamic> persona([Map<String, dynamic> extra = const {}]) => {
    'empresaId': 'e',
    'estado': 'activo',
    'nombres': 'Ana',
    ...extra,
  };
  TaskReassignmentDirectory crear(Map<String, Map<String, dynamic>> personas) =>
      TaskReassignmentDirectory.desdeDatos(
        empresaId: 'e',
        usuarios: personas,
        cargos: cargos,
        areas: areas,
        centroAliases: {'sede-doc': 'sede'},
      );

  test(
    'cargo solo por nombre y aliases de área/cargo encuentran todo el personal',
    () {
      final d = crear({
        'nombre': persona({'cargo': ' INSPECTOR DE CALIDÁD '}),
        'alias': persona({'cargoId': 'cargo-doc'}),
        'canonico': persona({'cargoId': 'inspector', 'areaId': 'e_calidad'}),
        'area': persona({
          'cargo': 'Inspector de Calidad',
          'areaId': 'area-doc',
        }),
      });
      final area = d.areas.opciones.firstWhere((a) => a.nombre == 'Calidad');
      expect(area.contiene('area-doc'), isTrue);
      expect(area.contiene('e_calidad'), isTrue);
      expect(d.filtrar(areaId: area.id, cargoId: 'inspector'), hasLength(4));
      expect(d.filtrar(busqueda: 'calidád'), hasLength(4));
      expect(d.cargos.where((c) => c['id'] == 'inspector'), hasLength(1));
      expect(d.areas.opciones.any((a) => a.nombre == 'Reservada'), isFalse);
    },
  );

  test(
    'empresa secundaria usa su puesto y centros, sin heredar la principal',
    () {
      final d = crear({
        'secundaria': {
          'empresaId': 'otra',
          'empresas': ['otra', 'e'],
          'estado': 'activo',
          'cargoId': 'jefe-compras',
          'areaId': 'e_compras',
          'centroId': 'otra-sede',
          'empresasDetalle': {
            'e': {
              'cargo': 'Inspector de Calidad',
              'centrosTrabajoIds': ['sede-doc'],
            },
          },
        },
        'ajena': {'empresaId': 'otra', 'cargo': 'Inspector de Calidad'},
      });
      expect(
        d.filtrar(cargoId: 'inspector', centroId: 'sede').single['id'],
        'secundaria',
      );
      expect(d.filtrar(cargoId: 'jefe-compras'), isEmpty);
      expect(d.filtrar(centroId: 'otra-sede'), isEmpty);
    },
  );

  test(
    'nombres de cargo repetidos se resuelven por área; sin área no se inventa',
    () {
      final d = crear({
        'compras': persona({'cargo': 'Jefe', 'areaId': 'e_compras'}),
        'calidad': persona({'cargo': 'Jefe', 'areaId': 'area-doc'}),
        'ambiguo': persona({'cargo': 'Jefe'}),
        'historico': persona({
          'cargo': 'Cargo sin maestro',
          'areaId': 'e_compras',
        }),
      });
      expect(d.filtrar(cargoId: 'jefe-compras').single['id'], 'compras');
      expect(d.filtrar(cargoId: 'jefe').single['id'], 'calidad');
      expect(d.usuarios.firstWhere((u) => u['id'] == 'ambiguo')['areaId'], '');
      final historico = d.usuarios.firstWhere((u) => u['id'] == 'historico');
      expect(d.cargos.any((c) => c['id'] == historico['cargoId']), isTrue);
      expect(
        d.filtrar(cargoId: historico['cargoId']!).single['id'],
        'historico',
      );
    },
  );

  test(
    'respeta retiro, habilitación, marca operativa y exclusión del aprobador',
    () {
      final d = crear({
        'retirada': persona({
          'empresasDetalle': {
            'e': {'estadoLaboral': 'inactivo'},
          },
        }),
        'deshabilitada': persona({'estado': 'inactivo'}),
        'sin-operar': persona({'soloTalentoHumano': true}),
        'no-asignable': persona({'recibeAsignaciones': false}),
        'cargo-no-operativo': persona({'cargo': 'No operativo'}),
        'responsable': persona(),
        'aprobador': persona(),
        'destino': persona({'cargo': 'Inspector de Calidad'}),
      });
      expect(
        d.filtrar(excluir: {'responsable', 'aprobador'}).single['id'],
        'destino',
      );
    },
  );
}
