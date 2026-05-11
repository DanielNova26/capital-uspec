import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

Future<String> recognizeTextFromXFile(XFile file) async {
  try {
    final inputImage = InputImage.fromFilePath(file.path);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final result = await recognizer.processImage(inputImage);
    await recognizer.close();
    return result.text.trim();
  } catch (_) {
    return '';
  }
}
