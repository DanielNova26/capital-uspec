import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

const String kArial = 'Arial';
const Color kDocumentBlue = Color(0xFF145DA0);

class DocumentManagementScreen extends StatefulWidget {
  final String currentUserId;

  const DocumentManagementScreen({
    Key? key,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<DocumentManagementScreen> createState() => _DocumentManagementScreenState();
}

class _DocumentManagementScreenState extends State<DocumentManagementScreen> {
  final List<PlatformFile> _pickedDocs = [];
  final List<PlatformFile> _pickedSignatures = [];

  final List<_DocumentRecord> _records = [
    _DocumentRecord(
      titulo: 'Procedimiento de Inducción',
      codigo: 'DOC-IND-001',
      version: 'v2.1',
      estado: _DocumentStatus.revisado,
      creadoPor: 'Laura Gómez',
      revisadoPor: 'Diego Vargas',
      aprobadoPor: '',
      fechaActualizacion: DateTime.now().subtract(const Duration(days: 2)),
    ),
    _DocumentRecord(
      titulo: 'Política de Seguridad de la Información',
      codigo: 'DOC-SEG-004',
      version: 'v1.4',
      estado: _DocumentStatus.aprobado,
      creadoPor: 'Camila Ruiz',
      revisadoPor: 'Jorge Peña',
      aprobadoPor: 'Patricia Salazar',
      fechaActualizacion: DateTime.now().subtract(const Duration(days: 5)),
    ),
    _DocumentRecord(
      titulo: 'Formato de Solicitud de Compras',
      codigo: 'DOC-COM-010',
      version: 'v3.0',
      estado: _DocumentStatus.subido,
      creadoPor: 'Miguel Díaz',
      revisadoPor: '',
      aprobadoPor: '',
      fechaActualizacion: DateTime.now().subtract(const Duration(hours: 8)),
    ),
  ];

  Future<void> _pickWordFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['doc', 'docx'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedDocs.addAll(result.files));
    }
  }

  Future<void> _pickSignature() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['png'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedSignatures.addAll(result.files));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión documental', style: TextStyle(fontFamily: kArial)),
        backgroundColor: kDocumentBlue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderCard(
              onUpload: _pickWordFile,
              onSignature: _pickSignature,
              pickedDocs: _pickedDocs,
              pickedSignatures: _pickedSignatures,
            ),
            const SizedBox(height: 20),
            Text(
              'Flujo de estados',
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: kArial,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _StatusFlowRow(),
            const SizedBox(height: 28),
            Text(
              'Documentos recientes',
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: kArial,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (_, index) => _DocumentCard(record: _records[index]),
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemCount: _records.length,
            ),
            const SizedBox(height: 28),
            Text(
              'Recomendación de plantilla Word',
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: kArial,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _TemplateGuideCard(),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final VoidCallback onUpload;
  final VoidCallback onSignature;
  final List<PlatformFile> pickedDocs;
  final List<PlatformFile> pickedSignatures;

  const _HeaderCard({
    required this.onUpload,
    required this.onSignature,
    required this.pickedDocs,
    required this.pickedSignatures,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: kDocumentBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDocumentBlue.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sube documentos Word y firma digital',
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: kArial,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Carga el archivo .docx, define el estado y agrega firmas en PNG con fondo transparente. '
                'Aquí puedes visualizar rápidamente quién creó, revisó o aprobó el documento.',
            style: theme.textTheme.bodyMedium?.copyWith(fontFamily: kArial),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_file),
                label: const Text('Subir Word', style: TextStyle(fontFamily: kArial)),
              ),
              OutlinedButton.icon(
                onPressed: onSignature,
                icon: const Icon(Icons.draw),
                label: const Text('Agregar firma PNG', style: TextStyle(fontFamily: kArial)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PickedFilesSection(
            title: 'Archivos Word listos para revisar',
            files: pickedDocs,
            emptyMessage: 'Aún no has subido documentos.',
            icon: Icons.description,
          ),
          const SizedBox(height: 12),
          _PickedFilesSection(
            title: 'Firmas digitales disponibles',
            files: pickedSignatures,
            emptyMessage: 'Sin firmas cargadas.',
            icon: Icons.verified,
          ),
        ],
      ),
    );
  }
}

class _PickedFilesSection extends StatelessWidget {
  final String title;
  final List<PlatformFile> files;
  final String emptyMessage;
  final IconData icon;

  const _PickedFilesSection({
    required this.title,
    required this.files,
    required this.emptyMessage,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: kDocumentBlue),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFamily: kArial,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (files.isEmpty)
          Text(
            emptyMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: kArial,
              color: Colors.black54,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: files
                .map(
                  (file) => Chip(
                avatar: const Icon(Icons.insert_drive_file, size: 18),
                label: Text(file.name, style: const TextStyle(fontFamily: kArial)),
              ),
            )
                .toList(),
          ),
      ],
    );
  }
}

class _StatusFlowRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _StatusNode(label: 'Subido', icon: Icons.cloud_done, isActive: true),
        _StatusConnector(),
        _StatusNode(label: 'Revisado', icon: Icons.fact_check, isActive: true),
        _StatusConnector(),
        _StatusNode(label: 'Aprobado', icon: Icons.verified, isActive: true),
      ],
    );
  }
}

class _StatusNode extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;

  const _StatusNode({
    required this.label,
    required this.icon,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? kDocumentBlue : Colors.grey;

    return Column(
      children: [
        CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          radius: 22,
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontFamily: kArial, color: color)),
      ],
    );
  }
}

class _StatusConnector extends StatelessWidget {
  const _StatusConnector();

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        height: 2,
        color: kDocumentBlue.withOpacity(0.4),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final _DocumentRecord record;

  const _DocumentCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = record.estado.color;
    final formattedDate =
        '${record.fechaActualizacion.day.toString().padLeft(2, '0')}/'
        '${record.fechaActualizacion.month.toString().padLeft(2, '0')}/'
        '${record.fechaActualizacion.year}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.titulo,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: kArial,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${record.codigo} · ${record.version} · Act. $formattedDate',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: kArial,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Chip(
                backgroundColor: statusColor.withOpacity(0.15),
                label: Text(
                  record.estado.label,
                  style: TextStyle(fontFamily: kArial, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _StatusStepper(currentStatus: record.estado),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _PersonTag(label: 'Creado por', name: record.creadoPor),
              _PersonTag(label: 'Revisado por', name: record.revisadoPor),
              _PersonTag(label: 'Aprobado por', name: record.aprobadoPor),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: _StampBadge(text: record.estado.stamp),
          ),
        ],
      ),
    );
  }
}

class _StatusStepper extends StatelessWidget {
  final _DocumentStatus currentStatus;

  const _StatusStepper({required this.currentStatus});

  @override
  Widget build(BuildContext context) {
    final steps = _DocumentStatus.values;

    return Row(
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        final isActive = step.index <= currentStatus.index;
        final color = isActive ? step.color : Colors.grey.shade400;

        return Expanded(
          child: Column(
            children: [
              Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                step.label,
                style: TextStyle(
                  fontFamily: kArial,
                  fontSize: 12,
                  color: color,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _PersonTag extends StatelessWidget {
  final String label;
  final String name;

  const _PersonTag({
    required this.label,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = name.isEmpty ? 'Pendiente' : name;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: kDocumentBlue.withOpacity(0.15),
          child: Icon(
            Icons.person,
            size: 16,
            color: kDocumentBlue,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(fontFamily: kArial)),
            Text(
              displayName,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: kArial,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StampBadge extends StatelessWidget {
  final String text;

  const _StampBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kDocumentBlue.withOpacity(0.5)),
        color: kDocumentBlue.withOpacity(0.08),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontFamily: kArial,
          fontWeight: FontWeight.bold,
          color: kDocumentBlue,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _TemplateGuideCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estructura sugerida',
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: kArial,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          _BulletItem(text: 'Encabezado con logo, nombre del proceso y código del documento.'),
          _BulletItem(text: 'Tabla de control: versión, fecha, área responsable y estado actual.'),
          _BulletItem(text: 'Cuerpo en secciones numeradas para facilitar la lectura y auditorías.'),
          _BulletItem(text: 'Bloque de firmas: elaborado por, revisado por, aprobado por con espacio para PNG.'),
          _BulletItem(text: 'Pie de página con sello visible: “EN REVISIÓN” o “APROBADO” según el estado.'),
          const SizedBox(height: 16),
          Text(
            'Sugerencia de sellos',
            style: theme.textTheme.titleSmall?.copyWith(
              fontFamily: kArial,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: const [
              _StampBadge(text: 'En revisión'),
              _StampBadge(text: 'Aprobado'),
            ],
          ),
        ],
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  final String text;

  const _BulletItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontFamily: kArial, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DocumentStatus {
  subido('Subido', 'Subido'),
  revisado('Revisado', 'En revisión'),
  aprobado('Aprobado', 'Aprobado');

  final String label;
  final String stamp;

  const _DocumentStatus(this.label, this.stamp);

  Color get color {
    switch (this) {
      case _DocumentStatus.subido:
        return const Color(0xFF2F74C0);
      case _DocumentStatus.revisado:
        return const Color(0xFFF2A900);
      case _DocumentStatus.aprobado:
        return const Color(0xFF2E7D32);
    }
  }
}

class _DocumentRecord {
  final String titulo;
  final String codigo;
  final String version;
  final _DocumentStatus estado;
  final String creadoPor;
  final String revisadoPor;
  final String aprobadoPor;
  final DateTime fechaActualizacion;

  _DocumentRecord({
    required this.titulo,
    required this.codigo,
    required this.version,
    required this.estado,
    required this.creadoPor,
    required this.revisadoPor,
    required this.aprobadoPor,
    required this.fechaActualizacion,
  });
}