import 'package:cloud_firestore/cloud_firestore.dart';

/// Convierte una fecha de nacimiento en una fecha civil, sin aplicar zonas
/// horarias. Para cumpleaños importan año, mes y día, no un instante UTC.
DateTime? parseFechaNacimiento(Object? raw) {
  if (raw == null) return null;
  // Firestore suele recibir fechas civiles como medianoche local o UTC. Leer
  // los componentes UTC evita que Colombia las convierta al día anterior.
  if (raw is Timestamp) return _civil(raw.toDate().toUtc());
  if (raw is DateTime) return _civil(raw);

  final value = raw.toString().trim();
  if (value.isEmpty) return null;

  final latin = RegExp(
    r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})$',
  ).firstMatch(value);
  if (latin != null) {
    return _validDate(
      int.parse(latin.group(3)!),
      int.parse(latin.group(2)!),
      int.parse(latin.group(1)!),
    );
  }

  // Lee solo la parte civil de ISO-8601. DateTime.parse convertiría sufijos Z
  // u offsets a hora local y podría desplazar el cumpleaños un día.
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(value);
  if (iso != null) {
    return _validDate(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  return null;
}

DateTime _civil(DateTime value) => DateTime(value.year, value.month, value.day);

DateTime? _validDate(int year, int month, int day) {
  if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final value = DateTime(year, month, day);
  return value.year == year && value.month == month && value.day == day
      ? value
      : null;
}

DateTime proximoCumpleanos(DateTime birth, {DateTime? desde}) {
  final today = _civil(desde ?? DateTime.now());
  var next = DateTime(today.year, birth.month, birth.day);
  if (next.isBefore(today)) {
    next = DateTime(today.year + 1, birth.month, birth.day);
  }
  return next;
}

int diasParaCumpleanos(DateTime birth, {DateTime? desde}) {
  final today = _civil(desde ?? DateTime.now());
  return proximoCumpleanos(birth, desde: today).difference(today).inDays;
}

int edadEnFecha(DateTime birth, {DateTime? fecha}) {
  final current = _civil(fecha ?? DateTime.now());
  var age = current.year - birth.year;
  if (current.month < birth.month ||
      (current.month == birth.month && current.day < birth.day)) {
    age--;
  }
  return age < 0 ? 0 : age;
}

int edadAlProximoCumpleanos(DateTime birth, {DateTime? desde}) =>
    proximoCumpleanos(birth, desde: desde).year - birth.year;
