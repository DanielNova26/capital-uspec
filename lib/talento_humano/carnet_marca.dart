// lib/talento_humano/carnet_marca.dart
//
// Lo único que cambia de una empresa a otra en el carnet: dos colores y el
// logo. El modelo (posición de la foto, la banda del cargo, los arcos, el QR)
// es el mismo para todas y no se configura.
//
// Por qué no es un editor de imágenes: el carnet se dibuja como PDF vectorial,
// así que se imprime nítido a cualquier tamaño y los colores se cambian sin
// volver a montar una plantilla. Una plantilla PNG por empresa obligaría a
// rehacer la imagen cada vez que alguien cambia un tono, y se vería borrosa al
// imprimir a 300 dpi.
//
// El logo NO se guarda aparte: es el mismo `logoUrl` de TBL_EMPRESAS que ya
// usan las notificaciones y las planillas. Tener dos logos por empresa termina
// con uno de los dos desactualizado.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Colores del carnet de referencia (ALFA Unión Temporal). Son el punto de
/// partida de cualquier empresa que todavía no haya configurado los suyos.
const int kCarnetAzulPorDefecto = 0xFF1B1B64;
const int kCarnetDoradoPorDefecto = 0xFFC6A02C;

/// Marca del carnet de una empresa.
class CarnetMarca {
  final String empresaId;
  final String empresaNombre;
  final String logoUrl;

  /// Color de la banda del cargo y de la mitad de los arcos.
  final int colorPrimario;

  /// Color de acento: la otra mitad de los arcos.
  final int colorSecundario;

  const CarnetMarca({
    required this.empresaId,
    this.empresaNombre = '',
    this.logoUrl = '',
    this.colorPrimario = kCarnetAzulPorDefecto,
    this.colorSecundario = kCarnetDoradoPorDefecto,
  });

  CarnetMarca copyWith({
    String? empresaNombre,
    String? logoUrl,
    int? colorPrimario,
    int? colorSecundario,
  }) {
    return CarnetMarca(
      empresaId: empresaId,
      empresaNombre: empresaNombre ?? this.empresaNombre,
      logoUrl: logoUrl ?? this.logoUrl,
      colorPrimario: colorPrimario ?? this.colorPrimario,
      colorSecundario: colorSecundario ?? this.colorSecundario,
    );
  }

  /// Lee la marca del documento de la empresa.
  ///
  /// Un campo ausente no es un error: la empresa que nunca configuró el carnet
  /// imprime con los colores por defecto en vez de quedarse sin carnet.
  factory CarnetMarca.desdeEmpresa(String empresaId, Map<String, dynamic>? d) {
    final data = d ?? const <String, dynamic>{};
    return CarnetMarca(
      empresaId: empresaId,
      empresaNombre: (data['nombre'] ?? data['razonSocial'] ?? '')
          .toString()
          .trim(),
      logoUrl: (data['logoUrl'] ?? '').toString().trim(),
      colorPrimario: colorDesdeHex(
        data['carnetColorPrimario'],
        kCarnetAzulPorDefecto,
      ),
      colorSecundario: colorDesdeHex(
        data['carnetColorSecundario'],
        kCarnetDoradoPorDefecto,
      ),
    );
  }

  Map<String, dynamic> get camposFirestore => {
    'carnetColorPrimario': hexDeColor(colorPrimario),
    'carnetColorSecundario': hexDeColor(colorSecundario),
  };
}

/// Convierte `#1B1B64` (o `1B1B64`, o `#FF1B1B64`) a un entero ARGB opaco.
///
/// Devuelve [porDefecto] ante cualquier cosa que no sea un color: un valor
/// escrito a mano en Firestore no debe dejar la pantalla en rojo.
int colorDesdeHex(dynamic valor, int porDefecto) {
  var texto = valor?.toString().trim() ?? '';
  if (texto.startsWith('#')) texto = texto.substring(1);
  if (texto.length == 6) texto = 'FF$texto';
  if (texto.length != 8) return porDefecto;
  final parsed = int.tryParse(texto, radix: 16);
  return parsed ?? porDefecto;
}

/// `#RRGGBB`, que es como se guardan los colores en TBL_EMPRESAS.
String hexDeColor(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

/// Carga y guardado de la marca. Vive en TBL_EMPRESAS junto al logo.
class CarnetMarcaService {
  final FirebaseFirestore _db;

  CarnetMarcaService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  Future<CarnetMarca> cargar(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) return const CarnetMarca(empresaId: '');
    final snap = await _db.collection('TBL_EMPRESAS').doc(id).get();
    return CarnetMarca.desdeEmpresa(id, snap.data());
  }

  /// Guarda solo los campos del carnet.
  ///
  /// Va con `merge` y sin tocar `logoUrl`: el logo se administra desde Admin y
  /// pisarlo desde aquí borraría el que usan notificaciones y planillas.
  Future<void> guardar(CarnetMarca marca) async {
    final id = marca.empresaId.trim();
    if (id.isEmpty) throw ArgumentError('empresaId es obligatorio');
    await _db.collection('TBL_EMPRESAS').doc(id).set({
      ...marca.camposFirestore,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
