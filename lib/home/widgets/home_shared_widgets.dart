// lib/home/widgets/home_shared_widgets.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:todo/theme/app_typography.dart';

class ModuleCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool compact;
  final double? width;

  const ModuleCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.compact = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: compact ? 2 : 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withOpacity(0.8),
                  color,
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min, // Prevents taking infinite height
              children: [
                Icon(
                  icon,
                  size: compact ? 24 : 32,
                  color: Colors.white,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 11 : 13,
                      fontFamily: kArial,
                      letterSpacing: -0.2,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontFamily: kArial,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class CompanyNameWidget extends StatelessWidget {
  final String empresaId;
  final TextStyle? style;
  final bool showIdIfNotFound;

  const CompanyNameWidget({
    super.key,
    required this.empresaId,
    this.style,
    this.showIdIfNotFound = true,
  });

  @override
  Widget build(BuildContext context) {
    if (empresaId.isEmpty || empresaId == 'Sin empresa') {
      return Text('Sin empresa', style: style);
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('TBL_EMPRESAS').doc(empresaId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text('...', style: style);
        }
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final nombre = data?['nombre'] ?? data?['nombreEmpresa'] ?? data?['alias'] ?? data?['razonSocial'];
          if (nombre != null && nombre.toString().isNotEmpty) {
            return Text(nombre.toString(), style: style, overflow: TextOverflow.ellipsis);
          }
        }
        return Text(showIdIfNotFound ? empresaId : 'Empresa desconocida', style: style, overflow: TextOverflow.ellipsis);
      },
    );
  }
}

class QuickActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const QuickActionChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primaryColor = color ?? scheme.primary;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        onPressed: onTap,
        backgroundColor: primaryColor.withOpacity(0.1),
        side: BorderSide(color: primaryColor.withOpacity(0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        avatar: Icon(icon, size: 16, color: primaryColor),
        label: Text(
          label,
          style: TextStyle(
            color: primaryColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: kArial,
          ),
        ),
      ),
    );
  }
}
