// Fuera del navegador no hay "client hints": el equipo se lee con
// device_info_plus (ver device_info_reader.dart).
Future<({String modelo, String version})> pistasDelNavegador() async =>
    (modelo: '', version: '');
