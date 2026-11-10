import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gd_formato_plantilla.dart';

Future<int?> gdElegirCantidadHojas(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (_) => const _CantidadHojasDialog(),
  );
}

class _CantidadHojasDialog extends StatefulWidget {
  const _CantidadHojasDialog();

  @override
  State<_CantidadHojasDialog> createState() => _CantidadHojasDialogState();
}

class _CantidadHojasDialogState extends State<_CantidadHojasDialog> {
  final _formKey = GlobalKey<FormState>();
  int _cantidad = 1;

  void _descargar() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    Navigator.of(context).pop(_cantidad);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Plantilla Excel'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cada hoja incluye el encabezado institucional. Puedes '
              'renombrar las pestañas o agregar más en Excel.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: '1',
              decoration: const InputDecoration(
                labelText: 'Cantidad de hojas',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              validator: (texto) {
                final cantidad = int.tryParse(texto ?? '');
                if (cantidad == null ||
                    cantidad < 1 ||
                    cantidad > kGdPlantillaMaxHojas) {
                  return 'Elige entre 1 y $kGdPlantillaMaxHojas hojas.';
                }
                return null;
              },
              onSaved: (texto) => _cantidad = int.parse(texto!),
              onFieldSubmitted: (_) => _descargar(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _descargar, child: const Text('Descargar')),
      ],
    );
  }
}
