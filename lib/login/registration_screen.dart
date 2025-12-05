// lib/login/registration_screen.dart

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';            // para formatear fecha en español
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'preview_screen.dart';


/// Formatter para convertir todo el texto a mayúsculas
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

/// Formatter para convertir todo el texto a minúsculas
class LowerCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) =>
      newValue.copyWith(text: newValue.text.toLowerCase());
}

/// Formatter para capitalizar sólo la primera letra de cada palabra
class CapitalizeTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final words = newValue.text.toLowerCase().split(' ');
    final capitalized = words
        .map((w) => w.isEmpty
        ? ''
        : w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
        .join(' ');
    return newValue.copyWith(text: capitalized);
  }
}

/// Modelo para cursos complementarios (antes "Certificados")
class Certificado {
  final TextEditingController nombreCtrl = TextEditingController();
  final TextEditingController fechaCtrl = TextEditingController();
  Uint8List? bytes;
  String? extension;
  String? url;
  void dispose() {
    nombreCtrl.dispose();
    fechaCtrl.dispose();
  }
}

/// Modelo para experiencia laboral con soporte
class Experiencia {
  final TextEditingController empresaCtrl = TextEditingController();
  final TextEditingController cargoCtrl = TextEditingController();
  final TextEditingController inicioCtrl = TextEditingController();
  final TextEditingController finCtrl = TextEditingController();
  Uint8List? soporteBytes;
  String? soporteUrl;
  void dispose() {
    empresaCtrl.dispose();
    cargoCtrl.dispose();
    inicioCtrl.dispose();
    finCtrl.dispose();
  }
}

class RegistrationScreen extends StatefulWidget {
  final String cedula;
  final String empresaId;
  const RegistrationScreen({Key? key, required this.cedula, required this.empresaId})
      : super(key: key);

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  // Colores corporativos
  static const Color _primaryColor = Color(0xFF1975B8);
  static const Color _accentColor  = Color(0xFF1975B8);

  int _currentStep = 0;
  final _formKeys = List.generate(5, (_) => GlobalKey<FormState>());

  // 1) Estado para la revisión de RRHH:
  bool _needsRevision = false;
  String? _revisionNote;

  // Paso 0: Foto y cédula
  Uint8List? _fotoBytes;
  String? _fotoUrl;
  Uint8List? _cedulaDocBytes;
  String? _cedulaDocUrl;

  // Datos personales
  final _primerNombreCtrl    = TextEditingController();
  final _segundoNombreCtrl   = TextEditingController();
  final _primerApellidoCtrl  = TextEditingController();
  final _segundoApellidoCtrl = TextEditingController();
  final _lugarExpedicionCtrl = TextEditingController();
  final _emailCtrl           = TextEditingController();
  final _telefonoCtrl        = TextEditingController();
  final _direccionCtrl       = TextEditingController();
  final _ciudadCtrl          = TextEditingController();

  // Paso 1: Antecedentes (solo URLs)
  Uint8List? _procBytes;
  String? _procUrl;
  Uint8List? _contrBytes;
  String? _contrUrl;
  Uint8List? _polBytes;
  String? _polUrl;
  Uint8List? _medBytes;
  String? _medUrl;

  // Paso 2: Formación académica
  final _bachInstCtrl  = TextEditingController();
  final _bachFechaCtrl = TextEditingController();
  String? _bachilerUrl;

  bool _hasUniversity    = false;
  final _uniInstCtrl     = TextEditingController();
  final _uniCarrCtrl     = TextEditingController();
  final _uniFechaCtrl    = TextEditingController();
  String? _uniUrl;

  bool _hasTarjetaProf   = false;
  final _tarjetaNumeroCtrl = TextEditingController();
  Uint8List? _tarjetaBytes;
  String? _tarjetaUrl;

  bool _hasSecondCareer  = false;
  final _secInstCtrl     = TextEditingController();
  final _secCarrCtrl     = TextEditingController();
  final _secFechaCtrl    = TextEditingController();
  String? _secUrl;

  bool _hasEspecializacion = false;
  final _espInstCtrl      = TextEditingController();
  final _espProgCtrl      = TextEditingController();
  final _espFechaCtrl     = TextEditingController();
  String? _espUrl;

  bool _hasMaestria      = false;
  final _maeInstCtrl     = TextEditingController();
  final _maeProgCtrl     = TextEditingController();
  final _maeFechaCtrl    = TextEditingController();
  String? _maeUrl;

  // Paso 3: Cursos Complementarios
  bool _hasCertificados = false;
  final List<Certificado> _certs = [];

  // Paso 4: Referencias laborales
  final List<Experiencia> _exps = [Experiencia()];

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  Future<void> _loadExistingData() async {
    final usuariosCol =
    FirebaseFirestore.instance.collection('TBL_USUARIOS');
    var doc = await usuariosCol.doc(widget.cedula).get();
    if (doc.exists) {
      final empresaDoc = (doc.data()?['empresaId'] as String?)?.trim() ?? '';
      if (empresaDoc != widget.empresaId) {
        doc = await usuariosCol.doc();
      }
    }
    if (!doc.exists) {
      final query = await usuariosCol
          .where('cedula', isEqualTo: widget.cedula)
          .where('empresaId', isEqualTo: widget.empresaId)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        doc = query.docs.first;
      }
    }
    if (!doc.exists) return;
    final d = doc.data()!;

    setState(() {
      // 1) Flags de revisión
      _needsRevision = d['needsRevision'] == true;
      _revisionNote  = d['revisionNote'] as String?;

      // 2) Foto y cédula
      _fotoUrl      = d['fotoUrl']      as String?;
      _cedulaDocUrl = d['cedulaDocUrl'] as String?;

      // 3) Datos personales
      _primerNombreCtrl.text    = d['primerNombre']    ?? '';
      _segundoNombreCtrl.text   = d['segundoNombre']   ?? '';
      _primerApellidoCtrl.text  = d['primerApellido']  ?? '';
      _segundoApellidoCtrl.text = d['segundoApellido'] ?? '';
      _lugarExpedicionCtrl.text = d['lugarExpedicion'] ?? '';
      _emailCtrl.text           = d['email']           ?? '';
      _telefonoCtrl.text        = d['telefono']        ?? '';
      _direccionCtrl.text       = d['direccion']       ?? '';
      _ciudadCtrl.text          = d['ciudad']          ?? '';

      // 4) Antecedentes / comprobantes
      _procUrl  = d['procUrl']  as String?;
      _contrUrl = d['contrUrl'] as String?;
      _polUrl   = d['polUrl']   as String?;
      _medUrl   = d['medUrl']   as String?;

      // 5) Formación académica
      _bachInstCtrl.text      = d['bachInst']       ?? '';
      _bachFechaCtrl.text     = d['bachFecha']      ?? '';
      _bachilerUrl            = d['bachillerUrl']   as String?;
      _hasUniversity          = d['hasUniversity']  ?? false;
      _uniInstCtrl.text       = d['uniInst']        ?? '';
      _uniCarrCtrl.text       = d['uniCarr']        ?? '';
      _uniFechaCtrl.text      = d['uniFecha']       ?? '';
      _uniUrl                 = d['uniUrl']         as String?;
      _hasTarjetaProf         = d['hasTarjetaProf'] ?? false;
      _tarjetaNumeroCtrl.text = d['tarjetaNumero']  ?? '';
      _tarjetaUrl             = d['tarjetaUrl']     as String?;
      _hasSecondCareer        = d['hasSecondCareer'] ?? false;
      _secInstCtrl.text       = d['secInst']        ?? '';
      _secCarrCtrl.text       = d['secCarr']        ?? '';
      _secFechaCtrl.text      = d['secFecha']       ?? '';
      _secUrl                 = d['secUrl']         as String?;
      _hasEspecializacion     = d['hasEspecializacion'] ?? false;
      _espInstCtrl.text       = d['espInst']        ?? '';
      _espProgCtrl.text       = d['espProg']        ?? '';
      _espFechaCtrl.text      = d['espFecha']       ?? '';
      _espUrl                 = d['espUrl']         as String?;
      _hasMaestria            = d['hasMaestria']    ?? false;
      _maeInstCtrl.text       = d['maeInst']        ?? '';
      _maeProgCtrl.text       = d['maeProg']        ?? '';
      _maeFechaCtrl.text      = d['maeFecha']       ?? '';
      _maeUrl                 = d['maeUrl']         as String?;

      // 6) Cursos complementarios
      _hasCertificados = d['hasCertificados'] ?? false;
      _certs.clear();
      if (_hasCertificados) {
        for (var c in d['certificados'] as List<dynamic>) {
          final cert = Certificado()
            ..nombreCtrl.text = c['nombre'] ?? ''
            ..fechaCtrl.text  = c['fecha']  ?? ''
            ..url             = c['url']    as String?;
          _certs.add(cert);
        }
      }

      // 7) Experiencias laborales
      _exps.clear();
      for (var e in d['experiencias'] as List<dynamic>) {
        final exp = Experiencia()
          ..empresaCtrl.text = e['empresa']   ?? ''
          ..cargoCtrl.text   = e['cargo']     ?? ''
          ..inicioCtrl.text  = e['inicio']    ?? ''
          ..finCtrl.text     = e['fin']       ?? ''
          ..soporteUrl       = e['soporteUrl'] as String?;
        _exps.add(exp);
      }
    });

    // 8) Mostrar diálogo de corrección si aplica
    if (_needsRevision && (_revisionNote?.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Corrección requerida'),
            content: Text(_revisionNote!),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    // Datos personales
    _primerNombreCtrl.dispose();
    _segundoNombreCtrl.dispose();
    _primerApellidoCtrl.dispose();
    _segundoApellidoCtrl.dispose();
    _lugarExpedicionCtrl.dispose();
    _emailCtrl.dispose();
    _telefonoCtrl.dispose();
    _direccionCtrl.dispose();
    _ciudadCtrl.dispose();
    // Formación académica
    _bachInstCtrl.dispose();
    _bachFechaCtrl.dispose();
    _uniInstCtrl.dispose();
    _uniCarrCtrl.dispose();
    _uniFechaCtrl.dispose();
    _tarjetaNumeroCtrl.dispose();
    _secInstCtrl.dispose();
    _secCarrCtrl.dispose();
    _secFechaCtrl.dispose();
    _espInstCtrl.dispose();
    _espProgCtrl.dispose();
    _espFechaCtrl.dispose();
    _maeInstCtrl.dispose();
    _maeProgCtrl.dispose();
    _maeFechaCtrl.dispose();
    // Cursos complementarios y referencias
    for (var c in _certs) c.dispose();
    for (var r in _exps) r.dispose();
    super.dispose();
  }

  /// Muestra un diálogo modal con un spinner y texto
  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            const Expanded(child: Text('Generando PDF...')),
          ],
        ),
      ),
    );
  }

  /// Muestra un diálogo con un check verde y “¡Finalizado!”
  Future<void> _showSuccessDialog() {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 20),
            Expanded(child: Text('¡Finalizado!')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Muestra un diálogo de error
  Future<void> _showErrorDialog(String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickExperienciaSoporte(int index) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf','png','jpg','jpeg'],
      withData: true,
    );
    if (r == null) return;
    final f = r.files.single;
    final exp = _exps[index];
    exp.soporteBytes = f.bytes;
    exp.soporteUrl = await _uploadBytes(
      'experiencia_${index}.${f.extension}',
      f.bytes!,
    );
    setState(() {});
  }

  Widget _buildTextField(
      TextEditingController ctrl,
      String label, {
        TextInputType keyboardType = TextInputType.text,
        List<TextInputFormatter>? extraFormatters,
        bool mandatory = true,
        TextInputFormatter? caseFormatter,
      }) {
    final formatters = <TextInputFormatter>[
      caseFormatter ?? CapitalizeTextFormatter()
    ];
    if (extraFormatters != null) formatters.addAll(extraFormatters);
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label),
      validator: mandatory
          ? (v) => v == null || v.trim().isEmpty ? 'Obligatorio' : null
          : null,
    );
  }

  Future<String> _uploadBytes(String path, Uint8List bytes) async {
    final ref =
    FirebaseStorage.instance.ref('cedulas/${widget.cedula}/$path');
    await ref.putData(bytes);
    return await ref.getDownloadURL();
  }

  Future<void> _pickPhoto() async {
    if (kIsWeb) {
      // Web: usar FilePicker para imagen (cámara/galería)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final data = file.bytes!;
      final ext = file.extension!;
      _fotoBytes = data;
      _fotoUrl = await _uploadBytes('foto.$ext', data);
      setState(() {});
    } else {
      // Android/iOS: ImagePicker
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (pickedFile == null) return;
      final bytes = await pickedFile.readAsBytes();
      final ext = pickedFile.path.split('.').last;
      _fotoBytes = bytes;
      _fotoUrl = await _uploadBytes('foto.$ext', bytes);
      setState(() {});
    }
  }

  Future<void> _pickCedulaDoc() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (r == null) return;
    final f = r.files.single;
    _cedulaDocBytes = f.bytes;
    _cedulaDocUrl =
    await _uploadBytes('cedula.${f.extension}', f.bytes!);
    setState(() {});
  }

  Future<void> _pickFileDoc({
    required String tag,
    required void Function(String url) onUrl,
    required void Function(Uint8List bytes) onBytes,
  }) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (r == null) return;
    final f = r.files.single;
    onBytes(f.bytes!);
    final uploaded = await _uploadBytes('$tag.${f.extension}', f.bytes!);
    onUrl(uploaded);
    setState(() {});
  }

  Future<void> _pickTarjetaDoc() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (r == null) return;
    final f = r.files.single;
    _tarjetaBytes = f.bytes;
    _tarjetaUrl =
    await _uploadBytes('tarjeta_prof.${f.extension}', f.bytes!);
    setState(() {});
  }

  Future<void> _pickMonthYear(TextEditingController ctrl) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(1900),
      lastDate: now,
      locale: const Locale('es', 'ES'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: _primaryColor,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      ctrl.text = DateFormat('MM/yyyy', 'es').format(picked);
    }
  }

  void _onStepContinue() async {
    if (_currentStep == 0) {
      if (_fotoBytes == null) {
        await _showErrorDialog('Sube tu foto antes de continuar');
        return;
      }
      if (_cedulaDocUrl == null) {
        await _showErrorDialog('Sube tu documento de cédula');
        return;
      }
    }
    if (_currentStep == 1) {
      if (_procUrl == null ||
          _contrUrl == null ||
          _polUrl == null ||
          _medUrl == null) {
        await _showErrorDialog('Completa todos los antecedentes');
        return;
      }
    }
    if (_currentStep == 2) {
      if (_bachInstCtrl.text.isEmpty ||
          _bachFechaCtrl.text.isEmpty ||
          _bachilerUrl == null) {
        await _showErrorDialog(
            'Completa bachillerato y sube el soporte correspondiente');
        return;
      }
      if (_hasUniversity) {
        if (_uniInstCtrl.text.isEmpty ||
            _uniCarrCtrl.text.isEmpty ||
            _uniFechaCtrl.text.isEmpty ||
            _uniUrl == null ||
            (_hasTarjetaProf &&
                (_tarjetaNumeroCtrl.text.isEmpty || _tarjetaUrl == null))) {
          await _showErrorDialog(
              'Completa datos de universidad, tarjeta (si aplica) y sube soportes');
          return;
        }
      }
    }
    if (_currentStep == 3 && _hasCertificados) {
      for (var c in _certs) {
        if (c.nombreCtrl.text.isEmpty ||
            c.fechaCtrl.text.isEmpty ||
            c.url == null) {
          await _showErrorDialog('Completa todos los cursos');
          return;
        }
      }
    }
    if (_currentStep == 4) {
      for (var r in _exps) {
        if (r.empresaCtrl.text.isEmpty ||
            r.cargoCtrl.text.isEmpty    ||
            r.inicioCtrl.text.isEmpty   ||
            r.finCtrl.text.isEmpty) {
          await _showErrorDialog('Completa todos los datos de experiencia');
          return;
        }
        if (r.soporteUrl == null) {
          await _showErrorDialog('Sube el soporte para cada experiencia');
          return;
        }
      }
    }
    if (!_formKeys[_currentStep].currentState!.validate()) return;

    // Si no es el último paso, avanzamos
    if (_currentStep < 4) {
      setState(() => _currentStep++);
      return;
    }
    // --- Último paso: navegar a la pantalla de preview ---
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(
          data: {
            // — Datos personales —
            'cedula':           widget.cedula,
            'empresaId':        widget.empresaId,
            'fotoBytes':        _fotoBytes!,
            'fotoUrl':          _fotoUrl!,
            'cedulaDocUrl':     _cedulaDocUrl!,

            'primerNombre':     _primerNombreCtrl.text,
            'segundoNombre':    _segundoNombreCtrl.text,
            'primerApellido':   _primerApellidoCtrl.text,
            'segundoApellido':  _segundoApellidoCtrl.text,
            'lugarExpedicion':  _lugarExpedicionCtrl.text,
            'email':            _emailCtrl.text,
            'telefono':         _telefonoCtrl.text,
            'direccion':        _direccionCtrl.text,
            'ciudad':           _ciudadCtrl.text,

            // — Formación académica —
            'bachInst':         _bachInstCtrl.text,
            'bachFecha':        _bachFechaCtrl.text,
            'bachillerUrl':     _bachilerUrl!,

            'hasUniversity':    _hasUniversity,
            'uniInst':          _uniInstCtrl.text,
            'uniCarr':          _uniCarrCtrl.text,
            'uniFecha':         _uniFechaCtrl.text,
            'uniUrl':           _uniUrl,

            'hasTarjetaProf':   _hasTarjetaProf,
            'tarjetaNumero':    _tarjetaNumeroCtrl.text.trim(),
            'tarjetaUrl':       _tarjetaUrl,

            'hasSecondCareer':  _hasSecondCareer,
            'secInst':          _secInstCtrl.text,
            'secCarr':          _secCarrCtrl.text,
            'secFecha':         _secFechaCtrl.text,
            'secUrl':           _secUrl,

            'hasEspecializacion': _hasEspecializacion,
            'espInst':            _espInstCtrl.text,
            'espProg':            _espProgCtrl.text,
            'espFecha':           _espFechaCtrl.text,
            'espUrl':             _espUrl,

            'hasMaestria':      _hasMaestria,
            'maeInst':          _maeInstCtrl.text,
            'maeProg':          _maeProgCtrl.text,
            'maeFecha':         _maeFechaCtrl.text,
            'maeUrl':           _maeUrl,

            // — Antecedentes / comprobantes —
            'procUrl':          _procUrl!,
            'contrUrl':         _contrUrl!,
            'polUrl':           _polUrl!,
            'medUrl':           _medUrl!,

            // — Cursos complementarios —
            'hasCertificados':  _hasCertificados,
            'certificados':     _certs.map((c) => {
              'nombre': c.nombreCtrl.text,
              'fecha':  c.fechaCtrl.text,
              'url':    c.url!,
            }).toList(),

            // — Experiencias laborales —
            'experiencias': _exps.map((e) => {
              'empresa':    e.empresaCtrl.text,
              'cargo':      e.cargoCtrl.text,
              'inicio':     e.inicioCtrl.text,
              'fin':        e.finCtrl.text,
              'soporteUrl': e.soporteUrl,
            }).toList(),
          },
        ),
      ),
    );
  }

  void _onStepCancel() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Actualizar Hoja de Vida'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Stepper(
          currentStep: _currentStep,
          physics: const ClampingScrollPhysics(),
          onStepContinue: _onStepContinue,
          onStepCancel: _onStepCancel,
          controlsBuilder: (ctx, details) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Row(
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: details.onStepContinue,
                  child: Text(_currentStep < 4 ? 'Siguiente' : 'Finalizar'),
                ),
                const SizedBox(width: 12),
                if (_currentStep > 0)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: details.onStepCancel,
                    child: const Text('Atrás'),
                  ),
              ],
            ),
          ),
          steps: [
            // Paso 0: Datos Personales
            Step(
              title: const Text('Datos Personales'),
              isActive: _currentStep >= 0,
              content: Form(
                key: _formKeys[0],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 120,
                      width: 120,
                      color: Colors.grey[200],
                      child: _fotoBytes != null
                          ? Image.memory(_fotoBytes!, fit: BoxFit.cover)
                          : (_fotoUrl != null
                          ? Image.network(
                        _fotoUrl!,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, c, p) =>
                        p == null ? c : const Center(child: CircularProgressIndicator()),
                      )
                          : const Icon(Icons.camera_alt, size: 40, color: Colors.grey)),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Tomar Foto'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _pickPhoto,
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      _primerNombreCtrl,
                      'Primer Nombre',
                      extraFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚáéíóúñÑ ]"))
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      _segundoNombreCtrl,
                      'Segundo Nombre',
                      mandatory: false,
                      extraFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚáéíóúñÑ ]"))
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      _primerApellidoCtrl,
                      'Primer Apellido',
                      extraFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚáéíóúñÑ ]"))
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      _segundoApellidoCtrl,
                      'Segundo Apellido',
                      mandatory: false,
                      extraFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚáéíóúñÑ ]"))
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: widget.cedula,
                      decoration: const InputDecoration(labelText: 'Cédula'),
                      enabled: false,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      _lugarExpedicionCtrl,
                      'Lugar de expedición',
                      extraFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚáéíóúñÑ ]"))
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: Text(_cedulaDocUrl == null
                          ? 'Subir documento de cédula'
                          : 'Subido correctamente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _cedulaDocUrl == null
                            ? _primaryColor
                            : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _pickCedulaDoc,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      inputFormatters: [LowerCaseTextFormatter()],
                      decoration:
                      const InputDecoration(labelText: 'Correo Electrónico'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Obligatorio';
                        final regex =
                        RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                        return regex.hasMatch(v.trim())
                            ? null
                            : 'Formato inválido';
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      _telefonoCtrl,
                      'Teléfono',
                      keyboardType: TextInputType.phone,
                      extraFormatters: [FilteringTextInputFormatter.digitsOnly],
                      caseFormatter: LowerCaseTextFormatter(),
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(_direccionCtrl, 'Dirección de Residencia'),
                    const SizedBox(height: 16),
                    _buildTextField(
                      _ciudadCtrl,
                      'Ciudad',
                      extraFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚáéíóúñÑ ]"))
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Paso 1: Antecedentes
            Step(
              title: const Text('Antecedentes'),
              isActive: _currentStep >= 1,
              content: Form(
                key: _formKeys[1],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Procuraduría
                    ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Generar Procuraduría'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        launchUrlString(
                          'https://www.procuraduria.gov.co/Pages/Generacion-de-antecedentes.aspx',
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: Text(_procUrl == null
                          ? 'Subir Procuraduría'
                          : 'Subido correctamente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        _procUrl == null ? _primaryColor : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        await _pickFileDoc(
                          tag: 'Procuraduria',
                          onBytes: (b) => _procBytes = b,
                          onUrl: (u) => _procUrl = u,
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // Contraloría
                    ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Generar Contraloría'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        launchUrlString(
                          'https://www.contraloria.gov.co/control-fiscal/responsabilidad-fiscal/certificado-de-antecedentes-fiscales',
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: Text(_contrUrl == null
                          ? 'Subir Contraloría'
                          : 'Subido correctamente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        _contrUrl == null ? _primaryColor : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        await _pickFileDoc(
                          tag: 'Contraloria',
                          onBytes: (b) => _contrBytes = b,
                          onUrl: (u) => _contrUrl = u,
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // Policía
                    ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Generar Policía'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        launchUrlString(
                          'https://antecedentes.policia.gov.co:7005/WebJudicial/',
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: Text(_polUrl == null
                          ? 'Subir Policía'
                          : 'Subido correctamente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        _polUrl == null ? _primaryColor : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        await _pickFileDoc(
                          tag: 'Policia',
                          onBytes: (b) => _polBytes = b,
                          onUrl: (u) => _polUrl = u,
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // Medidas correctivas
                    ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Generar Medidas Correctivas'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        launchUrlString(
                          'https://srvcnpc.policia.gov.co/PSC/frm_cnp_consulta.aspx',
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: Text(_medUrl == null
                          ? 'Subir Medidas'
                          : 'Subido correctamente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        _medUrl == null ? _primaryColor : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        await _pickFileDoc(
                          tag: 'Medidas',
                          onBytes: (b) => _medBytes = b,
                          onUrl: (u) => _medUrl = u,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Paso 2: Formación Académica
            Step(
              title: const Text('Formación Académica'),
              isActive: _currentStep >= 2,
              content: Form(
                key: _formKeys[2],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('BACHILLERATO',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildTextField(_bachInstCtrl, 'Institución'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bachFechaCtrl,
                      readOnly: true,
                      onTap: () => _pickMonthYear(_bachFechaCtrl),
                      decoration: InputDecoration(
                        labelText: 'Fecha grado (MM/AAAA)',
                        suffixIcon:
                        Icon(Icons.calendar_month, color: _accentColor),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? 'Obligatorio'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _pickFileDoc(
                        tag: 'bachillerato',
                        onBytes: (b) => null,
                        onUrl: (u) => _bachilerUrl = u,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        _bachilerUrl == null ? _primaryColor : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_bachilerUrl == null
                          ? 'Subir Soporte Bachillerato'
                          : 'Subido correctamente'),
                    ),
                    const SizedBox(height: 24),
                    CheckboxListTile(
                      title: const Text('Formación Universitaria'),
                      value: _hasUniversity,
                      onChanged: (v) => setState(() => _hasUniversity = v!),
                    ),
                    if (_hasUniversity) ...[
                      _buildTextField(_uniInstCtrl, 'Institución'),
                      const SizedBox(height: 16),
                      _buildTextField(_uniCarrCtrl, 'Carrera'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _uniFechaCtrl,
                        readOnly: true,
                        onTap: () => _pickMonthYear(_uniFechaCtrl),
                        decoration: InputDecoration(
                          labelText: 'Fecha grado (MM/AAAA)',
                          suffixIcon:
                          Icon(Icons.calendar_month, color: _accentColor),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Obligatorio'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text('¿Tiene Tarjeta Profesional?'),
                        value: _hasTarjetaProf,
                        onChanged: (v) =>
                            setState(() => _hasTarjetaProf = v!),
                      ),
                      if (_hasTarjetaProf) ...[
                        _buildTextField(_tarjetaNumeroCtrl,
                            'Número de Tarjeta Profesional'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _pickTarjetaDoc,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            _tarjetaUrl == null ? _primaryColor : Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(_tarjetaUrl == null
                              ? 'Subir Tarjeta Profesional'
                              : 'Subido correctamente'),
                        ),
                        const SizedBox(height: 24),
                      ],
                      ElevatedButton(
                        onPressed: () => _pickFileDoc(
                          tag: 'universidad',
                          onBytes: (b) => null,
                          onUrl: (u) => _uniUrl = u,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          _uniUrl == null ? _primaryColor : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(_uniUrl == null
                            ? 'Subir Soporte Universidad'
                            : 'Subido correctamente'),
                      ),
                      const SizedBox(height: 24),
                    ],
                    CheckboxListTile(
                      title: const Text('Segunda Carrera'),
                      value: _hasSecondCareer,
                      onChanged: (v) => setState(() => _hasSecondCareer = v!),
                    ),
                    if (_hasSecondCareer) ...[
                      _buildTextField(_secInstCtrl, 'Institución'),
                      const SizedBox(height: 16),
                      _buildTextField(_secCarrCtrl, 'Carrera'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _secFechaCtrl,
                        readOnly: true,
                        onTap: () => _pickMonthYear(_secFechaCtrl),
                        decoration: InputDecoration(
                          labelText: 'Fecha grado (MM/AAAA)',
                          suffixIcon:
                          Icon(Icons.calendar_month, color: _accentColor),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Obligatorio'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _pickFileDoc(
                          tag: 'segunda_carrera',
                          onBytes: (b) => null,
                          onUrl: (u) => _secUrl = u,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          _secUrl == null ? _primaryColor : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(_secUrl == null
                            ? 'Subir Soporte Segunda Carrera'
                            : 'Subido correctamente'),
                      ),
                      const SizedBox(height: 24),
                    ],
                    CheckboxListTile(
                      title: const Text('Especialización'),
                      value: _hasEspecializacion,
                      onChanged: (v) =>
                          setState(() => _hasEspecializacion = v!),
                    ),
                    if (_hasEspecializacion) ...[
                      _buildTextField(_espInstCtrl, 'Institución'),
                      const SizedBox(height: 16),
                      _buildTextField(_espProgCtrl, 'Programa'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _espFechaCtrl,
                        readOnly: true,
                        onTap: () => _pickMonthYear(_espFechaCtrl),
                        decoration: InputDecoration(
                          labelText: 'Fecha grado (MM/AAAA)',
                          suffixIcon: Icon(Icons.calendar_month,
                              color: _accentColor),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Obligatorio'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _pickFileDoc(
                          tag: 'especializacion',
                          onBytes: (b) => null,
                          onUrl: (u) => _espUrl = u,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          _espUrl == null ? _primaryColor : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(_espUrl == null
                            ? 'Subir Soporte Especialización'
                            : 'Subido correctamente'),
                      ),
                      const SizedBox(height: 24),
                    ],
                    CheckboxListTile(
                      title: const Text('Maestría'),
                      value: _hasMaestria,
                      onChanged: (v) => setState(() => _hasMaestria = v!),
                    ),
                    if (_hasMaestria) ...[
                      _buildTextField(_maeInstCtrl, 'Institución'),
                      const SizedBox(height: 16),
                      _buildTextField(_maeProgCtrl, 'Programa'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _maeFechaCtrl,
                        readOnly: true,
                        onTap: () => _pickMonthYear(_maeFechaCtrl),
                        decoration: InputDecoration(
                          labelText: 'Fecha grado (MM/AAAA)',
                          suffixIcon: Icon(Icons.calendar_month,
                              color: _accentColor),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Obligatorio'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _pickFileDoc(
                          tag: 'maestria',
                          onBytes: (b) => null,
                          onUrl: (u) => _maeUrl = u,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          _maeUrl == null ? _primaryColor : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(_maeUrl == null
                            ? 'Subir Soporte Maestría'
                            : 'Subido correctamente'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),

            // Paso 3: Cursos Complementarios
            Step(
              title: const Text('Cursos Complementarios'),
              isActive: _currentStep >= 3,
              content: Form(
                key: _formKeys[3],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CheckboxListTile(
                      title: const Text('Tengo Cursos Complementarios'),
                      value: _hasCertificados,
                      onChanged: (v) => setState(() => _hasCertificados = v!),
                    ),
                    if (_hasCertificados) ...[
                      for (int i = 0; i < _certs.length; i++) ...[
                        _buildCertRow(i),
                        const SizedBox(height: 16),
                      ],
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar Curso'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => setState(() => _certs.add(Certificado())),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Paso 4: Referencias Laborales
            Step(
              title: const Text('Experiencia Laboral'),
              isActive: _currentStep >= 4,
              content: Form(
                key: _formKeys[4],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < _exps.length; i++) ...[
                      _buildRefRow(i),
                      const SizedBox(height: 12),
                    ],
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar experiencia'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => setState(() => _exps.add(Experiencia())),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCertRow(int index) {
    final cert = _certs[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(cert.nombreCtrl, 'Nombre del Curso'),
        const SizedBox(height: 12),
        TextFormField(
          controller: cert.fechaCtrl,
          readOnly: true,
          onTap: () => _pickMonthYear(cert.fechaCtrl),
          decoration: InputDecoration(
            labelText: 'Fecha (MM/AAAA)',
            suffixIcon: Icon(Icons.calendar_month, color: _accentColor),
          ),
          validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () async {
            final r = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
              withData: true,
            );
            if (r == null) return;
            final f = r.files.single;
            cert.bytes     = f.bytes;
            cert.extension = f.extension;
            cert.url       = await _uploadBytes('curso_$index.${f.extension}', f.bytes!);
            setState(() {});
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: cert.url == null ? _primaryColor : Colors.green,
            foregroundColor: Colors.white,
          ),
          child: Text(cert.url == null ? 'Subir Soporte' : 'Subido correctamente'),
        ),
        if (_certs.length > 1)
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                setState(() {
                  cert.dispose();
                  _certs.removeAt(index);
                });
              },
            ),
          ),
      ],
    );
  }

  Widget _buildRefRow(int index) {
    final r = _exps[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(r.empresaCtrl, 'Empresa'),
        const SizedBox(height: 8),
        _buildTextField(r.cargoCtrl, 'Cargo'),
        const SizedBox(height: 8),
        TextFormField(
          controller: r.inicioCtrl,
          readOnly: true,
          onTap: () => _pickMonthYear(r.inicioCtrl),
          decoration: InputDecoration(
            labelText: 'Fecha Inicio (MM/AAAA)',
            suffixIcon: Icon(Icons.calendar_month, color: _accentColor),
          ),
          validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: r.finCtrl,
          readOnly: true,
          onTap: () => _pickMonthYear(r.finCtrl),
          decoration: InputDecoration(
            labelText: 'Fecha Fin (MM/AAAA)',
            suffixIcon: Icon(Icons.calendar_month, color: _accentColor),
          ),
          validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.upload_file),
          label: Text(r.soporteUrl == null ? 'Subir soporte' : 'Soporte subido'),
          style: ElevatedButton.styleFrom(
            backgroundColor: r.soporteUrl == null ? _primaryColor : Colors.green,
            foregroundColor: Colors.white,
          ),
          onPressed: () => _pickExperienciaSoporte(index),
        ),
        if (_exps.length > 1)
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                setState(() {
                  r.dispose();
                  _exps.removeAt(index);
                });
              },
            ),
          ),
        const Divider(thickness: 1.2),
      ],
    );
  }
}
