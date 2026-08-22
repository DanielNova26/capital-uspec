import 'package:flutter_test/flutter_test.dart';
import 'package:todo/correo/correo_models.dart';

void main() {
  test('separarValores normaliza separadores y descarta valores vacíos', () {
    expect(separarValores(' urgente, factura\n; vencimiento '), [
      'urgente',
      'factura',
      'vencimiento',
    ]);
  });

  test('correoStringList solo conserva valores textuales no vacíos', () {
    expect(correoStringList([' alerta ', null, '', 123]), ['alerta', '123']);
  });

  test('las reglas nuevas buscan palabras clave solo en el asunto', () {
    const regla = CorreoRegla(
      id: 'regla-1',
      empresaId: 'EMPRESA_001',
      nombre: 'Requerimientos',
    );

    expect(regla.buscarEn, const ['asunto']);
    expect(regla.tipoFiltro, 'palabra');
  });

  test('una regla combinada conserva palabra y remitente', () {
    const regla = CorreoRegla(
      id: 'regla-2',
      empresaId: 'EMPRESA_001',
      nombre: 'Tutelas del juzgado',
      tipoFiltro: 'combinado',
      palabrasClave: ['tutela'],
      remitentes: ['juzgado@ramajudicial.gov.co'],
    );

    final data = regla.toMap();
    expect(data['tipoFiltro'], 'combinado');
    expect(data['palabrasClave'], ['tutela']);
    expect(data['remitentes'], ['juzgado@ramajudicial.gov.co']);
  });

  test('cada filtro conserva el icono elegido para WhatsApp', () {
    const regla = CorreoRegla(
      id: 'regla-icono',
      empresaId: 'EMPRESA_001',
      nombre: 'Tutelas',
      icono: '⚖️',
    );

    expect(regla.toMap()['icono'], '⚖️');
  });

  test(
    'un filtro puede crear correspondencia automática por tipo documental',
    () {
      const regla = CorreoRegla(
        id: 'regla-gd',
        empresaId: 'EMPRESA_001',
        nombre: 'Derechos de petición',
        crearCorrespondencia: true,
        tipoDocumental: 'Derecho de petición',
      );

      final data = regla.toMap();
      expect(data['crearCorrespondencia'], isTrue);
      expect(data['accionCoincidencia'], 'correspondencia');
      expect(data['tipoDocumental'], 'Derecho de petición');
    },
  );

  test('un buzón Microsoft conserva su proveedor al serializarse', () {
    const cuenta = CorreoCuenta(
      id: 'cuenta-ms',
      empresaId: 'EMPRESA_001',
      nombre: 'Correspondencia Microsoft',
      email: 'correspondencia@example.com',
      proveedor: 'microsoft',
    );

    expect(cuenta.toMap()['proveedor'], 'microsoft');
  });

  test('el mensaje permite identificar el buzón que lo recibió', () {
    const mensaje = CorreoMensaje(
      id: 'mensaje-1',
      cuentaId: 'cuenta-ms',
      correoCuenta: 'correspondencia@example.com',
      proveedor: 'microsoft',
      remitente: 'ciudadano@example.com',
      asunto: 'Solicitud',
      estado: 'alertado',
      categoria: 'General',
      palabrasClave: [],
      expedienteId: '',
      radicado: '',
      tareaId: '',
    );

    expect(mensaje.correoCuenta, 'correspondencia@example.com');
    expect(mensaje.proveedor, 'microsoft');
  });
}
