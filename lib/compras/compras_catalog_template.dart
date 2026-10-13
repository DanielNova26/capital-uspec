import 'dart:typed_data';

import 'compras_excel_export.dart';
import 'compras_models.dart';

/// Plantillas generadas por la app con los mismos catálogos del importador.
/// La hoja de carga va vacía: los ejemplos nunca se convierten en registros.
Uint8List construirPlantillaCatalogo({required bool proveedores}) {
  final columnas = proveedores
      ? const [
          'NIT',
          'RAZON SOCIAL',
          'DIRECCION',
          'TELEFONO',
          'CORREO',
          'DEPARTAMENTO',
          'CIUDAD',
          'PROV. LOCAL',
          'PEQUENO PRODUCTOR AGROPECUARIO',
        ]
      : const [
          'CODIGO_PRODUCTO',
          'NOMBRE_PRODUCTO',
          'CATEGORIA',
          'UNIDAD_MEDIDA',
          'ORIGEN',
          'PERECEDERO',
        ];
  return construirExcelHojas([
    HojaExcelConsulta(
      nombre: proveedores ? 'PROVEEDORES' : 'PRODUCTOS',
      columnas: columnas,
      filas: const [],
      ajustarTexto: true,
    ),
    HojaExcelConsulta(
      nombre: 'INSTRUCCIONES',
      ajustarTexto: true,
      columnas: const ['Campo', 'Cómo diligenciar'],
      filas: [
        [
          'Carga',
          'Diligencie la primera hoja desde la fila 2. Conserve los encabezados. Guarde como .xlsx.',
        ],
        ['Empresa', 'Los registros se agregan únicamente a la empresa activa.'],
        [
          'Duplicados',
          proveedores
              ? 'Se omiten NIT existentes; no se actualizan.'
              : 'Se omiten códigos o nombres existentes; no se actualizan.',
        ],
        if (proveedores) ...[
          [
            'NIT / RAZON SOCIAL',
            'Obligatorios. Use texto para NIT y teléfono, conservando ceros iniciales.',
          ],
          ['PROV. LOCAL', 'SI o NO. Vacío equivale a NO.'],
          [
            'PEQUENO PRODUCTOR AGROPECUARIO',
            'SI o NO. Vacío equivale a NO. Es independiente de proveedor local.',
          ],
          [
            'Referencia',
            'Ley 2046 de 2020 y Decreto 248 de 2021. La marca identifica al proveedor; no acredita por sí sola el cumplimiento legal.',
          ],
          [
            'Normativa',
            'https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=159934',
          ],
          [
            'Otros campos',
            'Dirección, teléfono, correo, departamento y ciudad son opcionales.',
          ],
        ] else ...[
          [
            'NOMBRE_PRODUCTO / CATEGORIA / UNIDAD_MEDIDA',
            'Obligatorios. Consulte los valores permitidos en CATALOGOS.',
          ],
          [
            'CODIGO_PRODUCTO',
            'Opcional. Use texto para conservar ceros iniciales.',
          ],
          ['ORIGEN', 'NACIONAL o IMPORTADO. Vacío equivale a NACIONAL.'],
          ['PERECEDERO', 'SI o NO. Vacío equivale a NO.'],
        ],
      ],
    ),
    if (!proveedores)
      HojaExcelConsulta(
        nombre: 'CATALOGOS',
        columnas: const ['Tipo', 'Valor permitido'],
        filas: [
          for (final v in kCategoriasCompras) ['CATEGORIA', v],
          for (final v in kUnidadesMedida) ['UNIDAD_MEDIDA', v],
          ['ORIGEN', 'NACIONAL'],
          ['ORIGEN', 'IMPORTADO'],
          ['PERECEDERO', 'SI'],
          ['PERECEDERO', 'NO'],
        ],
      ),
  ]);
}
