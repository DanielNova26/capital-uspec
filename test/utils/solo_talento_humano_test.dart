import 'package:flutter_test/flutter_test.dart';
import 'package:todo/utils/user_company.dart';

// 4 oct 2026, documento "Tareas": "en Talento Humano un campo para marcar
// cuando una persona no va a estar habilitada para operar en To-Do" (solo
// hoja de vida y trámites de Talento Humano).

Map<String, dynamic> _persona({bool? marca, String empresa = 'e1'}) => {
  'empresaId': 'e1',
  'empresas': ['e1', 'e2'],
  'apps': ['tareasdashboard', 'visitasdashboard'],
  'estado': 'activo',
  'empresasDetalle': {
    'e1': {
      'apps': ['tareasdashboard', 'visitasdashboard'],
      if (marca != null && empresa == 'e1') kCampoSoloTalentoHumano: marca,
    },
    'e2': {
      'apps': ['tareasdashboard'],
      if (marca != null && empresa == 'e2') kCampoSoloTalentoHumano: marca,
    },
  },
};

void main() {
  test('sin marca opera normalmente', () {
    final p = _persona();
    expect(soloTalentoHumanoEn(p, 'e1'), isFalse);
    expect(recibeAsignacionesEnEmpresa(p, 'e1'), isTrue);
    expect(userHasApp(p, 'tareasdashboard', empresaId: 'e1'), isTrue);
  });

  test('marcada: no recibe tareas ni abre módulos en esa empresa', () {
    final p = _persona(marca: true);
    expect(soloTalentoHumanoEn(p, 'e1'), isTrue);
    expect(recibeAsignacionesEnEmpresa(p, 'e1'), isFalse);
    // Ni la marca del cargo ("recibe asignaciones") la devuelve.
    expect(recibeAsignacionesEnEmpresa(p, 'e1', marcaDelCargo: true), isFalse);
    expect(userHasApp(p, 'tareasdashboard', empresaId: 'e1'), isFalse);
    expect(userHasApp(p, 'visitasdashboard', empresaId: 'e1'), isFalse);
    // Sigue vinculada: no es un retiro.
    expect(personaHabilitadaEn(p, 'e1'), isTrue);
  });

  test('la marca es por empresa', () {
    final p = _persona(marca: true, empresa: 'e2');
    expect(soloTalentoHumanoEn(p, 'e1'), isFalse);
    expect(soloTalentoHumanoEn(p, 'e2'), isTrue);
    expect(userHasApp(p, 'tareasdashboard', empresaId: 'e1'), isTrue);
    expect(userHasApp(p, 'tareasdashboard', empresaId: 'e2'), isFalse);
  });

  test('acepta texto de importaciones', () {
    final p = _persona()
      ..['empresasDetalle']['e1'][kCampoSoloTalentoHumano] = 'si';
    expect(soloTalentoHumanoEn(p, 'e1'), isTrue);
    p['empresasDetalle']['e1'][kCampoSoloTalentoHumano] = 'false';
    expect(soloTalentoHumanoEn(p, 'e1'), isFalse);
  });
}
