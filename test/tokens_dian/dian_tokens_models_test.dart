import 'package:flutter_test/flutter_test.dart';
import 'package:todo/tokens_dian/dian_tokens_models.dart';
import 'package:todo/utils/user_company.dart';

void main() {
  group('Tokens DIAN', () {
    test('interpreta fechas y nunca necesita exponer el enlace', () {
      final token = DianTokenRecord.fromMap({
        'id': 'dian_1',
        'empresaId': 'EMPRESA_001',
        'estado': 'nuevo',
        'recibidoAt': 1785938400000,
        'remitente': 'DIAN',
        'accessCount': 0,
      });

      expect(token.id, 'dian_1');
      expect(token.recibidoAt, isNotNull);
      expect(token.disponible, isTrue);
      expect(token.abierto, isFalse);
    });

    test('marca como no disponibles los estados finales', () {
      for (final state in ['expirado', 'archivado', 'invalidado']) {
        final token = DianTokenRecord.fromMap({'id': state, 'estado': state});
        expect(token.disponible, isFalse, reason: state);
      }
    });

    test('normaliza aliases del modulo al appId canonico', () {
      final normalized = normalizeAppIdList(['tokens', 'tokensdian']);
      expect(normalized.ids, ['tokensdiandashboard']);
      expect(normalized.changed, isTrue);
    });

    test('el buzon parte desconectado y anuncia su filtro', () {
      const buzon = DianBuzonEstado.sinConectar;

      expect(buzon.conectado, isFalse);
      expect(buzon.conError, isFalse);
      expect(buzon.descripcionFiltro, contains(kDianRemitenteOficial));
      expect(buzon.descripcionFiltro, contains(kDianAsuntoOficial));
    });

    test('lee el estado del buzon sin exponer credenciales', () {
      final buzon = DianBuzonEstado.fromMap({
        'conectado': true,
        'proveedor': 'yahoo',
        'email': 'buzon.dian@yahoo.com',
        'estado': 'conectado',
        'ultimaRevisionAt': 1785938400000,
        'totalRegistrados': 7,
        'remitenteFiltrado': kDianRemitenteOficial,
        'asuntoFiltrado': kDianAsuntoOficial,
        'appPasswordEncrypted': 'no-deberia-viajar',
      });

      expect(buzon.conectado, isTrue);
      expect(buzon.email, 'buzon.dian@yahoo.com');
      expect(buzon.ultimaRevisionAt, isNotNull);
      expect(buzon.totalRegistrados, 7);
      expect(buzon.ultimoError, isEmpty);
    });

    test('marca el buzon en error y conserva el motivo', () {
      final buzon = DianBuzonEstado.fromMap({
        'conectado': true,
        'estado': 'error',
        'ultimoError': 'Yahoo rechazo las credenciales.',
      });

      expect(buzon.conError, isTrue);
      expect(buzon.conectado, isTrue);
      expect(buzon.ultimoError, contains('credenciales'));
    });

    test('reconoce el estado de credenciales invalidas', () {
      final buzon = DianBuzonEstado.fromMap({
        'conectado': false,
        'estado': 'credenciales_invalidas',
        'ultimoError': 'Yahoo rechazo la clave.',
      });

      expect(buzon.conError, isTrue);
      expect(buzon.conectado, isFalse);
    });

    test('resume la lectura del buzon en lenguaje del usuario', () {
      final vacio = DianBuzonResumen.fromMap({'revisados': 0});
      final sinNuevos = DianBuzonResumen.fromMap({
        'revisados': 3,
        'duplicados': 3,
      });
      final conNuevos = DianBuzonResumen.fromMap({
        'revisados': 2,
        'registrados': 2,
      });

      expect(vacio.mensaje, contains('No llegaron tokens'));
      expect(sinNuevos.mensaje, contains('3'));
      expect(conNuevos.mensaje, contains('2 token(s) nuevo(s)'));
    });

    test('respeta autorizacion por empresa activa', () {
      final user = <String, dynamic>{
        'empresasDetalle': {
          'EMPRESA_A': {
            'apps': ['tokensdiandashboard'],
          },
          'EMPRESA_B': {
            'apps': ['correodashboard'],
          },
        },
      };

      expect(userHasApp(user, 'tokens', empresaId: 'EMPRESA_A'), isTrue);
      expect(userHasApp(user, 'tokens', empresaId: 'EMPRESA_B'), isFalse);
    });
  });
}
