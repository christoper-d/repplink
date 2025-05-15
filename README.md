# 📦 Repplink

**Repplink** es un paquete ligero para Dart y Flutter que permite **descargar y procesar archivos de texto almacenados en Google Drive** usando un enlace público. Es ideal para cargar catálogos, configuraciones, listas de contenido o cualquier archivo estructurado en texto plano, sin necesidad de un backend propio.

---

## ✨ Características

- 🔗 Valida y transforma enlaces públicos de Google Drive a enlaces directos de descarga.
- 📥 Descarga archivos temporalmente en el dispositivo.
- 📄 Lee archivos de texto por líneas y separadores personalizados (`|` y `,`).
- 🧠 Convierte el contenido en listas de datos (`List<List<dynamic>>`).
- 🧩 Transforma cada fila en modelos personalizados con una función `fromRow`.

---

## 🚀 Empezando

Agrega a tu `pubspec.yaml`:

```yaml
dependencies:
  repplink:
    git:
      url: https://github.com/christoper-d/repplink.git
```
(O usa la URL de tu paquete en pub.dev si lo publicas.)

## 🧪 Ejemplo de uso

Supón que tienes este archivo en Drive:

img1.jpg,img2.jpg | Obra 1 | https://www.dropbox.com/video1 | etiqueta1,etiqueta2
img3.jpg          | Obra 2 | https://www.dropbox.com/video2 | etiqueta3

Paso 1: Define tu modelo

```dart
class Obra {
  final List<String> images;
  final String title;
  final String videoUrl;
  final List<String> tags;

  Obra({
    required this.images,
    required this.title,
    required this.videoUrl,
    required this.tags,
  });

  factory Obra.fromRow(List<dynamic> row) {
    return Obra(
      images: List<String>.from(row[0]),
      title: row[1],
      videoUrl: row[2],
      tags: List<String>.from(row[3]),
    );
  }
}
```

Paso 2: Usa Repplink

```dart
final repplink = Repplink('https://drive.google.com/file/d/TU_ID/view');
final obras = await repplink.startWithModel<Obra>(Obra.fromRow);
```

## 📚 API

> Repplink(String rawLink)

Crea una instancia validando el enlace de Google Drive.

> Future<bool> isAccessible()

Verifica si el archivo puede descargarse (retorna true si es accesible).

> Future<T?> start<T>()

Descarga y devuelve el contenido. Si T es List<List<dynamic>>, el contenido se parsea por líneas y separadores.

> Future<List<T>> startWithModel<T>(T Function(List<dynamic>) fromRow)

Transforma cada fila en un modelo personalizado.

## 📂 Estructura esperada del archivo

Campos separados por |.

Campos con múltiples valores separados por ,.

Ejemplo:

```text
img1,img2 | Título | https://video | etiqueta1,etiqueta2
```

##  📬 Información adicional

📢 Contribuciones bienvenidas.

🐞 Reporta errores vía GitHub Issues.

🧠 Este paquete no requiere autenticación de Google Drive, funciona solo con enlaces públicos.
