// lib/talento_humano/hoja_de_vida_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'hoja_de_vida_service.dart';
import '../login/preview_screen.dart';

const List<String> _epsOptions = [
  'Aliansalud EPS',
  'Anas Wayuu EPSI',
  'Asmet Salud',
  'Asociación Indígena del Cauca EPSI',
  'Cajacopi Atlántico',
  'Capital Salud EPS-S',
  'Capresoca EPS',
  'Comfachocó',
  'Comfaoriente',
  'Comfenalco Valle EPS',
  'Compensar EPS',
  'Coosalud EPS',
  'Dusakawi EPSI',
  'Emssanar E.S.S.',
  'EPM - Empresas Públicas de Medellín',
  'EPS Familiar de Colombia',
  'EPS Sanitas',
  'EPS Sura',
  'Famisanar EPS',
  'Fondo de Pasivo Social de Ferrocarriles Nacionales',
  'Mallamas EPSI',
  'Mutual Ser',
  'Nueva EPS',
  'Pijaos Salud EPSI',
  'Salud Mía EPS',
  'Salud Total EPS',
  'Savia Salud EPS',
  'Servicio Occidental de Salud EPS SOS',
];

String _formatHvDateTime(dynamic value) {
  DateTime? dt;
  if (value is Timestamp) dt = value.toDate();
  if (value is DateTime) dt = value;
  if (value is String) dt = DateTime.tryParse(value);
  if (dt == null) return '';
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final suffix = dt.hour >= 12 ? 'p. m.' : 'a. m.';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '$hour:$minute $suffix';
}

const List<String> _fondoPensionesOptions = [
  'Colpensiones',
  'Colfondos',
  'Porvenir',
  'Protección',
  'Skandia',
];

const List<String> _fondoCesantiasOptions = [
  'Colfondos',
  'Fondo Nacional del Ahorro',
  'Porvenir',
  'Protección',
  'Skandia',
];

const List<String> _estadoCivilOptions = [
  'Soltero/a',
  'Casado/a',
  'Unión libre',
  'Separado/a',
  'Divorciado/a',
  'Viudo/a',
];

const List<String> _tipoSangreOptions = [
  'A+',
  'A-',
  'B+',
  'B-',
  'AB+',
  'AB-',
  'O+',
  'O-',
];

const List<String> _generoOptions = ['Masculino', 'Femenino'];

const List<String> _tipoVehiculoOptions = [
  'Motocicleta',
  'Bicicleta',
  'Carro particular',
  'Transporte público',
];

const Map<String, String> _epsCertificateUrls = {
  'Aliansalud EPS': 'https://www.aliansalud.com.co/',
  'Anas Wayuu EPSI': 'https://www.anaswayuu.com/',
  'Asmet Salud': 'https://www.asmetsalud.com/',
  'Asociación Indígena del Cauca EPSI': 'https://www.aicsalud.org.co/',
  'Cajacopi Atlántico': 'https://cajacopieps.com/',
  'Capital Salud EPS-S': 'https://www.capitalsalud.gov.co/',
  'Capresoca EPS': 'https://www.capresoca-casanare.gov.co/',
  'Comfachocó': 'https://www.comfachoco.com.co/',
  'Comfaoriente': 'https://www.comfaoriente.com/',
  'Comfenalco Valle EPS': 'https://eps.comfenalcovalle.com.co/',
  'Compensar EPS': 'https://www.compensar.com/salud/',
  'Coosalud EPS': 'https://coosalud.com/',
  'Dusakawi EPSI': 'https://dusakawi.com/',
  'Emssanar E.S.S.': 'https://www.emssanar.org.co/',
  'EPM - Empresas Públicas de Medellín': 'https://www.epm.com.co/',
  'EPS Familiar de Colombia': 'https://epsfamiliardecolombia.com/',
  'EPS Sanitas': 'https://www.epssanitas.com/',
  'EPS Sura': 'https://www.epssura.com/',
  'Famisanar EPS': 'https://www.famisanar.com.co/',
  'Fondo de Pasivo Social de Ferrocarriles Nacionales':
      'https://www.fps.gov.co/',
  'Mallamas EPSI': 'https://www.mallamaseps.com.co/',
  'Mutual Ser': 'https://www.mutualser.org/',
  'Nueva EPS': 'https://aplicaciones.nuevaeps.com.co/Portal/home.jspx',
  'Pijaos Salud EPSI': 'https://pijao-salud.com/',
  'Salud Mía EPS': 'https://www.saludmia.com.co/',
  'Salud Total EPS': 'https://saludtotal.com.co/',
  'Savia Salud EPS': 'https://www.saviasaludeps.com/',
  'Servicio Occidental de Salud EPS SOS': 'https://www.sos.com.co/',
};

const Map<String, String> _pensionCertificateUrls = {
  'Colpensiones': 'https://sede.colpensiones.gov.co/',
  'Colfondos': 'https://www.colfondos.com.co/',
  'Porvenir': 'https://www.porvenir.com.co/',
  'Protección': 'https://www.proteccion.com/',
  'Skandia': 'https://www.skandia.com.co/',
};

const Map<String, String> _cesantiasCertificateUrls = {
  'Colfondos': 'https://www.colfondos.com.co/',
  'Fondo Nacional del Ahorro': 'https://www.fna.gov.co/',
  'Porvenir': 'https://www.porvenir.com.co/',
  'Protección': 'https://www.proteccion.com/',
  'Skandia': 'https://www.skandia.com.co/',
};

const Map<String, String> _bancoCertificateUrls = {
  'Bancolombia':
      'https://www.grupobancolombia.com/personas/productos-servicios/certificaciones',
  'Banco de Bogotá': 'https://sucursalpersonas.transaccionesbancobogota.com/',
  'Davivienda': 'https://micrositios.davivienda.com/personas/',
  'BBVA Colombia': 'https://www.bbva.com.co/personas/banca-online.html',
  'Banco Popular': 'https://www.bancopopular.com.co/',
  'Banco de Occidente': 'https://www.bancodeoccidente.com.co/',
  'Banco Agrario': 'https://www.bancoagrario.gov.co/',
  'Scotiabank Colpatria': 'https://www.scotiabankcolpatria.com/',
  'AV Villas': 'https://www.avvillas.com.co/',
  'Nequi': 'https://www.nequi.com.co/',
  'Nubank': 'https://nubank.com.co/',
  'Lulo Bank': 'https://www.lulobank.com/',
  'Banco Falabella': 'https://www.bancofalabella.com.co/',
  'Bancamía': 'https://www.bancamia.com.co/',
  'Confiar Cooperativa Financiera': 'https://www.confiar.coop/',
  'Otro': '',
};

// ── Modo de uso ────────────────────────────────────────────────────────────
enum HvMode {
  /// Primera vez: al terminar va a PreviewScreen para confirmar y enviar.
  registro,

  /// Usuario existente editando su perfil: guarda directamente via servicio.
  perfil,
}

// ── Formatters ─────────────────────────────────────────────────────────────
class _Lower extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(o, n) =>
      n.copyWith(text: n.text.toLowerCase());
}

class _Cap extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(o, n) {
    final words = n.text.toLowerCase().split(' ');
    final cap = words
        .map(
          (w) => w.isEmpty
              ? ''
              : w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''),
        )
        .join(' ');
    return n.copyWith(text: cap);
  }
}

// ── Modelos locales ────────────────────────────────────────────────────────
class _Cert {
  final nombre = TextEditingController();
  final fecha = TextEditingController();
  Uint8List? bytes;
  String? url;
  void dispose() {
    nombre.dispose();
    fecha.dispose();
  }
}

class _Exp {
  final empresa = TextEditingController();
  final cargo = TextEditingController();
  final inicio = TextEditingController();
  final fin = TextEditingController();
  Uint8List? soporteBytes;
  String? soporteUrl;
  void dispose() {
    empresa.dispose();
    cargo.dispose();
    inicio.dispose();
    fin.dispose();
  }
}

// ── Widget principal ───────────────────────────────────────────────────────
class HojaDeVidaScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final HvMode mode;

  const HojaDeVidaScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.mode,
  });

  @override
  State<HojaDeVidaScreen> createState() => _HojaDeVidaScreenState();
}

class _HojaDeVidaScreenState extends State<HojaDeVidaScreen> {
  final _svc = HojaDeVidaService();
  int _step = 0;
  final _keys = List.generate(6, (_) => GlobalKey<FormState>());
  bool _loading = true;

  // Estado de revisión de TH
  String? _estadoRevision;
  String? _revisionNota;
  dynamic _correctionRequestedAt;
  dynamic _correctionUpdatedAt;
  dynamic _correctionSubmittedAt;
  String? _correctionStatus;
  String? _loadWarning;

  // Paso 0 — Foto y datos personales
  Uint8List? _fotoBytes;
  String? _fotoUrl;
  String? _cedulaDocUrl;

  final _primerNombre = TextEditingController();
  final _segundoNombre = TextEditingController();
  final _primerApellido = TextEditingController();
  final _segundoApellido = TextEditingController();
  final _expDepartamentoCtrl = TextEditingController();
  final _lugarExpedicion = TextEditingController();
  final _email = TextEditingController();
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  final _resDepartamentoCtrl = TextEditingController();
  final _ciudad = TextEditingController();
  final _barrio = TextEditingController();
  final _eps = TextEditingController();
  final _fondoPensiones = TextEditingController();
  final _fondoCesantias = TextEditingController();
  String? _epsUrl, _pensionUrl, _cesantiasUrl;
  List<HvCatalogItem> _departamentos = [];
  List<HvCatalogItem> _expCiudades = [];
  List<HvCatalogItem> _resCiudades = [];
  List<HvCatalogItem> _nacCiudades = [];
  String? _expDepartamentoCod;
  String? _expDepartamentoNombre;
  String? _expCiudadCod;
  String? _resDepartamentoCod;
  String? _resDepartamentoNombre;
  String? _resCiudadCod;
  String? _nacDepartamentoCod;
  String? _nacDepartamentoNombre;
  String? _nacCiudadCod;

  // Paso 1 — Perfil demográfico (solo plataforma)
  String? _estadoCivil;
  final _estadoCivilCtrl = TextEditingController();
  final _numeroHijos = TextEditingController();
  String? _tipoSangre;
  final _tipoSangreCtrl = TextEditingController();
  final _contactoEmergenciaNombre = TextEditingController();
  final _contactoEmergenciaTelefono = TextEditingController();
  final _fechaNacimiento = TextEditingController();
  final _nacDepartamentoCtrl = TextEditingController();
  final _lugarNacimiento = TextEditingController();
  final _edad = TextEditingController();
  String? _genero;
  final _generoCtrl = TextEditingController();
  final _personasCargo = TextEditingController();
  final _estrato = TextEditingController();
  String? _tipoVehiculo;
  final _tipoVehiculoCtrl = TextEditingController();

  // Paso 2 — Antecedentes
  String? _procUrl, _contrUrl, _polUrl, _medUrl;
  String? _banco;
  final _bancoCtrl = TextEditingController();
  final _bancoOtroCtrl = TextEditingController(); // solo cuando eligen "Otro"
  String? _certBancoUrl;

  // Paso 3 — Formación académica
  final _bachInst = TextEditingController();
  final _bachFecha = TextEditingController();
  String? _bachUrl;

  bool _hasUni = false;
  final _uniInst = TextEditingController();
  final _uniCarr = TextEditingController();
  final _uniFecha = TextEditingController();
  String? _uniUrl;

  bool _hasTarjeta = false;
  final _tarjetaNum = TextEditingController();
  String? _tarjetaUrl;

  bool _hasSecond = false;
  final _secInst = TextEditingController();
  final _secCarr = TextEditingController();
  final _secFecha = TextEditingController();
  String? _secUrl;

  bool _hasEspecial = false;
  final _espInst = TextEditingController();
  final _espProg = TextEditingController();
  final _espFecha = TextEditingController();
  String? _espUrl;

  bool _hasMaestria = false;
  final _maeInst = TextEditingController();
  final _maeProg = TextEditingController();
  final _maeFecha = TextEditingController();
  String? _maeUrl;

  // Paso 4 — Cursos complementarios
  bool _hasCerts = false;
  final _certs = <_Cert>[];

  // Paso 5 — Experiencia laboral
  final _exps = <_Exp>[_Exp()];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Carga de datos ────────────────────────────────────────────────────────

  Future<void> _load() async {
    Map<String, dynamic> d = {};
    List<HvCatalogItem> departamentos = [];
    try {
      final results = await Future.wait([
        _svc.getHojaDeVida(widget.userId),
        _svc.getDepartamentos(),
      ]).timeout(const Duration(seconds: 8));
      d = results[0] as Map<String, dynamic>;
      departamentos = results[1] as List<HvCatalogItem>;
    } catch (e) {
      _loadWarning =
          'No se pudieron cargar datos previos. Puedes completar o actualizar tu hoja de vida desde cero.';
    }

    if (!mounted) return;
    setState(() {
      _departamentos = departamentos;
      _estadoRevision = d['estadoRevision'] as String?;
      _revisionNota = d['revisionNota'] as String?;
      _correctionRequestedAt = d['correctionRequestedAt'];
      _correctionUpdatedAt = d['correctionUpdatedAt'];
      _correctionSubmittedAt = d['correctionSubmittedAt'];
      _correctionStatus = d['correctionStatus'] as String?;

      _fotoUrl = d['fotoUrl'] as String?;
      _cedulaDocUrl = d['cedulaDocUrl'] as String?;

      _primerNombre.text = d['primerNombre'] ?? '';
      _segundoNombre.text = d['segundoNombre'] ?? '';
      _primerApellido.text = d['primerApellido'] ?? '';
      _segundoApellido.text = d['segundoApellido'] ?? '';
      _lugarExpedicion.text = d['lugarExpedicion'] ?? '';
      _expDepartamentoCod = d['lugarExpedicionDepartamentoCod'] as String?;
      _expDepartamentoNombre =
          d['lugarExpedicionDepartamentoNombre'] as String?;
      _expDepartamentoCtrl.text = _expDepartamentoNombre ?? '';
      _expCiudadCod = d['lugarExpedicionCiudadCod'] as String?;
      _email.text = d['email'] ?? '';
      _telefono.text = d['telefono'] ?? '';
      _direccion.text = d['direccion'] ?? '';
      _ciudad.text = d['ciudad'] ?? '';
      _resDepartamentoCod = d['residenciaDepartamentoCod'] as String?;
      _resDepartamentoNombre = d['residenciaDepartamentoNombre'] as String?;
      _resDepartamentoCtrl.text = _resDepartamentoNombre ?? '';
      _resCiudadCod = d['residenciaCiudadCod'] as String?;
      _barrio.text = d['barrio'] ?? '';
      _eps.text = d['eps'] ?? '';
      _fondoPensiones.text = d['fondoPensiones'] ?? '';
      _fondoCesantias.text = d['fondoCesantias'] ?? '';
      _epsUrl = d['epsUrl'] as String?;
      _pensionUrl = d['pensionUrl'] as String?;
      _cesantiasUrl = d['cesantiasUrl'] as String?;

      _estadoCivil = d['estadoCivil'] as String?;
      _estadoCivilCtrl.text = _estadoCivil ?? '';
      _numeroHijos.text = d['numeroHijos']?.toString() ?? '';
      _tipoSangre = d['tipoSangre'] as String?;
      _tipoSangreCtrl.text = _tipoSangre ?? '';
      _contactoEmergenciaNombre.text = d['contactoEmergenciaNombre'] ?? '';
      _contactoEmergenciaTelefono.text = d['contactoEmergenciaTelefono'] ?? '';
      _fechaNacimiento.text = d['fechaNacimiento'] ?? '';
      _lugarNacimiento.text = d['lugarNacimiento'] ?? '';
      _nacDepartamentoCod = d['nacimientoDepartamentoCod'] as String?;
      _nacDepartamentoNombre = d['nacimientoDepartamentoNombre'] as String?;
      _nacDepartamentoCtrl.text = _nacDepartamentoNombre ?? '';
      _nacCiudadCod = d['nacimientoCiudadCod'] as String?;
      _edad.text = d['edad']?.toString() ?? '';
      _genero = d['genero'] as String?;
      _generoCtrl.text = _genero ?? '';
      _personasCargo.text = d['personasCargo']?.toString() ?? '';
      _estrato.text = d['estrato']?.toString() ?? '';
      _tipoVehiculo = d['tipoVehiculo'] as String?;
      _tipoVehiculoCtrl.text = _tipoVehiculo ?? '';

      _procUrl = d['procUrl'] as String?;
      _contrUrl = d['contrUrl'] as String?;
      _polUrl = d['polUrl'] as String?;
      _medUrl = d['medUrl'] as String?;
      final savedBanco = d['banco'] as String? ?? '';
      if (savedBanco.isEmpty || _bancoCertificateUrls.containsKey(savedBanco)) {
        _banco = savedBanco.isEmpty ? null : savedBanco;
        _bancoCtrl.text = _banco ?? '';
      } else {
        // Valor personalizado (fue guardado como "Otro: NombreBanco")
        _banco = 'Otro';
        _bancoCtrl.text = 'Otro';
        _bancoOtroCtrl.text = savedBanco;
      }
      _certBancoUrl = d['certBancoUrl'] as String?;

      _bachInst.text = d['bachInst'] ?? '';
      _bachFecha.text = d['bachFecha'] ?? '';
      _bachUrl = d['bachillerUrl'] as String?;

      _hasUni = d['hasUniversity'] ?? false;
      _uniInst.text = d['uniInst'] ?? '';
      _uniCarr.text = d['uniCarr'] ?? '';
      _uniFecha.text = d['uniFecha'] ?? '';
      _uniUrl = d['uniUrl'] as String?;

      _hasTarjeta = d['hasTarjetaProf'] ?? false;
      _tarjetaNum.text = d['tarjetaNumero'] ?? '';
      _tarjetaUrl = d['tarjetaUrl'] as String?;

      _hasSecond = d['hasSecondCareer'] ?? false;
      _secInst.text = d['secInst'] ?? '';
      _secCarr.text = d['secCarr'] ?? '';
      _secFecha.text = d['secFecha'] ?? '';
      _secUrl = d['secUrl'] as String?;

      _hasEspecial = d['hasEspecializacion'] ?? false;
      _espInst.text = d['espInst'] ?? '';
      _espProg.text = d['espProg'] ?? '';
      _espFecha.text = d['espFecha'] ?? '';
      _espUrl = d['espUrl'] as String?;

      _hasMaestria = d['hasMaestria'] ?? false;
      _maeInst.text = d['maeInst'] ?? '';
      _maeProg.text = d['maeProg'] ?? '';
      _maeFecha.text = d['maeFecha'] ?? '';
      _maeUrl = d['maeUrl'] as String?;

      _hasCerts = d['hasCertificados'] ?? false;
      _certs.clear();
      if (_hasCerts) {
        for (final c in (d['certificados'] as List<dynamic>? ?? [])) {
          _certs.add(
            _Cert()
              ..nombre.text = c['nombre'] ?? ''
              ..fecha.text = c['fecha'] ?? ''
              ..url = c['url'] as String?,
          );
        }
      }

      _exps.clear();
      for (final e in (d['experiencias'] as List<dynamic>? ?? [])) {
        _exps.add(
          _Exp()
            ..empresa.text = e['empresa'] ?? ''
            ..cargo.text = e['cargo'] ?? ''
            ..inicio.text = e['inicio'] ?? ''
            ..fin.text = e['fin'] ?? ''
            ..soporteUrl = e['soporteUrl'] as String?,
        );
      }
      if (_exps.isEmpty) _exps.add(_Exp());

      _loading = false;
    });

    await _hydrateCatalogSelections();

    if (_estadoRevision == 'requiere_cambios' &&
        (_revisionNota?.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showRevisionBanner(),
      );
    }
  }

  void _showRevisionBanner() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Corrección requerida por Talento Humano'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_revisionNota!),
            if (_formatHvDateTime(_correctionRequestedAt).isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Devuelta: ${_formatHvDateTime(_correctionRequestedAt)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _hydrateCatalogSelections() async {
    _hydrateDepartmentText(
      _expDepartamentoCod,
      _expDepartamentoCtrl,
      (name) => _expDepartamentoNombre = name,
    );
    _hydrateDepartmentText(
      _resDepartamentoCod,
      _resDepartamentoCtrl,
      (name) => _resDepartamentoNombre = name,
    );
    _hydrateDepartmentText(
      _nacDepartamentoCod,
      _nacDepartamentoCtrl,
      (name) => _nacDepartamentoNombre = name,
    );
    await Future.wait([
      if ((_expDepartamentoCod ?? '').isNotEmpty)
        _loadCiudades(
          _expDepartamentoCod!,
          (items) => _expCiudades = items,
          cityName: _lugarExpedicion.text,
          setCityCode: (code) => _expCiudadCod = code,
        ),
      if ((_resDepartamentoCod ?? '').isNotEmpty)
        _loadCiudades(
          _resDepartamentoCod!,
          (items) => _resCiudades = items,
          cityName: _ciudad.text,
          setCityCode: (code) => _resCiudadCod = code,
        ),
      if ((_nacDepartamentoCod ?? '').isNotEmpty)
        _loadCiudades(
          _nacDepartamentoCod!,
          (items) => _nacCiudades = items,
          cityName: _lugarNacimiento.text,
          setCityCode: (code) => _nacCiudadCod = code,
        ),
    ]);
    if (mounted) setState(() {});
  }

  void _hydrateDepartmentText(
    String? code,
    TextEditingController controller,
    ValueChanged<String?> setName,
  ) {
    final item = _catalogValue(_departamentos, code);
    if (item == null) return;
    controller.text = item.name;
    setName(item.name);
  }

  Future<void> _loadCiudades(
    String departamentoCode,
    void Function(List<HvCatalogItem>) assign, {
    String? cityName,
    void Function(String?)? setCityCode,
  }) async {
    final items = await _svc.getCiudades(departamentoCode);
    assign(items);
    final currentCityName = cityName?.trim().toLowerCase() ?? '';
    if (currentCityName.isNotEmpty && setCityCode != null) {
      for (final item in items) {
        if (item.name.toLowerCase() == currentCityName) {
          setCityCode(item.code);
          break;
        }
      }
    }
  }

  // ── Upload helpers ─────────────────────────────────────────────────────────

  Future<String> _upload(String tag, Uint8List bytes, String ext) =>
      _svc.uploadFile(widget.userId, tag, bytes, ext);

  Future<void> _pickPhoto() async {
    Uint8List? bytes;
    String ext = 'jpg';
    if (kIsWeb) {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (r == null) return;
      bytes = r.files.single.bytes!;
      ext = r.files.single.extension ?? 'jpg';
    } else {
      final picker = ImagePicker();
      final src = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Cámara'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galería'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (src == null) return;
      final picked = await picker.pickImage(source: src, imageQuality: 80);
      if (picked == null) return;
      bytes = await picked.readAsBytes();
      ext = picked.path.split('.').last;
    }
    final url = await _upload('foto', bytes, ext);
    setState(() {
      _fotoBytes = bytes;
      _fotoUrl = url;
    });
  }

  Future<void> _pickDoc(
    String tag,
    void Function(String url) onUrl, {
    void Function(Uint8List b)? onBytes,
  }) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (r == null) return;
    final f = r.files.single;
    final ext = (f.extension ?? '').toLowerCase();
    if (ext != 'pdf') {
      _showErr('Solo se permiten documentos en formato PDF.');
      return;
    }
    final bytes = f.bytes;
    if (bytes == null) {
      _showErr('No se pudo leer el archivo seleccionado.');
      return;
    }
    onBytes?.call(bytes);
    final url = await _upload(tag, bytes, 'pdf');
    onUrl(url);
    setState(() {});
  }

  Future<void> _pickMonthYear(TextEditingController ctrl) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('es', 'ES'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: Theme.of(context).colorScheme.primary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      ctrl.text = DateFormat('MM/yyyy', 'es').format(picked);
    }
  }

  Future<void> _pickFullDate(TextEditingController ctrl) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(DateTime.now().year - 25),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('es', 'ES'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: Theme.of(context).colorScheme.primary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    ctrl.text = DateFormat('dd/MM/yyyy', 'es').format(picked);
    if (identical(ctrl, _fechaNacimiento)) {
      _edad.text = _calculateAge(picked).toString();
    }
  }

  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    final hadBirthday =
        now.month > birthDate.month ||
        (now.month == birthDate.month && now.day >= birthDate.day);
    if (!hadBirthday) age--;
    return age < 0 ? 0 : age;
  }

  // ── Navegación entre pasos ─────────────────────────────────────────────────

  Future<void> _onContinue() async {
    if (!_keys[_step].currentState!.validate()) return;

    // Validaciones de archivos por paso
    if (_step == 0) {
      if (_fotoUrl == null) {
        _showErr('Debes subir o tomar tu foto');
        return;
      }
      if (_cedulaDocUrl == null) {
        _showErr('Debes subir el documento de cédula');
        return;
      }
      if (_epsUrl == null || _pensionUrl == null || _cesantiasUrl == null) {
        _showErr(
          'Debes subir los soportes de EPS, pensiones y cesantías en PDF',
        );
        return;
      }
    }
    if (_step == 2) {
      if (_procUrl == null ||
          _contrUrl == null ||
          _polUrl == null ||
          _medUrl == null) {
        _showErr('Completa todos los antecedentes');
        return;
      }
      if (_banco == null || _banco!.isEmpty) {
        _showErr('Selecciona tu banco');
        return;
      }
      if (_banco == 'Otro' && _bancoOtroCtrl.text.trim().isEmpty) {
        _showErr('Escribe el nombre de tu banco');
        return;
      }
      if (_certBancoUrl == null) {
        _showErr('Sube el certificado bancario');
        return;
      }
    }
    if (_step == 3) {
      if (_bachInst.text.isEmpty ||
          _bachFecha.text.isEmpty ||
          _bachUrl == null) {
        _showErr('Completa bachillerato y sube el soporte');
        return;
      }
      if (_hasUni &&
          (_uniInst.text.isEmpty ||
              _uniCarr.text.isEmpty ||
              _uniFecha.text.isEmpty ||
              _uniUrl == null)) {
        _showErr('Completa los datos universitarios y sube el soporte');
        return;
      }
      if (_hasUni &&
          _hasTarjeta &&
          (_tarjetaNum.text.isEmpty || _tarjetaUrl == null)) {
        _showErr('Completa tarjeta profesional');
        return;
      }
    }
    if (_step == 4 && _hasCerts) {
      for (final c in _certs) {
        if (c.nombre.text.isEmpty || c.fecha.text.isEmpty || c.url == null) {
          _showErr('Completa todos los cursos y sube sus soportes');
          return;
        }
      }
    }
    if (_step == 5) {
      for (final e in _exps) {
        if (e.empresa.text.isEmpty ||
            e.cargo.text.isEmpty ||
            e.inicio.text.isEmpty ||
            e.fin.text.isEmpty) {
          _showErr('Completa todos los datos de experiencia');
          return;
        }
        if (e.soporteUrl == null) {
          _showErr('Sube el soporte para cada experiencia laboral');
          return;
        }
      }
    }

    if (_step < 5) {
      setState(() => _step++);
      return;
    }

    // Último paso → acción según modo
    await _finalizar();
  }

  void _onCancel() {
    if (_step > 0) setState(() => _step--);
  }

  // ── Finalizar ───────────────────────────────────────────────────────────────

  Future<void> _finalizar() async {
    final cvData = _buildCvData();
    if (widget.mode == HvMode.registro) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            data: {
              ...cvData,
              'cedula': widget.userId,
              'empresaId': widget.empresaId,
              'fotoBytes': _fotoBytes,
              'fotoUrl': _fotoUrl!,
            },
          ),
        ),
      );
    } else {
      await _guardarPerfil(cvData);
    }
  }

  Future<void> _saveDraftNow() async {
    final cvData = _buildCvData();
    try {
      await _svc.saveDraft(widget.userId, cvData);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Borrador guardado correctamente'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar borrador: $e')));
    }
  }

  Future<void> _guardarPerfil(Map<String, dynamic> cvData) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar actualización'),
        content: const Text(
          'Se enviará tu hoja de vida a Talento Humano para revisión.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    _showLoading('Guardando...');
    try {
      if (_fotoBytes != null) {
        cvData['fotoUrl'] = await _upload('foto', _fotoBytes!, 'jpg');
      }
      await _svc.saveHojaDeVida(widget.userId, widget.empresaId, cvData);
      if (!mounted) return;
      Navigator.of(context).pop(); // cierra loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hoja de vida enviada a Talento Humano')),
      );
      Navigator.of(context).pop(); // vuelve al home
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErr('Error al guardar: $e');
    }
  }

  Map<String, dynamic> _buildCvData() => {
    'fotoUrl': _fotoUrl,
    'cedulaDocUrl': _cedulaDocUrl,
    'primerNombre': _primerNombre.text.trim(),
    'segundoNombre': _segundoNombre.text.trim(),
    'primerApellido': _primerApellido.text.trim(),
    'segundoApellido': _segundoApellido.text.trim(),
    'lugarExpedicion': _lugarExpedicion.text.trim(),
    'lugarExpedicionDepartamentoCod': _expDepartamentoCod,
    'lugarExpedicionDepartamentoNombre': _expDepartamentoNombre,
    'lugarExpedicionCiudadCod': _expCiudadCod,
    'lugarExpedicionCiudadNombre': _lugarExpedicion.text.trim(),
    'email': _email.text.trim(),
    'telefono': _telefono.text.trim(),
    'direccion': _direccion.text.trim(),
    'ciudad': _ciudad.text.trim(),
    'residenciaDepartamentoCod': _resDepartamentoCod,
    'residenciaDepartamentoNombre': _resDepartamentoNombre,
    'residenciaCiudadCod': _resCiudadCod,
    'residenciaCiudadNombre': _ciudad.text.trim(),
    'barrio': _barrio.text.trim(),
    'eps': _eps.text.trim(),
    'fondoPensiones': _fondoPensiones.text.trim(),
    'fondoCesantias': _fondoCesantias.text.trim(),
    'epsUrl': _epsUrl,
    'pensionUrl': _pensionUrl,
    'cesantiasUrl': _cesantiasUrl,
    'estadoCivil': _estadoCivilCtrl.text.trim(),
    'numeroHijos': _numeroHijos.text.trim(),
    'tipoSangre': _tipoSangreCtrl.text.trim(),
    'contactoEmergenciaNombre': _contactoEmergenciaNombre.text.trim(),
    'contactoEmergenciaTelefono': _contactoEmergenciaTelefono.text.trim(),
    'fechaNacimiento': _fechaNacimiento.text.trim(),
    'lugarNacimiento': _lugarNacimiento.text.trim(),
    'nacimientoDepartamentoCod': _nacDepartamentoCod,
    'nacimientoDepartamentoNombre': _nacDepartamentoNombre,
    'nacimientoCiudadCod': _nacCiudadCod,
    'nacimientoCiudadNombre': _lugarNacimiento.text.trim(),
    'edad': _edad.text.trim(),
    'genero': _generoCtrl.text.trim(),
    'personasCargo': _personasCargo.text.trim(),
    'estrato': _estrato.text.trim(),
    'tipoVehiculo': _tipoVehiculoCtrl.text.trim(),
    'procUrl': _procUrl,
    'contrUrl': _contrUrl,
    'polUrl': _polUrl,
    'medUrl': _medUrl,
    'banco': _banco == 'Otro' ? _bancoOtroCtrl.text.trim() : _banco,
    'certBancoUrl': _certBancoUrl,
    'bachInst': _bachInst.text.trim(),
    'bachFecha': _bachFecha.text.trim(),
    'bachillerUrl': _bachUrl,
    'hasUniversity': _hasUni,
    'uniInst': _uniInst.text.trim(),
    'uniCarr': _uniCarr.text.trim(),
    'uniFecha': _uniFecha.text.trim(),
    'uniUrl': _uniUrl,
    'hasTarjetaProf': _hasTarjeta,
    'tarjetaNumero': _tarjetaNum.text.trim(),
    'tarjetaUrl': _tarjetaUrl,
    'hasSecondCareer': _hasSecond,
    'secInst': _secInst.text.trim(),
    'secCarr': _secCarr.text.trim(),
    'secFecha': _secFecha.text.trim(),
    'secUrl': _secUrl,
    'hasEspecializacion': _hasEspecial,
    'espInst': _espInst.text.trim(),
    'espProg': _espProg.text.trim(),
    'espFecha': _espFecha.text.trim(),
    'espUrl': _espUrl,
    'hasMaestria': _hasMaestria,
    'maeInst': _maeInst.text.trim(),
    'maeProg': _maeProg.text.trim(),
    'maeFecha': _maeFecha.text.trim(),
    'maeUrl': _maeUrl,
    'hasCertificados': _hasCerts,
    'certificados': _certs
        .map(
          (c) => {
            'nombre': c.nombre.text.trim(),
            'fecha': c.fecha.text.trim(),
            'url': c.url,
          },
        )
        .toList(),
    'experiencias': _exps
        .map(
          (e) => {
            'empresa': e.empresa.text.trim(),
            'cargo': e.cargo.text.trim(),
            'inicio': e.inicio.text.trim(),
            'fin': e.fin.text.trim(),
            'soporteUrl': e.soporteUrl,
          },
        )
        .toList(),
  };

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showErr(String msg) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  void _showLoading(String msg) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(msg)),
        ],
      ),
    ),
  );

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _primerNombre.dispose();
    _segundoNombre.dispose();
    _primerApellido.dispose();
    _segundoApellido.dispose();
    _expDepartamentoCtrl.dispose();
    _lugarExpedicion.dispose();
    _email.dispose();
    _telefono.dispose();
    _direccion.dispose();
    _resDepartamentoCtrl.dispose();
    _ciudad.dispose();
    _barrio.dispose();
    _eps.dispose();
    _fondoPensiones.dispose();
    _fondoCesantias.dispose();
    _estadoCivilCtrl.dispose();
    _numeroHijos.dispose();
    _tipoSangreCtrl.dispose();
    _contactoEmergenciaNombre.dispose();
    _contactoEmergenciaTelefono.dispose();
    _fechaNacimiento.dispose();
    _nacDepartamentoCtrl.dispose();
    _lugarNacimiento.dispose();
    _edad.dispose();
    _generoCtrl.dispose();
    _personasCargo.dispose();
    _estrato.dispose();
    _tipoVehiculoCtrl.dispose();
    _bancoCtrl.dispose();
    _bancoOtroCtrl.dispose();
    _bachInst.dispose();
    _bachFecha.dispose();
    _uniInst.dispose();
    _uniCarr.dispose();
    _uniFecha.dispose();
    _tarjetaNum.dispose();
    _secInst.dispose();
    _secCarr.dispose();
    _secFecha.dispose();
    _espInst.dispose();
    _espProg.dispose();
    _espFecha.dispose();
    _maeInst.dispose();
    _maeProg.dispose();
    _maeFecha.dispose();
    for (final c in _certs) {
      c.dispose();
    }
    for (final e in _exps) {
      e.dispose();
    }
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;
    final title = widget.mode == HvMode.registro
        ? 'Registro de Hoja de Vida'
        : 'Mi Hoja de Vida';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (_loading)
            const _LoadInfoBanner(
              message:
                  'Preparando tu hoja de vida. Puedes empezar a completar la información mientras cargan datos previos.',
            ),
          if (_loadWarning != null) _LoadWarningBanner(message: _loadWarning!),
          if (_estadoRevision == 'requiere_cambios' &&
              (_revisionNota?.isNotEmpty ?? false))
            _RevisionBanner(
              nota: _revisionNota!,
              requestedAt: _correctionRequestedAt,
              updatedAt: _correctionUpdatedAt,
              submittedAt: _correctionSubmittedAt,
              status: _correctionStatus,
            ),
          if (_estadoRevision == 'aprobado')
            _StatusBanner(
              label: 'Hoja de vida aprobada por Talento Humano',
              color: Colors.green.shade700,
              icon: Icons.check_circle,
            ),
          if (_estadoRevision == 'en_revision')
            _StatusBanner(
              label: 'En revisión por Talento Humano',
              color: Colors.orange.shade700,
              icon: Icons.hourglass_top,
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 28 : 0,
                vertical: isDesktop ? 20 : 0,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isDesktop) ...[
                        _FormIntroCard(primary: primary),
                        const SizedBox(height: 16),
                      ],
                      Card(
                        elevation: isDesktop ? 2 : 0,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            isDesktop ? 18 : 0,
                          ),
                        ),
                        child: Stepper(
                          type: StepperType.vertical,
                          currentStep: _step,
                          physics: const ClampingScrollPhysics(),
                          onStepContinue: _onContinue,
                          onStepCancel: _onCancel,
                          controlsBuilder: (ctx, d) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 14,
                                    ),
                                  ),
                                  onPressed: d.onStepContinue,
                                  icon: Icon(
                                    _step < 5
                                        ? Icons.arrow_forward_rounded
                                        : Icons.check_rounded,
                                  ),
                                  label: Text(
                                    _step < 5
                                        ? 'Siguiente'
                                        : widget.mode == HvMode.registro
                                        ? 'Vista previa'
                                        : 'Enviar a TH',
                                  ),
                                ),
                                if (_step > 0)
                                  OutlinedButton.icon(
                                    onPressed: d.onStepCancel,
                                    icon: const Icon(Icons.arrow_back_rounded),
                                    label: const Text('Atrás'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      ),
                                    ),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: _saveDraftNow,
                                  icon: const Icon(Icons.save_outlined),
                                  label: const Text('Guardar borrador'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          steps: [
                            _step0(primary),
                            _stepDemografico(primary),
                            _step1(primary),
                            _step2(primary),
                            _step3(primary),
                            _step4(primary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Paso 0: Datos personales ───────────────────────────────────────────────

  Step _step0(Color primary) => Step(
    title: const Text('Datos Personales'),
    isActive: _step >= 0,
    content: Form(
      key: _keys[0],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('FOTO DE PERFIL'),
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: CircleAvatar(
                radius: 55,
                backgroundColor: Colors.grey[200],
                backgroundImage: _fotoBytes != null
                    ? MemoryImage(_fotoBytes!)
                    : (_fotoUrl != null
                          ? NetworkImage(_fotoUrl!) as ImageProvider
                          : null),
                child: (_fotoBytes == null && _fotoUrl == null)
                    ? const Icon(
                        Icons.add_a_photo,
                        size: 40,
                        color: Colors.grey,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.camera_alt),
              label: Text(
                _fotoUrl == null
                    ? 'Agregar imagen / foto de perfil'
                    : 'Cambiar imagen / foto de perfil',
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Esta imagen se usará como foto de la hoja de vida y del perfil.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 12),
          _sectionLabel('DATOS PARA LA HOJA DE VIDA'),
          _gap(),
          _field(_primerNombre, 'Primer Nombre', formatters: [_nameFilter()]),
          _gap(),
          _field(
            _segundoNombre,
            'Segundo Nombre',
            mandatory: false,
            formatters: [_nameFilter()],
          ),
          _gap(),
          _field(
            _primerApellido,
            'Primer Apellido',
            formatters: [_nameFilter()],
          ),
          _gap(),
          _field(
            _segundoApellido,
            'Segundo Apellido',
            mandatory: false,
            formatters: [_nameFilter()],
          ),
          _gap(),
          TextFormField(
            initialValue: widget.userId,
            decoration: const InputDecoration(labelText: 'Cédula'),
            enabled: false,
          ),
          _gap(),
          _departmentCityPicker(
            departmentLabel: 'Departamento de expedición',
            cityLabel: 'Ciudad de expedición',
            departmentController: _expDepartamentoCtrl,
            cityController: _lugarExpedicion,
            departmentCode: _expDepartamentoCod,
            ciudades: _expCiudades,
            onDepartmentChanged: (dep) => _onDepartmentChanged(
              dep,
              assignDepartment: (code, name) {
                _expDepartamentoCod = code;
                _expDepartamentoNombre = name;
              },
              assignCities: (items) => _expCiudades = items,
              assignCity: (code, name) {
                _expCiudadCod = code;
                _lugarExpedicion.text = name ?? '';
              },
            ),
            onCityChanged: (city) => setState(() {
              _expCiudadCod = city?.code;
              _lugarExpedicion.text = city?.name ?? '';
            }),
          ),
          _gap(),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            inputFormatters: [_Lower()],
            decoration: const InputDecoration(labelText: 'Correo electrónico'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Obligatorio';
              if (!RegExp(
                r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$',
              ).hasMatch(v.trim())) {
                return 'Formato inválido';
              }
              return null;
            },
          ),
          _gap(),
          _field(
            _telefono,
            'Teléfono',
            keyboard: TextInputType.phone,
            caseFormatter: _Lower(),
            formatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          _gap(),
          _field(
            _direccion,
            'Dirección de residencia',
            helperText:
                'Ej: calle 118 83A 59  —  solo letras, números y espacios',
            formatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'[A-Za-zÁÉÍÓÚáéíóúñÑ0-9 ]'),
              ),
            ],
          ),
          _gap(),
          _departmentCityPicker(
            departmentLabel: 'Departamento de residencia',
            cityLabel: 'Ciudad de residencia',
            departmentController: _resDepartamentoCtrl,
            cityController: _ciudad,
            departmentCode: _resDepartamentoCod,
            ciudades: _resCiudades,
            onDepartmentChanged: (dep) => _onDepartmentChanged(
              dep,
              assignDepartment: (code, name) {
                _resDepartamentoCod = code;
                _resDepartamentoNombre = name;
              },
              assignCities: (items) => _resCiudades = items,
              assignCity: (code, name) {
                _resCiudadCod = code;
                _ciudad.text = name ?? '';
              },
            ),
            onCityChanged: (city) => setState(() {
              _resCiudadCod = city?.code;
              _ciudad.text = city?.name ?? '';
            }),
          ),
          _gap(),
          _field(_barrio, 'Barrio'),
          _gap(),
          _searchableTextField(
            controller: _eps,
            label: 'EPS',
            options: _epsOptions,
          ),
          _certificateLink(
            controller: _eps,
            urls: _epsCertificateUrls,
            label: 'certificado EPS',
            fallbackUrl:
                'https://servicios.adres.gov.co/BDUA/Consulta-Afiliados-BDUA',
            fallbackLabel: 'Consultar afiliación en ADRES',
          ),
          _gap(),
          _docBtn(
            label: 'Soporte EPS (PDF)',
            url: _epsUrl,
            onTap: () => _pickDoc('eps', (u) => _epsUrl = u),
          ),
          _gap(),
          _searchableTextField(
            controller: _fondoPensiones,
            label: 'Fondo de pensiones',
            options: _fondoPensionesOptions,
          ),
          _certificateLink(
            controller: _fondoPensiones,
            urls: _pensionCertificateUrls,
            label: 'certificado de pensiones',
          ),
          _gap(),
          _docBtn(
            label: 'Soporte fondo de pensiones (PDF)',
            url: _pensionUrl,
            onTap: () => _pickDoc('fondo_pensiones', (u) => _pensionUrl = u),
          ),
          _gap(),
          _searchableTextField(
            controller: _fondoCesantias,
            label: 'Fondo de cesantías',
            options: _fondoCesantiasOptions,
          ),
          _certificateLink(
            controller: _fondoCesantias,
            urls: _cesantiasCertificateUrls,
            label: 'certificado de cesantías',
          ),
          _gap(),
          _docBtn(
            label: 'Soporte fondo de cesantías (PDF)',
            url: _cesantiasUrl,
            onTap: () => _pickDoc('fondo_cesantias', (u) => _cesantiasUrl = u),
          ),
          _gap(),
          _docBtn(
            label: 'Documento de cédula (PDF)',
            url: _cedulaDocUrl,
            onTap: () => _pickDoc('cedula', (u) => _cedulaDocUrl = u),
          ),
        ],
      ),
    ),
  );

  // ── Paso 1: Perfil demográfico ────────────────────────────────────────────

  Step _stepDemografico(Color primary) => Step(
    title: const Text('Perfil demográfico'),
    isActive: _step >= 1,
    content: Form(
      key: _keys[1],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('PERFIL DEMOGRÁFICO'),
          _gap(),
          _infoPanel(
            icon: Icons.lock_outline_rounded,
            title: 'Información solo para la plataforma',
            text:
                'Estos datos apoyan la gestión interna de Talento Humano y no se incluyen en la hoja de vida en PDF.',
          ),
          _gap(),
          _selectField(
            label: 'Estado civil',
            controller: _estadoCivilCtrl,
            options: _estadoCivilOptions,
            onChanged: (v) => _estadoCivil = v,
          ),
          _gap(),
          _field(
            _numeroHijos,
            'Número de hijos',
            keyboard: TextInputType.number,
            caseFormatter: _Lower(),
            formatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          _gap(),
          _selectField(
            label: 'Tipo de sangre',
            controller: _tipoSangreCtrl,
            options: _tipoSangreOptions,
            onChanged: (v) => _tipoSangre = v,
          ),
          _gap(),
          _fullDatePicker(_fechaNacimiento, 'Fecha de nacimiento'),
          _gap(),
          _departmentCityPicker(
            departmentLabel: 'Departamento de nacimiento',
            cityLabel: 'Ciudad de nacimiento',
            departmentController: _nacDepartamentoCtrl,
            cityController: _lugarNacimiento,
            departmentCode: _nacDepartamentoCod,
            ciudades: _nacCiudades,
            onDepartmentChanged: (dep) => _onDepartmentChanged(
              dep,
              assignDepartment: (code, name) {
                _nacDepartamentoCod = code;
                _nacDepartamentoNombre = name;
              },
              assignCities: (items) => _nacCiudades = items,
              assignCity: (code, name) {
                _nacCiudadCod = code;
                _lugarNacimiento.text = name ?? '';
              },
            ),
            onCityChanged: (city) => setState(() {
              _nacCiudadCod = city?.code;
              _lugarNacimiento.text = city?.name ?? '';
            }),
          ),
          _gap(),
          TextFormField(
            controller: _edad,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Edad',
              helperText:
                  'Se calcula con la fecha de nacimiento, pero puedes ajustarla.',
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Obligatorio' : null,
          ),
          _gap(),
          _selectField(
            label: 'Género',
            controller: _generoCtrl,
            options: _generoOptions,
            onChanged: (v) => _genero = v,
          ),
          _gap(),
          _field(
            _personasCargo,
            'Personas a cargo',
            keyboard: TextInputType.number,
            caseFormatter: _Lower(),
            formatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          _gap(),
          _field(
            _estrato,
            'Estrato',
            keyboard: TextInputType.number,
            caseFormatter: _Lower(),
            formatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          _gap(),
          _selectField(
            label: 'Tipo de vehículo o transporte',
            controller: _tipoVehiculoCtrl,
            options: _tipoVehiculoOptions,
            onChanged: (v) => _tipoVehiculo = v,
          ),
          _gap(),
          _field(
            _contactoEmergenciaNombre,
            'Nombre contacto de emergencia',
            formatters: [_nameFilter()],
          ),
          _gap(),
          _field(
            _contactoEmergenciaTelefono,
            'Teléfono contacto de emergencia',
            keyboard: TextInputType.phone,
            caseFormatter: _Lower(),
            formatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ],
      ),
    ),
  );

  // ── Paso 1: Adjuntos (Antecedentes + Datos Bancarios) ─────────────────────

  Step _step1(Color primary) => Step(
    title: const Text('Adjuntos'),
    isActive: _step >= 2,
    content: Form(
      key: _keys[2],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _antecedente(
            primary: primary,
            label: 'Procuraduría',
            url: _procUrl,
            externalUrl:
                'https://www.procuraduria.gov.co/Pages/Generacion-de-antecedentes.aspx',
            onPick: () =>
                _pickDoc('procuraduria', (u) => setState(() => _procUrl = u)),
          ),
          _gap(),
          _antecedente(
            primary: primary,
            label: 'Contraloría',
            url: _contrUrl,
            externalUrl:
                'https://www.contraloria.gov.co/control-fiscal/responsabilidad-fiscal/certificado-de-antecedentes-fiscales',
            onPick: () =>
                _pickDoc('contraloria', (u) => setState(() => _contrUrl = u)),
          ),
          _gap(),
          _antecedente(
            primary: primary,
            label: 'Policía Nacional',
            url: _polUrl,
            externalUrl:
                'https://antecedentes.policia.gov.co:7005/WebJudicial/',
            onPick: () =>
                _pickDoc('policia', (u) => setState(() => _polUrl = u)),
          ),
          _gap(),
          _antecedente(
            primary: primary,
            label: 'Medidas Correctivas',
            url: _medUrl,
            externalUrl:
                'https://srvcnpc.policia.gov.co/PSC/frm_cnp_consulta.aspx',
            onPick: () =>
                _pickDoc('medidas', (u) => setState(() => _medUrl = u)),
          ),
          _gap(),
          const Divider(),
          _gap(),
          _sectionLabel('DATOS BANCARIOS'),
          _gap(),
          _selectField(
            label: 'Banco',
            controller: _bancoCtrl,
            options: _bancoCertificateUrls.keys.toList(),
            onChanged: (v) => setState(() {
              _banco = v;
              _bancoCtrl.text = v ?? '';
              if (v != 'Otro') _bancoOtroCtrl.clear();
            }),
          ),
          if (_banco == 'Otro') ...[
            _gap(),
            TextFormField(
              controller: _bancoOtroCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre de tu banco',
                hintText: 'Ej: Banco W, Bancoomeva…',
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Escribe el nombre del banco'
                  : null,
            ),
            _gap(),
            const Text(
              'Ingresa a tu banco en línea y descarga el certificado de cuenta.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ] else if (_banco != null && _banco!.isNotEmpty) ...[
            _gap(),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: Text('Ir a $_banco para descargar el certificado'),
              onPressed: (_bancoCertificateUrls[_banco] ?? '').isEmpty
                  ? null
                  : () => launchUrlString(
                      _bancoCertificateUrls[_banco]!,
                      mode: LaunchMode.externalApplication,
                    ),
            ),
          ],
          _gap(),
          _docBtn(
            label: 'Certificado bancario (PDF)',
            url: _certBancoUrl,
            onTap: () => _pickDoc(
              'cert_banco',
              (u) => setState(() => _certBancoUrl = u),
            ),
          ),
        ],
      ),
    ),
  );

  // ── Paso 2: Formación académica ────────────────────────────────────────────

  Step _step2(Color primary) => Step(
    title: const Text('Formación Académica'),
    isActive: _step >= 3,
    content: Form(
      key: _keys[3],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('BACHILLERATO'),
          _gap(),
          _field(_bachInst, 'Institución'),
          _gap(),
          _datePicker(_bachFecha, 'Fecha de grado (MM/AAAA)'),
          _gap(),
          _docBtn(
            label: 'Soporte bachillerato',
            url: _bachUrl,
            onTap: () => _pickDoc('bachillerato', (u) => _bachUrl = u),
          ),
          const SizedBox(height: 20),
          _checkSection(
            title: 'Formación Universitaria',
            value: _hasUni,
            onChanged: (v) => setState(() => _hasUni = v),
            children: [
              _field(_uniInst, 'Institución'),
              _gap(),
              _field(_uniCarr, 'Carrera / Programa'),
              _gap(),
              _datePicker(_uniFecha, 'Fecha de grado (MM/AAAA)'),
              _gap(),
              _docBtn(
                label: 'Soporte universidad',
                url: _uniUrl,
                onTap: () => _pickDoc('universidad', (u) => _uniUrl = u),
              ),
              _gap(),
              _checkSection(
                title: '¿Tiene Tarjeta Profesional?',
                value: _hasTarjeta,
                onChanged: (v) => setState(() => _hasTarjeta = v),
                children: [
                  _field(_tarjetaNum, 'Número de tarjeta profesional'),
                  _gap(),
                  _docBtn(
                    label: 'Soporte tarjeta profesional',
                    url: _tarjetaUrl,
                    onTap: () =>
                        _pickDoc('tarjeta_profesional', (u) => _tarjetaUrl = u),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          _checkSection(
            title: 'Segunda Carrera',
            value: _hasSecond,
            onChanged: (v) => setState(() => _hasSecond = v),
            children: [
              _field(_secInst, 'Institución'),
              _gap(),
              _field(_secCarr, 'Carrera / Programa'),
              _gap(),
              _datePicker(_secFecha, 'Fecha de grado (MM/AAAA)'),
              _gap(),
              _docBtn(
                label: 'Soporte segunda carrera',
                url: _secUrl,
                onTap: () => _pickDoc('segunda_carrera', (u) => _secUrl = u),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _checkSection(
            title: 'Especialización',
            value: _hasEspecial,
            onChanged: (v) => setState(() => _hasEspecial = v),
            children: [
              _field(_espInst, 'Institución'),
              _gap(),
              _field(_espProg, 'Programa'),
              _gap(),
              _datePicker(_espFecha, 'Fecha de grado (MM/AAAA)'),
              _gap(),
              _docBtn(
                label: 'Soporte especialización',
                url: _espUrl,
                onTap: () => _pickDoc('especializacion', (u) => _espUrl = u),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _checkSection(
            title: 'Maestría',
            value: _hasMaestria,
            onChanged: (v) => setState(() => _hasMaestria = v),
            children: [
              _field(_maeInst, 'Institución'),
              _gap(),
              _field(_maeProg, 'Programa'),
              _gap(),
              _datePicker(_maeFecha, 'Fecha de grado (MM/AAAA)'),
              _gap(),
              _docBtn(
                label: 'Soporte maestría',
                url: _maeUrl,
                onTap: () => _pickDoc('maestria', (u) => _maeUrl = u),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // ── Paso 3: Cursos complementarios ─────────────────────────────────────────

  Step _step3(Color primary) => Step(
    title: const Text('Cursos Complementarios'),
    isActive: _step >= 4,
    content: Form(
      key: _keys[4],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            title: const Text('Tengo cursos complementarios'),
            value: _hasCerts,
            onChanged: (v) => setState(() {
              _hasCerts = v;
              if (v && _certs.isEmpty) _certs.add(_Cert());
            }),
          ),
          if (_hasCerts) ...[
            for (int i = 0; i < _certs.length; i++) _certCard(i, primary),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Agregar curso'),
              onPressed: () => setState(() => _certs.add(_Cert())),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _certCard(int i, Color primary) {
    final c = _certs[i];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Curso ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_certs.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => setState(() {
                      c.dispose();
                      _certs.removeAt(i);
                    }),
                  ),
              ],
            ),
            TextFormField(
              controller: c.nombre,
              decoration: const InputDecoration(labelText: 'Nombre del curso'),
              validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: c.fecha,
              readOnly: true,
              onTap: () => _pickMonthYear(c.fecha),
              decoration: const InputDecoration(
                labelText: 'Fecha (MM/AAAA)',
                suffixIcon: Icon(Icons.calendar_month),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
            ),
            const SizedBox(height: 8),
            _docBtn(
              label: 'Soporte del curso',
              url: c.url,
              onTap: () => _pickDoc(
                'curso_$i',
                (u) => c.url = u,
                onBytes: (b) => c.bytes = b,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Paso 4: Experiencia laboral ────────────────────────────────────────────

  Step _step4(Color primary) => Step(
    title: const Text('Experiencia Laboral'),
    isActive: _step >= 5,
    content: Form(
      key: _keys[5],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < _exps.length; i++) _expCard(i, primary),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Agregar experiencia'),
            onPressed: () => setState(() => _exps.add(_Exp())),
          ),
        ],
      ),
    ),
  );

  Widget _expCard(int i, Color primary) {
    final e = _exps[i];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Experiencia ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_exps.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => setState(() {
                      e.dispose();
                      _exps.removeAt(i);
                    }),
                  ),
              ],
            ),
            TextFormField(
              controller: e.empresa,
              inputFormatters: [_Cap()],
              decoration: const InputDecoration(labelText: 'Empresa'),
              validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: e.cargo,
              inputFormatters: [_Cap()],
              decoration: const InputDecoration(labelText: 'Cargo'),
              validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: e.inicio,
                    readOnly: true,
                    onTap: () => _pickMonthYear(e.inicio),
                    decoration: const InputDecoration(
                      labelText: 'Inicio',
                      suffixIcon: Icon(Icons.calendar_month),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Obligatorio' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: e.fin,
                    readOnly: true,
                    onTap: () => _pickMonthYear(e.fin),
                    decoration: const InputDecoration(
                      labelText: 'Fin',
                      suffixIcon: Icon(Icons.calendar_month),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Obligatorio' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _docBtn(
              label: 'Soporte de experiencia',
              url: e.soporteUrl,
              onTap: () => _pickDoc(
                'exp_$i',
                (u) => e.soporteUrl = u,
                onBytes: (b) => e.soporteBytes = b,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Widgets reutilizables ──────────────────────────────────────────────────

  Widget _infoPanel({
    required IconData icon,
    required String title,
    required String text,
  }) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(height: 1.35)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _selectField({
    required String label,
    required TextEditingController controller,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) => _searchableTextField(
    controller: controller,
    label: label,
    options: options,
    onChanged: onChanged,
  );

  String _searchKey(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');

  List<String> _filterStringOptions(List<String> options, String query) {
    final q = _searchKey(query);
    if (q.isEmpty) return options;
    return options.where((item) => _searchKey(item).contains(q)).toList();
  }

  List<HvCatalogItem> _filterCatalogOptions(
    List<HvCatalogItem> options,
    String query,
  ) {
    final q = _searchKey(query);
    if (q.isEmpty) return options;
    return options.where((item) => _searchKey(item.name).contains(q)).toList();
  }

  String? _mappedUrl(Map<String, String> urls, String value) {
    final key = _searchKey(value);
    if (key.isEmpty) return null;
    for (final entry in urls.entries) {
      if (_searchKey(entry.key) == key) return entry.value;
    }
    return null;
  }

  Widget _certificateLink({
    required TextEditingController controller,
    required Map<String, String> urls,
    required String label,
    String? fallbackUrl,
    String? fallbackLabel,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final selected = value.text.trim();
        final url = _mappedUrl(urls, selected);
        final externalUrl = url ?? (selected.isNotEmpty ? fallbackUrl : null);
        if (externalUrl == null) return const SizedBox.shrink();

        final text = url == null
            ? (fallbackLabel ?? 'Consultar entidad')
            : 'Generar $label en $selected';

        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => launchUrlString(
              externalUrl,
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(text),
            style: TextButton.styleFrom(
              foregroundColor: primary,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
        );
      },
    );
  }

  Widget _searchableTextField({
    required TextEditingController controller,
    required String label,
    required List<String> options,
    ValueChanged<String>? onChanged,
    bool mandatory = true,
  }) {
    return TypeAheadFormField<String>(
      textFieldConfiguration: TextFieldConfiguration(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.search_rounded),
        ),
        onChanged: (value) => onChanged?.call(value.trim()),
      ),
      suggestionsCallback: (pattern) => _filterStringOptions(options, pattern),
      itemBuilder: (_, item) => ListTile(dense: true, title: Text(item)),
      onSuggestionSelected: (item) {
        controller.text = item;
        onChanged?.call(item);
      },
      minCharsForSuggestions: 0,
      noItemsFoundBuilder: (_) => const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Sin resultados. Puedes escribir el valor manualmente.'),
      ),
      hideOnEmpty: false,
      validator: mandatory
          ? (v) => v == null || v.trim().isEmpty ? 'Obligatorio' : null
          : null,
    );
  }

  Widget _departmentCityPicker({
    required String departmentLabel,
    required String cityLabel,
    required TextEditingController departmentController,
    required TextEditingController cityController,
    required String? departmentCode,
    required List<HvCatalogItem> ciudades,
    required ValueChanged<HvCatalogItem?> onDepartmentChanged,
    required ValueChanged<HvCatalogItem?> onCityChanged,
  }) {
    final departmentValue = _catalogValue(_departamentos, departmentCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TypeAheadFormField<HvCatalogItem>(
          textFieldConfiguration: TextFieldConfiguration(
            controller: departmentController,
            decoration: InputDecoration(
              labelText: departmentLabel,
              suffixIcon: const Icon(Icons.search_rounded),
            ),
            onChanged: (value) {
              final item = _findCatalogByName(_departamentos, value);
              onDepartmentChanged(item);
            },
          ),
          suggestionsCallback: (pattern) =>
              _filterCatalogOptions(_departamentos, pattern),
          itemBuilder: (_, item) =>
              ListTile(dense: true, title: Text(item.name)),
          onSuggestionSelected: (item) {
            departmentController.text = item.name;
            onDepartmentChanged(item);
          },
          minCharsForSuggestions: 0,
          noItemsFoundBuilder: (_) => const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Sin resultados. Puedes escribir el nombre manualmente.',
            ),
          ),
          hideOnEmpty: false,
          validator: (_) =>
              departmentController.text.trim().isEmpty ? 'Obligatorio' : null,
        ),
        _gap(),
        TypeAheadFormField<HvCatalogItem>(
          textFieldConfiguration: TextFieldConfiguration(
            controller: cityController,
            enabled: true,
            decoration: InputDecoration(
              labelText: cityLabel,
              helperText: departmentValue == null
                  ? 'Selecciona un departamento para ver sugerencias'
                  : null,
              suffixIcon: const Icon(Icons.search_rounded),
            ),
            onChanged: (value) {
              final item = _findCatalogByName(ciudades, value);
              onCityChanged(item);
            },
          ),
          suggestionsCallback: (pattern) => departmentValue == null
              ? <HvCatalogItem>[]
              : _filterCatalogOptions(ciudades, pattern),
          itemBuilder: (_, item) =>
              ListTile(dense: true, title: Text(item.name)),
          onSuggestionSelected: (item) {
            cityController.text = item.name;
            onCityChanged(item);
          },
          minCharsForSuggestions: 0,
          noItemsFoundBuilder: (_) => const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Sin resultados. Puedes escribir el nombre manualmente.',
            ),
          ),
          hideOnEmpty: false,
          validator: (_) =>
              cityController.text.trim().isEmpty ? 'Obligatorio' : null,
        ),
      ],
    );
  }

  HvCatalogItem? _findCatalogByName(List<HvCatalogItem> items, String name) {
    final key = _searchKey(name);
    if (key.isEmpty) return null;
    for (final item in items) {
      if (_searchKey(item.name) == key) return item;
    }
    return null;
  }

  HvCatalogItem? _catalogValue(List<HvCatalogItem> items, String? code) {
    final clean = code?.trim() ?? '';
    if (clean.isEmpty) return null;
    for (final item in items) {
      if (item.code == clean) return item;
    }
    return null;
  }

  Future<void> _onDepartmentChanged(
    HvCatalogItem? department, {
    required void Function(String? code, String? name) assignDepartment,
    required void Function(List<HvCatalogItem> items) assignCities,
    required void Function(String? code, String? name) assignCity,
  }) async {
    assignDepartment(department?.code, department?.name);
    assignCities([]);
    assignCity(null, null);
    setState(() {});

    if (department == null) return;
    final ciudades = await _svc.getCiudades(department.code);
    if (!mounted) return;
    setState(() => assignCities(ciudades));
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool mandatory = true,
    TextInputType keyboard = TextInputType.text,
    TextInputFormatter? caseFormatter,
    List<TextInputFormatter> formatters = const [],
    String? helperText,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      inputFormatters: [caseFormatter ?? _Cap(), ...formatters],
      decoration: InputDecoration(labelText: label, helperText: helperText),
      validator: mandatory
          ? (v) => v == null || v.trim().isEmpty ? 'Obligatorio' : null
          : null,
    );
  }

  Widget _datePicker(TextEditingController ctrl, String label) => TextFormField(
    controller: ctrl,
    readOnly: true,
    onTap: () => _pickMonthYear(ctrl),
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: const Icon(Icons.calendar_month),
    ),
    validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
  );

  Widget _fullDatePicker(TextEditingController ctrl, String label) =>
      TextFormField(
        controller: ctrl,
        readOnly: true,
        onTap: () => _pickFullDate(ctrl),
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_rounded),
        ),
        validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
      );

  Widget _docBtn({
    required String label,
    required String? url,
    required VoidCallback onTap,
  }) => ElevatedButton.icon(
    icon: Icon(
      url == null ? Icons.picture_as_pdf_rounded : Icons.check_circle_rounded,
    ),
    label: Text(url == null ? 'Subir $label' : '$label subido'),
    style: ElevatedButton.styleFrom(
      backgroundColor: url == null
          ? Theme.of(context).colorScheme.primary
          : Colors.green,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onPressed: onTap,
  );

  Widget _antecedente({
    required Color primary,
    required String label,
    required String? url,
    required String externalUrl,
    required VoidCallback onPick,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.open_in_new),
        label: Text('Generar $label'),
        onPressed: () =>
            launchUrlString(externalUrl, mode: LaunchMode.externalApplication),
      ),
      const SizedBox(height: 6),
      _docBtn(label: label, url: url, onTap: onPick),
    ],
  );

  Widget _checkSection({
    required String title,
    required bool value,
    required void Function(bool) onChanged,
    required List<Widget> children,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CheckboxListTile(
        title: Text(title),
        value: value,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => onChanged(v!),
      ),
      if (value) ...children,
    ],
  );

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
  );

  Widget _gap() => const SizedBox(height: 12);

  FilteringTextInputFormatter _nameFilter() =>
      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÁÉÍÓÚáéíóúñÑ ]'));
}

class _FormIntroCard extends StatelessWidget {
  final Color primary;

  const _FormIntroCard({required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.assignment_ind_rounded, color: primary, size: 30),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hoja de vida digital',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Completa la información por bloques. Los soportes documentales se cargan únicamente en PDF.',
                  style: TextStyle(color: Color(0xFF64748B), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Banners de estado ──────────────────────────────────────────────────────

class _RevisionBanner extends StatelessWidget {
  final String nota;
  final dynamic requestedAt;
  final dynamic updatedAt;
  final dynamic submittedAt;
  final String? status;

  const _RevisionBanner({
    required this.nota,
    this.requestedAt,
    this.updatedAt,
    this.submittedAt,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final requested = _formatHvDateTime(requestedAt);
    final updated = _formatHvDateTime(updatedAt);
    final submitted = _formatHvDateTime(submittedAt);
    return Container(
      width: double.infinity,
      color: Colors.red.shade50,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Talento Humano solicita correcciones',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(nota, style: const TextStyle(color: Colors.red)),
                if (requested.isNotEmpty || updated.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (requested.isNotEmpty) 'Devuelta: $requested',
                      if (updated.isNotEmpty) 'Último cambio: $updated',
                      if (submitted.isNotEmpty) 'Reenviada: $submitted',
                      if ((status ?? '').isNotEmpty) 'Estado: $status',
                    ].join(' · '),
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusBanner({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _LoadWarningBanner extends StatelessWidget {
  final String message;

  const _LoadWarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadInfoBanner extends StatelessWidget {
  final String message;

  const _LoadInfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      color: primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top_rounded, color: primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
