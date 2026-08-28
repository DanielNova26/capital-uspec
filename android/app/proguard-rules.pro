# Reglas R8 para el build de release.

# --- ML Kit: reconocedores de texto no-latinos ---
# google_mlkit_text_recognition referencia los reconocedores de chino,
# devanagari, japones y coreano, pero sus artefactos no se incluyen como
# dependencia (la app solo escanea texto latino). Sin estas reglas R8 aborta
# con "Missing classes detected while running R8".
# Si algun dia se necesita otro alfabeto, hay que agregar la dependencia
# correspondiente (com.google.mlkit:text-recognition-<idioma>) en vez de
# ampliar esta lista.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
