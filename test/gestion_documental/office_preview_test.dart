import 'package:flutter_test/flutter_test.dart';
import 'package:todo/widgets/office_preview/office_preview.dart';

void main() {
  test('Word y Excel tienen visor; otros formatos no', () {
    expect(tieneVistaPreviaOffice('informe.DOCX'), isTrue);
    expect(tieneVistaPreviaOffice('datos.xlsx'), isTrue);
    expect(tieneVistaPreviaOffice('acta.pdf'), isFalse);
  });

  test('la URL del archivo queda codificada para el visor', () {
    const url = 'https://storage.example/doc.xlsx?token=a&b=c';
    expect(urlVisorOffice(url), contains(Uri.encodeComponent(url)));
    expect(urlVisorGoogle(url), contains(Uri.encodeComponent(url)));
  });
}
