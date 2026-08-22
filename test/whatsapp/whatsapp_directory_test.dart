import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/whatsapp_admin_service.dart';

void main() {
  const person = WhatsAppDirectorioPersona(
    id: '1019152994',
    cedula: '1019152994',
    nombre: 'Daniel Felipe Nova Velasco',
    telefono: '573001234567',
    email: 'daniel@empresa.com',
    cargo: 'Desarrollador',
    tieneTelefonoValido: true,
  );

  test('el directorio encuentra por nombre sin botón de búsqueda', () {
    expect(person.coincide('daniel nova'), isTrue);
  });

  test('el directorio ignora tildes y permite palabras no consecutivas', () {
    const maria = WhatsAppDirectorioPersona(
      id: '2',
      cedula: '2',
      nombre: 'María Fernanda Gómez',
      telefono: '573009876543',
      email: 'maria@empresa.com',
      cargo: 'Coordinadora de Gestión Humana',
      tieneTelefonoValido: true,
    );
    expect(maria.coincide('maria gomez'), isTrue);
    expect(maria.coincide('gestion humana'), isTrue);
  });

  test('el directorio encuentra un celular aunque tenga formato', () {
    expect(person.coincide('+57 300 123 4567'), isTrue);
  });

  test('el directorio también permite buscar por cédula y correo', () {
    expect(person.coincide('1019152994'), isTrue);
    expect(person.coincide('daniel@empresa'), isTrue);
  });
}
