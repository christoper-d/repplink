library;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';



/// Clase para manejar enlaces de Google Drive y descargar archivos.
///
/// Ejemplo básico:
/// ```dart
/// final repplink = Repplink('https://drive.google.com/file/d/ID_DEL_ARCHIVO/view');
/// final accessible = await repplink.isAccessible();
/// if (accessible) {
///   final data = await repplink.start<List<List<String>>>();
///   print(data);
/// }
/// ```
class Repplink {
  /// Enlace original de Google Drive que debe cumplir con el formato:
  /// https://drive.google.com/file/d/FILE_ID/view
  final String rawLink;

  /// Constructor que valida el formato del enlace.
  ///
  /// Lanza [FormatException] si el enlace no es válido.
  Repplink(this.rawLink) {
    if (!_isValidGoogleDriveLink(rawLink)) {
      throw FormatException('El enlace no es válido de Google Drive.');
    }
  }

  /// Valida que el enlace tenga el formato esperado de Google Drive.
  bool _isValidGoogleDriveLink(String link) {
    final regExp = RegExp(r'^https:\/\/drive\.google\.com\/file\/d\/([a-zA-Z0-9_-]+)\/view.*$');
    return regExp.hasMatch(link);
  }

  /// Extrae el ID del archivo del enlace.
  String get fileId {
    final match = RegExp(r'^https:\/\/drive\.google\.com\/file\/d\/([a-zA-Z0-9_-]+)\/view.*$')
        .firstMatch(rawLink);
    return match?.group(1) ?? '';
  }

  /// Genera un enlace directo para descargar el archivo desde Google Drive.
  String get directDownloadLink => 'https://drive.google.com/uc?export=download&id=$fileId';

  /// Verifica si el archivo está accesible haciendo una petición HEAD.
  ///
  /// Retorna `true` si el código de respuesta es 200.
  Future<bool> isAccessible() async {
    final response = await http.head(Uri.parse(directDownloadLink));
    return response.statusCode == 200;
  }

  /// Descarga el archivo de Google Drive y opcionalmente parsea su contenido.
  ///
  /// - Si se llama sin tipo genérico, solo descarga el archivo en una carpeta temporal y no devuelve nada.
  /// - Si se llama con `T == List<List<String>>`, lee el archivo, separa por líneas y por `|` y devuelve la lista de listas de strings.
  ///
  /// En ambos casos, el archivo temporal se elimina después de su uso.
  ///
  /// Ejemplo para obtener datos parseados:
  /// ```dart
  /// final data = await repplink.start<List<List<String>>>();
  /// ```
  Future<T?> start<T>() async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$fileId.tmp';
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }

    final response = await http.get(Uri.parse(directDownloadLink));

    if (response.statusCode == 200) {
      await file.writeAsBytes(response.bodyBytes);

      if (T == List<List<dynamic>>) {
        try {
          final content = await file.readAsString();
          final lines = content
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();

          // final parsed = lines.map((line) {
          //   final parts = line.split('|').where((p) => p.trim().isNotEmpty).toList();
          //   return parts;
          // }).where((parts) => parts.isNotEmpty).toList();

          final parsed = lines.map((line) {
            final parts = line
                .split('|')
                .map((p) => p.trim())
                .where((p) => p.isNotEmpty)
                .map((p) {
              // Si el campo contiene comas, lo convertimos en lista
              if (p.contains(',')) {
                return p
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
              } else {
                return p;
              }
            })
                .toList();

            return parts;
          }).where((parts) => parts.isNotEmpty).toList();

          await file.delete();
          return parsed as T;
        } catch (e) {
          await file.delete();
          throw FormatException('Error al leer o parsear el archivo: $e');
        }
      }

      return null;
    } else {
      throw HttpException('No se pudo descargar el archivo. Código: ${response.statusCode}');
    }
  }

  /// Descarga el archivo, lo parsea por líneas y convierte cada fila en un modelo personalizado `T`.
  ///
  /// Requiere que pases una función `fromRow`, que reciba una lista de `String` y devuelva una instancia de tu modelo.
  ///
  /// ⚠️ **IMPORTANTE:** Asegúrate de que:
  /// - Cada línea del archivo tenga exactamente los campos esperados separados por `|`.
  /// - Dentro de cada campo, si hay comas, ese campo será convertido automáticamente en una `List<String>`.
  /// - Tu modelo tenga un `factory constructor` o función similar que interprete correctamente esa estructura.
  ///
  /// ### Ejemplo de uso:
  /// Supongamos que cada línea del archivo tiene esta estructura:
  /// `imagen | título | enlace de video | etiquetas separadas por coma`
  ///
  /// Entonces tu modelo debería verse así:
  /// ```dart
  /// class Obra {
  ///   final String image;
  ///   final String title;
  ///   final String videoUrl;
  ///   final List<String> tags;
  ///
  ///   Obra({
  ///     required this.image,
  ///     required this.title,
  ///     required this.videoUrl,
  ///     required this.tags,
  ///   });
  ///
  ///   factory Obra.fromRow(List<String> row) {
  ///     return Obra(
  ///       image: row[0],
  ///       title: row[1],
  ///       videoUrl: row[2],
  ///       tags: List<String>.from(row[3]),
  ///     );
  ///   }
  /// }
  ///
  /// // Luego en tu código:
  /// final repplink = Repplink('https://drive.google.com/file/d/ID/view');
  /// final obras = await repplink.startWithModel<Obra>(Obra.fromRow);
  /// ```
  Future<List<T>> startWithModel<T>(T Function(List<dynamic> row) fromRow) async {
    final data = await start<List<List<dynamic>>>();
    if (data == null) return [];

    return data.map(fromRow).toList();
  }
}
