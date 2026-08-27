// lib/widgets/hidden_admin_unlocker.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HiddenAdminUnlocker extends StatefulWidget {
  final Widget child;               // p.ej. el logo
  final VoidCallback onUnlocked;    // navegar al panel

  const HiddenAdminUnlocker({
    Key? key,
    required this.child,
    required this.onUnlocked,
  }) : super(key: key);

  @override
  State<HiddenAdminUnlocker> createState() => _HiddenAdminUnlockerState();
}

class _HiddenAdminUnlockerState extends State<HiddenAdminUnlocker> {
  int _tapCount = 0;
  DateTime? _firstTapTime;

  Future<bool> _verifyPin(BuildContext context) async {
    // Messenger tomado antes de los await: el diálogo y la lectura de Firestore
    // pueden terminar con la pantalla ya cerrada.
    final messenger = ScaffoldMessenger.of(context);
    final pinCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Ingreso de administrador'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: pinCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'PIN de administrador',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => formKey.currentState!.validate()
                  ? Navigator.pop(ctx, true)
                  : null,
              child: const Text('Entrar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return false;

    // Lee PIN desde Firestore (TBL_CONFIG/SECURITY seedAdminPin) o usa "2468" por defecto
    final db = FirebaseFirestore.instance;
    try {
      final doc = await db.collection('TBL_CONFIG').doc('SECURITY').get();
      final expected = (doc.data()?['seedAdminPin'] ?? '2468').toString();
      if (pinCtrl.text.trim() == expected) return true;
      messenger.showSnackBar(
        const SnackBar(content: Text('PIN incorrecto')),
      );
      return false;
    } catch (_) {
      // Si no existe config, aceptar "2468"
      return pinCtrl.text.trim() == '2468';
    }
  }

  void _onTap() async {
    final now = DateTime.now();
    if (_firstTapTime == null || now.difference(_firstTapTime!) > const Duration(seconds: 1)) {
      _firstTapTime = now;
      _tapCount = 1;
    } else {
      _tapCount++;
      if (_tapCount >= 3) {
        _tapCount = 0;
        _firstTapTime = null;
        if (await _verifyPin(context)) {
          widget.onUnlocked();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: _onTap, child: widget.child);
  }
}
