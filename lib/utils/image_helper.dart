import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

class ImageHelper {
  static final ImagePicker _picker = ImagePicker();

  /// Picks an image from the gallery or camera.
  static Future<Uint8List?> pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(
      source: source,
      maxWidth: 1024, // Initial downscale to prevent OOM
      maxHeight: 1024,
    );

    if (image != null) {
      return await image.readAsBytes();
    }
    return null;
  }

  /// Compresses image data to be under [targetSizeKb].
  /// Returns the compressed bytes.
  static Future<Uint8List?> compressImage(Uint8List bytes, {int targetSizeKb = 100}) async {
    // Decode the image
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return null;

    // Resize if it's too large (e.g., max 500px for profile photo)
    if (image.width > 500 || image.height > 500) {
      image = img.copyResize(image, width: 500, height: 500, interpolation: img.Interpolation.average);
    }

    int quality = 90;
    Uint8List compressedBytes;
    
    // Compression loop
    do {
      compressedBytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      if (compressedBytes.lengthInBytes <= targetSizeKb * 1024) {
        break;
      }
      quality -= 10;
    } while (quality > 10);

    debugPrint('Final compressed size: ${compressedBytes.lengthInBytes / 1024} KB (Quality: $quality)');
    return compressedBytes;
  }
}
