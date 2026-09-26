import Flutter
import GoogleMaps
import PDFKit
import UIKit
import VisionKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var escanerDocumentos: EscanerDocumentos?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyD8posdo50hmD8PLPD9kR6IebNYfi6PkPs")
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "EscanerDocumentos") {
      escanerDocumentos = EscanerDocumentos(
        messenger: registrar.messenger(),
        raiz: { [weak self] in self?.window?.rootViewController }
      )
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// Escáner de documentos de iOS para Compras (`compras_document_scanner_io.dart`).
///
/// En Android lo hace ML Kit (google_mlkit_document_scanner), que no tiene
/// versión para iOS: por eso el botón "Escanear documento" no existía en
/// iPhone ni iPad. Aquí se usa el de Apple (VisionKit), que hace lo mismo:
/// detecta los bordes, recorta, endereza y admite varias páginas. Las páginas
/// se unen en un PDF con PDFKit y se devuelven como bytes, igual que en Android.
final class EscanerDocumentos: NSObject, VNDocumentCameraViewControllerDelegate {
  private let canal: FlutterMethodChannel
  private let raiz: () -> UIViewController?
  private var pendiente: FlutterResult?

  init(messenger: FlutterBinaryMessenger, raiz: @escaping () -> UIViewController?) {
    self.canal = FlutterMethodChannel(name: "todo/escaner_documentos", binaryMessenger: messenger)
    self.raiz = raiz
    super.init()
    canal.setMethodCallHandler { [weak self] llamada, resultado in
      guard let self = self else {
        resultado(FlutterMethodNotImplemented)
        return
      }
      switch llamada.method {
      case "disponible":
        resultado(VNDocumentCameraViewController.isSupported)
      case "escanearPdf":
        self.escanear(resultado)
      default:
        resultado(FlutterMethodNotImplemented)
      }
    }
  }

  private func escanear(_ resultado: @escaping FlutterResult) {
    guard pendiente == nil else {
      resultado(FlutterError(code: "ocupado", message: "Ya hay un escaneo abierto.", details: nil))
      return
    }
    guard VNDocumentCameraViewController.isSupported else {
      resultado(
        FlutterError(
          code: "no_disponible",
          message: "Este equipo no permite escanear documentos.",
          details: nil))
      return
    }
    guard var visible = raiz() else {
      resultado(
        FlutterError(
          code: "sin_pantalla",
          message: "No se encontró la pantalla para abrir el escáner.",
          details: nil))
      return
    }
    while let encima = visible.presentedViewController {
      visible = encima
    }
    pendiente = resultado
    let camara = VNDocumentCameraViewController()
    camara.delegate = self
    visible.present(camara, animated: true, completion: nil)
  }

  private func terminar(_ camara: VNDocumentCameraViewController, con valor: Any?) {
    let resultado = pendiente
    pendiente = nil
    camara.dismiss(animated: true) {
      resultado?(valor)
    }
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFinishWith scan: VNDocumentCameraScan
  ) {
    let pdf = PDFDocument()
    for indice in 0..<scan.pageCount {
      if let pagina = PDFPage(image: scan.imageOfPage(at: indice)) {
        pdf.insert(pagina, at: pdf.pageCount)
      }
    }
    guard pdf.pageCount > 0, let datos = pdf.dataRepresentation() else {
      terminar(controller, con: nil)
      return
    }
    terminar(controller, con: FlutterStandardTypedData(bytes: datos))
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    terminar(controller, con: nil)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFailWithError error: Error
  ) {
    terminar(
      controller,
      con: FlutterError(
        code: "error_escaner", message: error.localizedDescription, details: nil))
  }
}
