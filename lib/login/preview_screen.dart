//lib/login/preview_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'login_screen.dart'; // Asegúrate que el path sea correcto

const Color _accentColor = Color(0xFF145DA0);

class PreviewScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const PreviewScreen({Key? key, required this.data}) : super(key: key);

  Future<void> _openLink(BuildContext context, String url) async {
    if (!await launchUrlString(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace')),
      );
    }
  }

  Widget _buildDownloadButton(BuildContext context, String? url, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: url == null
          ? Text(
        '— $label: No cargado',
        style: TextStyle(color: Colors.red[700]),
      )
          : ElevatedButton.icon(
        onPressed: () => _openLink(context, url),
        icon: const Icon(Icons.download),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          minimumSize: const Size.fromHeight(40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Card _buildSectionCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const Divider(thickness: 1.2),
            ...children,
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndRegister(BuildContext context) async {
    // 1. Mostrar diálogo de confirmación
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar envío'),
        content: const Text('¿Estás seguro de querer subir la información?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // 2. Preparamos los datos (quitamos los bytes en crudo)
    final uploadData = Map<String, dynamic>.from(data)
      ..remove('fotoBytes');
    final empresaId = (data['empresaId'] as String?)?.trim() ?? '';
    if (empresaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falta el ID de la empresa.')),
      );
      return;
    }
    // 3. Subimos TODO + marcamos registrado + limpiamos revisión
    final usuariosCol =
    FirebaseFirestore.instance.collection('TBL_USUARIOS');
    final cedula = data['cedula'] as String;

    var docRef = usuariosCol.doc(cedula);
    final existing = await docRef.get();
    if (!existing.exists) {
      final query = await usuariosCol
          .where('cedula', isEqualTo: cedula)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        docRef = query.docs.first.reference;
      }
    }

    await docRef.set({
      ...uploadData,
      'registered': true,
      'needsRevision': false,
      'revisionNote': null,
      'updatedAt': FieldValue.serverTimestamp(),
      'correctionCount': 0,
    }, SetOptions(merge: true));

    // 4. Aviso al usuario
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('¡Información confirmada y registrada!')),
    );

    // 5. Volver al login
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final infoStyle = TextStyle(fontSize: 16, color: Colors.grey[800]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vista previa de datos'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // FOTO
            Center(
              child: FutureBuilder<String?>(
                future: () async {
                  // 1) Si el flujo normal subió bytes en memoria, no necesitamos Storage:
                  if (data['fotoBytes'] != null) return null;
                  final ced = data['cedula'] as String;
                  final folderRef = FirebaseStorage.instance.ref('cedulas/$ced');
                  try {
                    // 2) Listamos todos los ficheros bajo cedulas/<ced>
                    final listing = await folderRef.listAll();
                    // 3) Buscamos el que empiece por "foto."
                    final fileRef = listing.items.firstWhere(
                          (item) => item.name.startsWith('foto.'),
                      orElse: () => throw Exception('sin foto'),
                    );
                    // 4) Devolvemos su URL
                    return await fileRef.getDownloadURL();
                  } catch (_) {
                    return null; // no hay foto o error
                  }
                }(),
                builder: (ctx, snap) {
                  Widget child;
                  if (data['fotoBytes'] != null) {
                    // a) Usuario normal que acaba de subir foto:
                    child = ClipOval(
                      child: Image.memory(
                        data['fotoBytes'] as Uint8List,
                        fit: BoxFit.cover,
                        width: 120,
                        height: 120,
                      ),
                    );
                  } else if (snap.connectionState != ConnectionState.done) {
                    // b) Todavía buscando en Storage
                    child = const Center(child: CircularProgressIndicator());
                  } else {
                    final url = snap.data;
                    if (url != null) {
                      // c) Encontramos URL válida: la mostramos
                      child = ClipOval(
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          width: 120,
                          height: 120,
                          errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, size: 60, color: Colors.grey),
                        ),
                      );
                    } else {
                      // d) No hay bytes ni URL: icono genérico
                      child = const Icon(Icons.person, size: 60, color: Colors.grey);
                    }
                  }

                  return Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: child,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // DATOS PERSONALES
            _buildSectionCard(
              context: context,
              title: 'Datos personales',
              children: [
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge, color: _accentColor),
                  title: Text('Cédula: ${data['cedula']}', style: infoStyle),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person, color: _accentColor),
                  title: Text(
                    '${data['primerNombre']} ${data['segundoNombre']} '
                        '${data['primerApellido']} ${data['segundoApellido']}',
                    style: infoStyle,
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.place, color: _accentColor),
                  title: Text(
                    'Expedida en ${data['lugarExpedicion']}',
                    style: infoStyle,
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.email, color: _accentColor),
                  title: Text('Email: ${data['email']}', style: infoStyle),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone, color: _accentColor),
                  title: Text('Teléfono: ${data['telefono']}', style: infoStyle),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.home, color: _accentColor),
                  title: Text('Dirección: ${data['direccion']}', style: infoStyle),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_city, color: _accentColor),
                  title: Text('Ciudad: ${data['ciudad']}', style: infoStyle),
                ),
              ],
            ),

            // FORMACIÓN ACADÉMICA
            _buildSectionCard(
              context: context,
              title: 'Formación académica',
              children: [
                Text(
                  'Bachillerato: ${data['bachInst']} (${data['bachFecha']})',
                  style: infoStyle,
                ),
                if (data['hasUniversity'] == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Universidad: ${data['uniCarr']} en ${data['uniInst']} '
                        '(${data['uniFecha']})',
                    style: infoStyle,
                  ),
                ],
                if (data['hasTarjetaProf'] == true) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.card_membership, color: _accentColor),
                    title: Text(
                      'Tarjeta profesional: ${data['tarjetaNumero']}',
                      style: infoStyle,
                    ),
                  ),
                ],
                if (data['hasSecondCareer'] == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Segunda carrera: ${data['secCarr']} en ${data['secInst']} '
                        '(${data['secFecha']})',
                    style: infoStyle,
                  ),
                ],
                if (data['hasEspecializacion'] == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Especialización: ${data['espProg']} en ${data['espInst']} '
                        '(${data['espFecha']})',
                    style: infoStyle,
                  ),
                ],
                if (data['hasMaestria'] == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Maestría: ${data['maeProg']} en ${data['maeInst']} '
                        '(${data['maeFecha']})',
                    style: infoStyle,
                  ),
                ],
              ],
            ),

            // CURSOS COMPLEMENTARIOS
            if (data['hasCertificados'] == true)
              _buildSectionCard(
                context: context,
                title: 'Cursos complementarios',
                children: [
                  for (var c in data['certificados'] as List<dynamic>) ...[
                    Text('• ${c['nombre']} — ${c['fecha']}', style: infoStyle),
                  ],
                ],
              ),

            // EXPERIENCIA LABORAL
            _buildSectionCard(
              context: context,
              title: 'Experiencia laboral',
              children: [
                for (var exp in data['experiencias'] as List<dynamic>) ...[
                  Text(
                    '${exp['empresa']} — ${exp['cargo']} '
                        '(${exp['inicio']} a ${exp['fin']})',
                    style: infoStyle,
                  ),
                ],
              ],
            ),

            // COMPROBANTES
            _buildSectionCard(
              context: context,
              title: 'Comprobantes',
              children: [
                Text(
                  'Datos Personales',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                _buildDownloadButton(context, data['cedulaDocUrl'], 'Cédula'),
                const SizedBox(height: 12),
                Text(
                  'Antecedentes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                _buildDownloadButton(context, data['procUrl'], 'Procuraduría'),
                _buildDownloadButton(context, data['contrUrl'], 'Contraloría'),
                _buildDownloadButton(context, data['polUrl'], 'Policía'),
                _buildDownloadButton(context, data['medUrl'], 'Medidas Correctivas'),
                const SizedBox(height: 12),
                Text(
                  'Formación Académica',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                _buildDownloadButton(context, data['bachillerUrl'], 'Bachillerato'),
                if (data['hasUniversity'] == true)
                  _buildDownloadButton(context, data['uniUrl'], 'Universidad'),
                if (data['hasTarjetaProf'] == true)
                  _buildDownloadButton(context, data['tarjetaUrl'], 'Tarjeta Profesional'),
                if (data['hasSecondCareer'] == true)
                  _buildDownloadButton(context, data['secUrl'], 'Segunda Carrera'),
                if (data['hasEspecializacion'] == true)
                  _buildDownloadButton(context, data['espUrl'], 'Especialización'),
                if (data['hasMaestria'] == true)
                  _buildDownloadButton(context, data['maeUrl'], 'Maestría'),
                const SizedBox(height: 12),
                Text(
                  'Experiencia Laboral',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                for (var exp in data['experiencias'] as List<dynamic>) ...[
                  _buildDownloadButton(
                    context,
                    exp['soporteUrl'] as String?,
                    'Soporte ${exp['empresa']}',
                  ),
                ],
                if (data['hasCertificados'] == true)
                  ...[
                    const SizedBox(height: 12),
                    Text(
                      'Cursos Complementarios',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _accentColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (var c in data['certificados'] as List<dynamic>) ...[
                      _buildDownloadButton(
                        context,
                        c['url'] as String?,
                        'Soporte ${c['nombre']}',
                      ),
                    ],
                  ],
              ],
            ),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Corregir'),
                ),
                ElevatedButton(
                  onPressed: () => _confirmAndRegister(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Confirmar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
