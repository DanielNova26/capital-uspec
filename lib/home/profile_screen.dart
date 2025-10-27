// lib/home/profile_screen.dart

import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher_string.dart';

const Color _primaryColor = Color(0xFFE19E4C);
const Color _accentColor  = Color(0xFFC28942);
const String _arial       = 'Arial';

/// Formatter para convertir todo el texto a mayúsculas
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/// Formatter para convertir todo el texto a minúsculas
class LowerCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) => newValue.copyWith(text: newValue.text.toLowerCase());
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

/// Modelo para cursos complementarios
class Certificado {
  final nombreCtrl = TextEditingController();
  final fechaCtrl  = TextEditingController();
  Uint8List? bytes;
  String? url;
  void dispose() {
    nombreCtrl.dispose();
    fechaCtrl.dispose();
  }
}

/// Modelo para experiencia laboral
class Experiencia {
  final empresaCtrl = TextEditingController();
  final cargoCtrl   = TextEditingController();
  final inicioCtrl  = TextEditingController();
  final finCtrl     = TextEditingController();
  Uint8List? soporteBytes;
  String? soporteUrl;
  void dispose() {
    empresaCtrl.dispose();
    cargoCtrl.dispose();
    inicioCtrl.dispose();
    finCtrl.dispose();
  }
}

class ProfileScreen extends StatefulWidget {
  final String userId;
  const ProfileScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _currentStep = 0;
  final _formKeys = List.generate(5, (_) => GlobalKey<FormState>());

  bool _needsRevision = false;
  String? _revisionNote;

  Uint8List? _fotoBytes;
  String? _fotoUrl;
  Uint8List? _cedulaBytes;
  String? _cedulaUrl;

  final _primerNombreCtrl    = TextEditingController();
  final _segundoNombreCtrl   = TextEditingController();
  final _primerApellidoCtrl  = TextEditingController();
  final _segundoApellidoCtrl = TextEditingController();
  final _lugarExpedCtrl      = TextEditingController();
  final _emailCtrl           = TextEditingController();
  final _telefonoCtrl        = TextEditingController();
  final _direccionCtrl       = TextEditingController();
  final _ciudadCtrl          = TextEditingController();

  Uint8List? _procBytes;  String? _procUrl;
  Uint8List? _contrBytes; String? _contrUrl;
  Uint8List? _polBytes;   String? _polUrl;
  Uint8List? _medBytes;   String? _medUrl;

  final _bachInstCtrl  = TextEditingController();
  final _bachFechaCtrl = TextEditingController();
  String? _bachUrl;

  bool _hasUniversity    = false;
  final _uniInstCtrl     = TextEditingController();
  final _uniCarrCtrl     = TextEditingController();
  final _uniFechaCtrl    = TextEditingController();
  String? _uniUrl;

  bool _hasProfCard      = false;
  final _cardNumCtrl     = TextEditingController();
  Uint8List? _cardBytes;
  String? _cardUrl;

  bool _hasSecondDegree  = false;
  final _secInstCtrl     = TextEditingController();
  final _secCarrCtrl     = TextEditingController();
  final _secFechaCtrl    = TextEditingController();
  String? _secUrl;

  bool _hasEspecial      = false;
  final _espInstCtrl     = TextEditingController();
  final _espProgCtrl     = TextEditingController();
  final _espFechaCtrl    = TextEditingController();
  String? _espUrl;

  bool _hasMaster        = false;
  final _maeInstCtrl     = TextEditingController();
  final _maeProgCtrl     = TextEditingController();
  final _maeFechaCtrl    = TextEditingController();
  String? _maeUrl;

  bool _hasCertificates  = false;
  final _certs           = <Certificado>[];

  final _exps            = <Experiencia>[Experiencia()];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final doc = await FirebaseFirestore.instance
        .collection('TBL_HojasVida')
        .doc(widget.userId)
        .get();
    if (!doc.exists) return;
    final d = doc.data()!;
    setState(() {
      _needsRevision = d['needsRevision'] == true;
      _revisionNote  = d['revisionNote'];
      _fotoUrl       = d['fotoUrl'];
      _cedulaUrl     = d['cedulaDocUrl'];
      _primerNombreCtrl.text    = d['primerNombre']    ?? '';
      _segundoNombreCtrl.text   = d['segundoNombre']   ?? '';
      _primerApellidoCtrl.text  = d['primerApellido']  ?? '';
      _segundoApellidoCtrl.text = d['segundoApellido'] ?? '';
      _lugarExpedCtrl.text      = d['lugarExpedicion']?? '';
      _emailCtrl.text           = d['email']           ?? '';
      _telefonoCtrl.text        = d['telefono']        ?? '';
      _direccionCtrl.text       = d['direccion']       ?? '';
      _ciudadCtrl.text          = d['ciudad']          ?? '';
      _procUrl   = d['procUrl'];
      _contrUrl  = d['contrUrl'];
      _polUrl    = d['polUrl'];
      _medUrl    = d['medUrl'];
      _bachInstCtrl.text   = d['bachInst']        ?? '';
      _bachFechaCtrl.text  = d['bachFecha']       ?? '';
      _bachUrl             = d['bachillerUrl'];
      _hasUniversity       = d['hasUniversity']   ?? false;
      _uniInstCtrl.text    = d['uniInst']         ?? '';
      _uniCarrCtrl.text    = d['uniCarr']         ?? '';
      _uniFechaCtrl.text   = d['uniFecha']        ?? '';
      _uniUrl              = d['uniUrl'];
      _hasProfCard         = d['hasTarjetaProf']  ?? false;
      _cardNumCtrl.text    = d['tarjetaNumero']   ?? '';
      _cardUrl             = d['tarjetaUrl'];
      _hasSecondDegree     = d['hasSecondCareer'] ?? false;
      _secInstCtrl.text    = d['secInst']         ?? '';
      _secCarrCtrl.text    = d['secCarr']         ?? '';
      _secFechaCtrl.text   = d['secFecha']        ?? '';
      _secUrl              = d['secUrl'];
      _hasEspecial         = d['hasEspecializacion'] ?? false;
      _espInstCtrl.text    = d['espInst']         ?? '';
      _espProgCtrl.text    = d['espProg']         ?? '';
      _espFechaCtrl.text   = d['espFecha']        ?? '';
      _espUrl              = d['espUrl'];
      _hasMaster           = d['hasMaestria']     ?? false;
      _maeInstCtrl.text    = d['maeInst']         ?? '';
      _maeProgCtrl.text    = d['maeProg']         ?? '';
      _maeFechaCtrl.text   = d['maeFecha']        ?? '';
      _maeUrl              = d['maeUrl'];
      _hasCertificates     = d['hasCertificados'] ?? false;
      _certs.clear();
      if (_hasCertificates) {
        for (var c in d['certificados'] as List<dynamic>) {
          final cert = Certificado()
            ..nombreCtrl.text = c['nombre'] ?? ''
            ..fechaCtrl.text  = c['fecha']  ?? ''
            ..url             = c['url'];
          _certs.add(cert);
        }
      }
      _exps.clear();
      for (var e in d['experiencias'] as List<dynamic>) {
        final exp = Experiencia()
          ..empresaCtrl.text = e['empresa']   ?? ''
          ..cargoCtrl.text   = e['cargo']     ?? ''
          ..inicioCtrl.text  = e['inicio']    ?? ''
          ..finCtrl.text     = e['fin']       ?? ''
          ..soporteUrl       = e['soporteUrl'];
        _exps.add(exp);
      }
    });

    if (_needsRevision && (_revisionNote?.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Corrección requerida'),
            content: Text(_revisionNote!),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
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
    _primerNombreCtrl.dispose();
    _segundoNombreCtrl.dispose();
    _primerApellidoCtrl.dispose();
    _segundoApellidoCtrl.dispose();
    _lugarExpedCtrl.dispose();
    _emailCtrl.dispose();
    _telefonoCtrl.dispose();
    _direccionCtrl.dispose();
    _ciudadCtrl.dispose();
    _bachInstCtrl.dispose();
    _bachFechaCtrl.dispose();
    _uniInstCtrl.dispose();
    _uniCarrCtrl.dispose();
    _uniFechaCtrl.dispose();
    _cardNumCtrl.dispose();
    _secInstCtrl.dispose();
    _secCarrCtrl.dispose();
    _secFechaCtrl.dispose();
    _espInstCtrl.dispose();
    _espProgCtrl.dispose();
    _espFechaCtrl.dispose();
    _maeInstCtrl.dispose();
    _maeProgCtrl.dispose();
    _maeFechaCtrl.dispose();
    for (var c in _certs) c.dispose();
    for (var e in _exps) e.dispose();
    super.dispose();
  }

  Future<void> _pickPhotoSource(ImageSource source) async {
    try {
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
        if (result == null) return;
        _fotoBytes = result.files.single.bytes;
      } else {
        final picker = ImagePicker();
        final picked = await picker.pickImage(source: source, imageQuality: 80);
        if (picked == null) return;
        _fotoBytes = await picked.readAsBytes();
      }
      setState(() => _fotoUrl = null);
    } catch (_) {}
  }

  Future<void> _pickFile(String tag, void Function(Uint8List) onBytes, void Function(String) onUrl) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf','png','jpg','jpeg'],
      withData: true,
    );
    if (result == null) return;
    final file = result.files.single;
    onBytes(file.bytes!);
    final uploaded = await _uploadBytes('$tag.${file.extension}', file.bytes!);
    onUrl(uploaded);
  }

  Future<String> _uploadBytes(String path, Uint8List bytes) async {
    final ref = FirebaseStorage.instance.ref('hojas/${widget.userId}/$path');
    await ref.putData(bytes);
    return ref.getDownloadURL();
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
          colorScheme: const ColorScheme.light(primary: _primaryColor),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      ctrl.text = DateFormat('MM/yyyy', 'es').format(picked);
    }
  }

  void _onContinue() {
    if (!_formKeys[_currentStep].currentState!.validate()) return;
    if (_currentStep < 4) {
      setState(() => _currentStep++);
    } else {
      _saveProfile();
    }
  }

  void _onCancel() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  Future<void> _saveProfile() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Guardando perfil...')),
          ],
        ),
      ),
    );

    String? photoUrl = _fotoUrl;
    if (_fotoBytes != null) {
      photoUrl = await _uploadBytes('foto.jpg', _fotoBytes!);
    }

    final primerNom = _primerNombreCtrl.text.trim();
    final primerApe = _primerApellidoCtrl.text.trim();

    final updateData = {
      'fotoUrl':             photoUrl,
      'cedulaDocUrl':        _cedulaUrl,
      'primerNombre':        primerNom,
      'primerApellido':      primerApe,
      'segundoNombre':       _segundoNombreCtrl.text.trim(),
      'segundoApellido':     _segundoApellidoCtrl.text.trim(),
      'lugarExpedicion':     _lugarExpedCtrl.text.trim(),
      'email':               _emailCtrl.text.trim(),
      'telefono':            _telefonoCtrl.text.trim(),
      'direccion':           _direccionCtrl.text.trim(),
      'ciudad':              _ciudadCtrl.text.trim(),
      'procUrl':             _procUrl,
      'contrUrl':            _contrUrl,
      'polUrl':              _polUrl,
      'medUrl':              _medUrl,
      'bachInst':            _bachInstCtrl.text.trim(),
      'bachFecha':           _bachFechaCtrl.text.trim(),
      'bachillerUrl':        _bachUrl,
      'hasUniversity':       _hasUniversity,
      'uniInst':             _uniInstCtrl.text.trim(),
      'uniCarr':             _uniCarrCtrl.text.trim(),
      'uniFecha':            _uniFechaCtrl.text.trim(),
      'uniUrl':              _uniUrl,
      'hasTarjetaProf':      _hasProfCard,
      'tarjetaNumero':       _cardNumCtrl.text.trim(),
      'tarjetaUrl':          _cardUrl,
      'hasSecondCareer':     _hasSecondDegree,
      'secInst':             _secInstCtrl.text.trim(),
      'secCarr':             _secCarrCtrl.text.trim(),
      'secFecha':            _secFechaCtrl.text.trim(),
      'secUrl':              _secUrl,
      'hasEspecializacion':  _hasEspecial,
      'espInst':             _espInstCtrl.text.trim(),
      'espProg':             _espProgCtrl.text.trim(),
      'espFecha':            _espFechaCtrl.text.trim(),
      'espUrl':              _espUrl,
      'hasMaestria':         _hasMaster,
      'maeInst':             _maeInstCtrl.text.trim(),
      'maeProg':             _maeProgCtrl.text.trim(),
      'maeFecha':            _maeFechaCtrl.text.trim(),
      'maeUrl':              _maeUrl,
      'hasCertificados':     _hasCertificates,
      'certificados':        _certs.map((c) => {
        'nombre': c.nombreCtrl.text.trim(),
        'fecha':  c.fechaCtrl.text.trim(),
        'url':    c.url,
      }).toList(),
      'experiencias':        _exps.map((e) => {
        'empresa':    e.empresaCtrl.text.trim(),
        'cargo':      e.cargoCtrl.text.trim(),
        'inicio':     e.inicioCtrl.text.trim(),
        'fin':        e.finCtrl.text.trim(),
        'soporteUrl': e.soporteUrl,
      }).toList(),
    };

    await FirebaseFirestore.instance
        .collection('TBL_HojasVida')
        .doc(widget.userId)
        .update(updateData);

    Navigator.of(context).pop(); // cierra diálogo
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perfil actualizado')),
    );
  }

  Widget _buildField(
      TextEditingController ctrl,
      String label, {
        List<TextInputFormatter>? extraFormatters,
        bool mandatory = true,
        TextInputFormatter? caseFormatter,
      }) {
    final formatters = <TextInputFormatter>[ caseFormatter ?? CapitalizeTextFormatter() ];
    if (extraFormatters != null) formatters.addAll(extraFormatters);
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label),
      inputFormatters: formatters,
      validator: mandatory
          ? (v) => v == null || v.trim().isEmpty ? 'Obligatorio' : null
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil', style: TextStyle(fontFamily: _arial)),
        backgroundColor: _primaryColor,
      ),
      body: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        onStepContinue: _onContinue,
        onStepCancel: _onCancel,
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            children: [
              ElevatedButton(
                onPressed: details.onStepContinue,
                style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                child: Text(_currentStep < 4 ? 'Siguiente' : 'Guardar cambios'),
              ),
              const SizedBox(width: 12),
              if (_currentStep > 0)
                ElevatedButton(
                  onPressed: details.onStepCancel,
                  style: ElevatedButton.styleFrom(backgroundColor: _accentColor),
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _fotoBytes != null
                        ? MemoryImage(_fotoBytes!)
                        : (_fotoUrl != null
                        ? NetworkImage(_fotoUrl!) as ImageProvider
                        : null),
                    child: (_fotoBytes == null && _fotoUrl == null)
                        ? const Icon(Icons.person, size: 60, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _pickPhotoSource(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Cámara'),
                        style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => _pickPhotoSource(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Galería'),
                        style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    _primerNombreCtrl,
                    'Primer Nombre',
                    extraFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚáéíóúñÑ ]"))
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    _segundoNombreCtrl,
                    'Segundo Nombre',
                    mandatory: false,
                    extraFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚáéíóúñÑ ]"))
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    _primerApellidoCtrl,
                    'Primer Apellido',
                    extraFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚáéíóúñÑ ]"))
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    _segundoApellidoCtrl,
                    'Segundo Apellido',
                    mandatory: false,
                    extraFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚáéíóúñÑ ]"))
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.userId,
                    decoration: const InputDecoration(labelText: 'Cédula'),
                    enabled: false,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    _lugarExpedCtrl,
                    'Lugar de expedición',
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
                  ElevatedButton.icon(
                    onPressed: () => launchUrlString(
                      'https://www.procuraduria.gov.co/Pages/Generacion-de-antecedentes.aspx',
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Generar Procuraduría'),
                    style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _pickFile(
                      'procuraduria',
                          (b) => _procBytes = b,
                          (u) => _procUrl = u,
                    ),
                    icon: const Icon(Icons.upload_file),
                    label: Text(_procUrl == null ? 'Subir Procuraduría' : 'Procuraduría subida'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _procUrl == null ? _primaryColor : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => launchUrlString(
                      'https://www.contraloria.gov.co/control-fiscal/responsabilidad-fiscal/certificado-de-antecedentes-fiscales',
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Generar Contraloría'),
                    style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _pickFile(
                      'contraloria',
                          (b) => _contrBytes = b,
                          (u) => _contrUrl = u,
                    ),
                    icon: const Icon(Icons.upload_file),
                    label: Text(_contrUrl == null ? 'Subir Contraloría' : 'Contraloría subida'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _contrUrl == null ? _primaryColor : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => launchUrlString(
                      'https://antecedentes.policia.gov.co:7005/WebJudicial/',
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Generar Policía'),
                    style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _pickFile(
                      'policia',
                          (b) => _polBytes = b,
                          (u) => _polUrl = u,
                    ),
                    icon: const Icon(Icons.upload_file),
                    label: Text(_polUrl == null ? 'Subir Policía' : 'Policía subida'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _polUrl == null ? _primaryColor : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => launchUrlString(
                      'https://srvcnpc.policia.gov.co/PSC/frm_cnp_consulta.aspx',
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Generar Medidas Correctivas'),
                    style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _pickFile(
                      'medidas',
                          (b) => _medBytes = b,
                          (u) => _medUrl = u,
                    ),
                    icon: const Icon(Icons.upload_file),
                    label: Text(_medUrl == null ? 'Subir Medidas' : 'Medidas subidas'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _medUrl == null ? _primaryColor : Colors.green,
                    ),
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
                  const Text('BACHILLERATO', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildField(_bachInstCtrl, 'Institución Bachillerato'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bachFechaCtrl,
                    readOnly: true,
                    onTap: () => _pickMonthYear(_bachFechaCtrl),
                    decoration: InputDecoration(
                      labelText: 'Fecha grado (MM/AAAA)',
                      suffixIcon: const Icon(Icons.calendar_month),
                    ),
                    validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => _pickFile(
                      'bachillerato',
                          (b) {},
                          (u) => _bachUrl = u,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _bachUrl == null ? _primaryColor : Colors.green,
                    ),
                    child: Text(_bachUrl == null ? 'Subir Soporte Bachillerato' : 'Soporte subido'),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Formación Universitaria'),
                    value: _hasUniversity,
                    onChanged: (v) => setState(() => _hasUniversity = v!),
                  ),
                  if (_hasUniversity) ...[
                    _buildField(_uniInstCtrl, 'Institución Universidad'),
                    const SizedBox(height: 12),
                    _buildField(_uniCarrCtrl, 'Carrera'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _uniFechaCtrl,
                      readOnly: true,
                      onTap: () => _pickMonthYear(_uniFechaCtrl),
                      decoration: InputDecoration(
                        labelText: 'Fecha grado (MM/AAAA)',
                        suffixIcon: const Icon(Icons.calendar_month),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text('¿Tiene Tarjeta Profesional?'),
                      value: _hasProfCard,
                      onChanged: (v) => setState(() => _hasProfCard = v!),
                    ),
                    if (_hasProfCard) ...[
                      _buildField(_cardNumCtrl, 'Número Tarjeta Profesional'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _pickFile(
                          'tarjeta',
                              (b) => _cardBytes = b,
                              (u) => _cardUrl = u,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _cardUrl == null ? _primaryColor : Colors.green,
                        ),
                        child: Text(_cardUrl == null ? 'Subir Tarjeta Profesional' : 'Tarjeta subida'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ElevatedButton(
                      onPressed: () => _pickFile(
                        'universidad',
                            (b) {},
                            (u) => _uniUrl = u,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _uniUrl == null ? _primaryColor : Colors.green,
                      ),
                      child: Text(_uniUrl == null ? 'Subir Soporte Universidad' : 'Soporte subido'),
                    ),
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
                    value: _hasCertificates,
                    onChanged: (v) => setState(() => _hasCertificates = v!),
                  ),
                  if (_hasCertificates) ...[
                    for (int i = 0; i < _certs.length; i++) ...[
                      TextFormField(
                        controller: _certs[i].nombreCtrl,
                        decoration: const InputDecoration(labelText: 'Nombre del Curso'),
                        validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _certs[i].fechaCtrl,
                        readOnly: true,
                        onTap: () => _pickMonthYear(_certs[i].fechaCtrl),
                        decoration: const InputDecoration(
                          labelText: 'Fecha (MM/AAAA)',
                          suffixIcon: Icon(Icons.calendar_month),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => _pickFile(
                          'curso_$i',
                              (b) => _certs[i].bytes = b,
                              (u) => _certs[i].url = u,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _certs[i].url == null ? _primaryColor : Colors.green,
                        ),
                        child: Text(_certs[i].url == null ? 'Subir Soporte' : 'Soporte subido'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _certs.add(Certificado())),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar Curso'),
                      style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Paso 4: Experiencia Laboral
          Step(
            title: const Text('Experiencia Laboral'),
            isActive: _currentStep >= 4,
            content: Form(
              key: _formKeys[4],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < _exps.length; i++) ...[
                    TextFormField(
                      controller: _exps[i].empresaCtrl,
                      decoration: const InputDecoration(labelText: 'Empresa'),
                      validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _exps[i].cargoCtrl,
                      decoration: const InputDecoration(labelText: 'Cargo'),
                      validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _exps[i].inicioCtrl,
                      readOnly: true,
                      onTap: () => _pickMonthYear(_exps[i].inicioCtrl),
                      decoration: const InputDecoration(
                        labelText: 'Inicio (MM/AAAA)',
                        suffixIcon: Icon(Icons.calendar_month),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _exps[i].finCtrl,
                      readOnly: true,
                      onTap: () => _pickMonthYear(_exps[i].finCtrl),
                      decoration: const InputDecoration(
                        labelText: 'Fin (MM/AAAA)',
                        suffixIcon: Icon(Icons.calendar_month),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Obligatorio' : null,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => _pickFile(
                        'exp_${i}',
                            (b) => _exps[i].soporteBytes = b,
                            (u) => _exps[i].soporteUrl = u,
                      ),
                      icon: const Icon(Icons.upload_file),
                      label: Text(_exps[i].soporteUrl == null ? 'Subir soporte' : 'Soporte subido'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _exps[i].soporteUrl == null ? _primaryColor : Colors.green,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _exps.add(Experiencia())),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar experiencia'),
                    style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
