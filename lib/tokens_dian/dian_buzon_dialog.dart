import 'package:flutter/material.dart';

import 'dian_tokens_models.dart';
import 'dian_tokens_service.dart';

/// Diálogo de conexión del buzón, compartido por Admin → Tokens DIAN y por el
/// propio módulo. Vive aparte para que no haya dos versiones del formulario:
/// quien conecta el buzón debe ver siempre el mismo texto sobre qué se lee.
///
/// La contraseña de aplicación solo existe dentro de esta función: viaja al
/// backend, que la prueba contra el servidor IMAP y la cifra. Nunca se guarda
/// en el dispositivo ni vuelve a la app.
///
/// Devuelve el estado nuevo del buzón, o `null` si se canceló o falló.
Future<DianBuzonEstado?> mostrarDialogoConectarBuzon({
  required BuildContext context,
  required DianTokensService service,
  required String empresaId,
  required String userId,
  DianBuzonEstado estadoActual = DianBuzonEstado.sinConectar,
}) async {
  final email = TextEditingController(text: estadoActual.email);
  final password = TextEditingController();
  var historicos = estadoActual.procesarHistoricos;

  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setDialogState) => AlertDialog(
        title: const Text('Conectar buzon Yahoo'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDFA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF99F6E4)),
                  ),
                  child: Text(
                    estadoActual.descripcionFiltro,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF115E59),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Correo del buzon que recibe los tokens',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NO uses la clave con la que entras a Yahoo',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Yahoo bloquea esa clave a proposito. Necesitas una '
                        'contrasena de aplicacion, que se genera asi:\n'
                        '1. Entra a Yahoo con tu clave normal\n'
                        '2. Informacion de la cuenta > Seguridad de la cuenta\n'
                        '3. Generar contrasena de aplicacion\n'
                        '4. Copia la clave que te muestra y pegala abajo\n\n'
                        'Se pone una sola vez. Despues los tokens entran solos.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contrasena de aplicacion de Yahoo',
                    helperMaxLines: 2,
                    helperText:
                        'Si Yahoo te la muestra separada en grupos de cuatro, '
                        'pegala tal cual: los espacios se quitan solos.',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: historicos,
                  onChanged: (value) => setDialogState(() => historicos = value),
                  title: const Text('Revisar tokens DIAN anteriores'),
                  subtitle: const Text(
                    'Apagado solo trae los correos DIAN de los ultimos tres '
                    'dias en adelante.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.link),
            label: const Text('Probar y conectar'),
          ),
        ],
      ),
    ),
  );

  final correo = email.text.trim();
  final clave = password.text.trim();
  email.dispose();
  password.dispose();

  if (confirmado != true) return null;
  if (correo.isEmpty || clave.isEmpty) {
    throw StateError('Indica el correo y la contrasena de aplicacion.');
  }
  return service.conectarBuzon(
    empresaId: empresaId,
    userId: userId,
    email: correo,
    appPassword: clave,
    procesarHistoricos: historicos,
  );
}
