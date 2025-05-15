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
  /// Puedes especificar el tipo de retorno con el parámetro genérico `T`:
  ///
  /// - Si no se especifica `T`, el archivo solo se descarga a una carpeta temporal y no se devuelve nada.
  /// - Si `T == List<List<dynamic>>`, el archivo se lee como texto, se divide por líneas y por `|`,
  ///   y cada campo se convierte en `String` o `List<String>` (si contiene comas).
  /// - Si `T == List<Map<String, dynamic>>` y `useHeader` es `true`, se considera que la primera línea
  ///   es un encabezado, y cada línea siguiente se convierte en un `Map` con claves tomadas del encabezado.
  ///
  /// En todos los casos, el archivo temporal se elimina automáticamente después de su uso.
  ///
  /// ### Formato esperado:
  /// Cada línea del archivo debe tener campos separados por `|`. Si un campo contiene múltiples valores separados por coma,
  /// ese campo se convertirá automáticamente en una `List<String>`.
  ///
  /// ---
  /// ### Ejemplo sin encabezado:
  /// ```dart
  /// final data = await repplink.start<List<List<dynamic>>>();
  /// ```
  ///
  /// Esto produce:
  /// ```dart
  /// [
  ///   ['img1.png', 'Título 1', 'video1.mp4', ['tag1', 'tag2']],
  ///   ['img2.png', 'Título 2', 'video2.mp4', ['tag3']]
  /// ]
  /// ```
  ///
  /// ---
  /// ### Ejemplo con encabezado:
  /// ```dart
  /// final data = await repplink.start<List<Map<String, dynamic>>>(useHeader: true);
  /// ```
  ///
  /// Esto produce:
  /// ```dart
  /// [
  ///   {
  ///     'imagen': 'img1.png',
  ///     'título': 'Título 1',
  ///     'video': 'video1.mp4',
  ///     'etiquetas': ['tag1', 'tag2']
  ///   },
  ///   ...
  /// ]
  /// ```
  Future<T?> start<T>({bool useHeader = false}) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$fileId.tmp';
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }

    final response = await http.get(Uri.parse(directDownloadLink));

    if (response.statusCode == 200) {
      await file.writeAsBytes(response.bodyBytes);

      try {
        final content = await file.readAsString();
        final lines = content
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();

        if (lines.isEmpty) {
          await file.delete();
          return [] as T;
        }

        // Si se quiere usar encabezado y se espera Map<String, dynamic>
        if (useHeader && T == List<Map<String, dynamic>>) {
          final headerParts = lines.first.split('|').map((e) => e.trim()).toList();
          final dataLines = lines.skip(1);

          final parsed = dataLines.map((line) {
            final values = line
                .split('|')
                .map((p) => p.trim())
                .map((p) {
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

            final map = <String, dynamic>{};
            for (var i = 0; i < headerParts.length && i < values.length; i++) {
              map[headerParts[i]] = values[i];
            }

            return map;
          }).toList();

          await file.delete();
          return parsed as T;
        }

        // Si no se usa encabezado, devolver como lista de listas
        if (T == List<List<dynamic>>) {
          final parsed = lines.map((line) {
            final parts = line
                .split('|')
                .map((p) => p.trim())
                .where((p) => p.isNotEmpty)
                .map((p) {
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
        }

        await file.delete();
        return null;
      } catch (e) {
        await file.delete();
        throw FormatException('Error al leer o parsear el archivo: $e');
      }
    } else {
      throw HttpException('No se pudo descargar el archivo. Código: ${response.statusCode}');
    }
  }


  /// Descarga el archivo, lo parsea por líneas y convierte cada fila en un modelo personalizado `T`.
  ///
  /// Requiere que pases una función `fromRow`, que reciba una fila como `List<dynamic>` (sin encabezado)
  /// o como `Map<String, dynamic>` (si usas encabezado).
  ///
  /// Usa el parámetro [useHeader] para indicar si el archivo contiene una línea de encabezado.
  /// Si [useHeader] es `true`, la primera línea se usará como claves del mapa para cada fila.
  ///
  /// ⚠️ **IMPORTANTE:** Asegúrate de que:
  /// - Cada línea del archivo tenga los campos esperados, separados por `|`.
  /// - Los valores separados por comas dentro de un campo serán convertidos automáticamente en `List<String>`.
  /// - Tu modelo tenga un `factory constructor` o función que interprete correctamente
  ///   una fila como `List<dynamic>` o `Map<String, dynamic>`, según corresponda.
  ///
  /// ---
  /// ### Ejemplo de uso SIN encabezado (`List<dynamic>`):
  ///
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
  ///   factory Obra.fromRow(List<dynamic> row) {
  ///     return Obra(
  ///       image: row[0],
  ///       title: row[1],
  ///       videoUrl: row[2],
  ///       tags: List<String>.from(row[3]),
  ///     );
  ///   }
  /// }
  ///
  /// final repplink = Repplink('https://drive.google.com/file/d/ID/view');
  /// final obras = await repplink.startWithModel<Obra>(Obra.fromRow);
  /// ```
  ///
  /// ---
  /// ### Ejemplo de uso CON encabezado (`Map<String, dynamic>`):
  ///
  /// Si el archivo tiene encabezado:
  /// `imagen | título | video | etiquetas`
  ///
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
  ///   factory Obra.fromMap(Map<String, dynamic> map) {
  ///     return Obra(
  ///       image: map['imagen'],
  ///       title: map['título'],
  ///       videoUrl: map['video'],
  ///       tags: List<String>.from(map['etiquetas']),
  ///     );
  ///   }
  /// }
  ///
  /// final obras = await repplink.startWithModel<Obra>(
  ///   Obra.fromMap,
  ///   useHeader: true,
  /// );
  /// ```
  Future<List<T>> startWithModel<T>(
      T Function(dynamic row) fromRow, {
        bool useHeader = false,
      }) async {
    // Detecta el tipo esperado por fromRow: Map<String, dynamic> o List<dynamic>
    final data = await start(useHeader: useHeader);

    if (data == null) return [];

    if (data is List) {
      return data.map<T>((row) => fromRow(row)).toList();
    }

    throw FormatException('Formato de datos no compatible con el modelo.');
  }

}


// Future<T?> start<T>() async {
//   final dir = await getTemporaryDirectory();
//   final filePath = '${dir.path}/$fileId.tmp';
//   final file = File(filePath);
//
//   if (await file.exists()) {
//     await file.delete();
//   }
//
//   final response = await http.get(Uri.parse(directDownloadLink));
//
//   if (response.statusCode == 200) {
//     await file.writeAsBytes(response.bodyBytes);
//
//     if (T == List<List<dynamic>>) {
//       try {
//         final content = await file.readAsString();
//         final lines = content
//             .split('\n')
//             .map((line) => line.trim())
//             .where((line) => line.isNotEmpty)
//             .toList();
//
//         // final parsed = lines.map((line) {
//         //   final parts = line.split('|').where((p) => p.trim().isNotEmpty).toList();
//         //   return parts;
//         // }).where((parts) => parts.isNotEmpty).toList();
//
//         final parsed = lines.map((line) {
//           final parts = line
//               .split('|')
//               .map((p) => p.trim())
//               .where((p) => p.isNotEmpty)
//               .map((p) {
//             // Si el campo contiene comas, lo convertimos en lista
//             if (p.contains(',')) {
//               return p
//                   .split(',')
//                   .map((e) => e.trim())
//                   .where((e) => e.isNotEmpty)
//                   .toList();
//             } else {
//               return p;
//             }
//           })
//               .toList();
//
//           return parts;
//         }).where((parts) => parts.isNotEmpty).toList();
//
//         await file.delete();
//         return parsed as T;
//       } catch (e) {
//         await file.delete();
//         throw FormatException('Error al leer o parsear el archivo: $e');
//       }
//     }
//
//     return null;
//   } else {
//     throw HttpException('No se pudo descargar el archivo. Código: ${response.statusCode}');
//   }
// }


// Future<List<T>> startWithModel<T>(T Function(List<dynamic> row) fromRow) async {
//   final data = await start<List<List<dynamic>>>();
//   if (data == null) return [];
//
//   return data.map(fromRow).toList();
// }