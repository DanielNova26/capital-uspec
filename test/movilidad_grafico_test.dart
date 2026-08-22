// Verifica que las gráficas del informe de movilidad se rendericen sin
// reventar: los ejes del paquete `pdf` exigen valores ascendentes y es fácil
// romperlos con datos reales (un solo punto, valores muy pequeños, ceros).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

List<double> ejeY(double maximo) {
  if (maximo <= 0) return [0, 1];
  final crudo = maximo / 4;
  final magnitud = math.pow(10, (math.log(crudo) / math.ln10).floor());
  final paso = (crudo / magnitud).ceil() * magnitud.toDouble();
  final n = (maximo / maximo.clamp(1e-9, double.infinity) * (maximo / paso))
          .ceil() +
      1;
  return List.generate(n, (i) => i * paso);
}

pw.Widget grafico(List<String> etiquetas, List<double> valores,
    {bool lineas = false}) {
  final maximo = valores.reduce((a, b) => a > b ? a : b);
  final datos = <pw.PointChartValue>[
    for (var i = 0; i < valores.length; i++)
      pw.PointChartValue(i.toDouble(), valores[i]),
  ];
  return pw.SizedBox(
    height: 160,
    child: pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis<int>(
          List.generate(math.max(2, etiquetas.length), (i) => i),
          buildLabel: (v) {
            final i = v.toInt();
            if (i < 0 || i >= etiquetas.length) return pw.SizedBox();
            return pw.Text(
              etiquetas[i],
              style: const pw.TextStyle(fontSize: 6.5),
            );
          },
          marginStart: 20,
          marginEnd: 20,
        ),
        yAxis: pw.FixedAxis<double>(
          ejeY(maximo),
          format: (v) => v.toStringAsFixed(0),
          textStyle: const pw.TextStyle(fontSize: 6.5),
          divisions: true,
        ),
      ),
      datasets: [
        if (lineas)
          pw.LineDataSet(
            data: datos,
            color: PdfColors.green,
            drawSurface: true,
            isCurved: true,
          )
        else
          pw.BarDataSet(
            data: datos,
            color: PdfColors.blue,
            width: (330 / etiquetas.length).clamp(4.0, 22.0),
          ),
      ],
    ),
  );
}

void main() {
  test('la escala del eje Y siempre queda ascendente', () {
    for (final max in [0.0, 0.5, 1.0, 7.3, 85.0, 134.2, 1200.0]) {
      final eje = ejeY(max);
      expect(eje.length, greaterThan(1), reason: 'max=$max');
      for (var i = 1; i < eje.length; i++) {
        expect(eje[i], greaterThan(eje[i - 1]), reason: 'max=$max eje=$eje');
      }
      expect(eje.last, greaterThanOrEqualTo(max), reason: 'max=$max');
    }
  });

  test('las gráficas del informe se renderizan a PDF', () async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          // Casos reales del estudio.
          grafico(['04:00', '05:00', '06:00', '10:00', '11:00'],
              [16, 18, 18, 65, 69],
              lineas: true),
          grafico(['Ruta 1', 'Ruta 3', 'Ruta 5', 'Ruta 7', 'Ruta 8'],
              [134.2, 104.9, 93.6, 178.3, 102.3]),
          grafico(['Bajo', 'Medio', 'Alto', 'Crítico'], [120, 80, 40, 10]),
          // Bordes: una sola barra y valores en cero.
          grafico(['Único'], [42]),
          grafico(['A', 'B'], [0, 0]),
        ],
      ),
    );
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(1000));
  });
}
