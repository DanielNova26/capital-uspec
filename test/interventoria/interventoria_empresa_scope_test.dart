import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_service.dart';
import 'package:todo/interventoria/interventoria_tablero_asignacion.dart';
import 'package:todo/utils/user_company.dart';

void main() {
  group('personal de la empresa activa', () {
    test(
      'ser desarrollador no convierte a alguien en miembro de otra empresa',
      () {
        final usuario = <String, dynamic>{
          'desarrollador': true,
          'empresaId': 'EMPRESA_002',
          'empresas': ['EMPRESA_002'],
        };

        expect(userBelongsToEmpresa(usuario, 'EMPRESA_001'), isFalse);
        expect(
          puedeUsarDatosRaizInterventoria(usuario, 'EMPRESA_001'),
          isFalse,
        );
      },
    );

    test(
      'una cuenta multempresa no hereda el cargo ni el centro de la raíz',
      () {
        final usuario = <String, dynamic>{
          'empresaId': 'EMPRESA_002',
          'empresas': ['EMPRESA_001', 'EMPRESA_002'],
          'cargo': 'Coordinador de calidad',
          'centroId': 'moniquira',
          'areaId': 'EMPRESA_002_mantenimiento',
          'empresasDetalle': <String, dynamic>{
            'EMPRESA_001': <String, dynamic>{},
          },
        };

        expect(userBelongsToEmpresa(usuario, 'EMPRESA_001'), isTrue);
        expect(
          puedeUsarDatosRaizInterventoria(usuario, 'EMPRESA_001'),
          isFalse,
        );
        expect(puedeUsarDatosRaizInterventoria(usuario, 'EMPRESA_002'), isTrue);
      },
    );

    test('la raíz antigua se conserva para una cuenta de una sola empresa', () {
      final usuario = <String, dynamic>{
        'empresas': ['EMPRESA_001'],
        'cargo': 'Coordinador de calidad',
      };

      expect(puedeUsarDatosRaizInterventoria(usuario, 'EMPRESA_001'), isTrue);
    });
  });

  group('filtro de áreas', () {
    const areas = <String, String>{
      'EMPRESA_001_mantenimiento': 'Mantenimiento',
      'EMPRESA_001_calidad': 'Calidad',
    };

    test('no muestra un id de otra empresa aunque el nombre coincida', () {
      expect(
        areaVigenteInterventoria('EMPRESA_002_mantenimiento', areas),
        isNull,
      );
    });

    test('conserva ids de la empresa y nombres legados', () {
      expect(
        areaVigenteInterventoria('EMPRESA_001_calidad', areas),
        'EMPRESA_001_calidad',
      );
      expect(areaVigenteInterventoria('Calidad', areas), 'EMPRESA_001_calidad');
    });
  });

  group('candidatos por sede', () {
    const fuera = InterventoriaPersona(
      id: '1',
      nombre: 'Persona de otra sede',
      cargo: 'Coordinador de calidad',
      cargoMatriz: 'Coordinador de calidad',
      delCentro: false,
    );
    const enSede = InterventoriaPersona(
      id: '2',
      nombre: 'Persona de Moniquirá',
      cargo: 'Director de calidad',
      cargoMatriz: 'Director de calidad',
      delCentro: true,
    );

    test(
      'prioriza una alternativa local aunque la primera tenga candidatos',
      () {
        expect(
          priorizarResponsablesEnSede(const [
            [fuera],
            [enSede],
          ]),
          [enSede],
        );
      },
    );

    test('si no hay nadie local conserva candidatos para elección manual', () {
      expect(
        priorizarResponsablesEnSede(const [
          [fuera],
        ]),
        [fuera],
      );
      expect(priorizarResponsablesEnSede(const []), isEmpty);
    });
  });
}
