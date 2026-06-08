import 'dart:convert';
import 'dart:typed_data';

/// One image attached to an AI plan request.
///
/// `bytes` is the raw PNG/JPEG. `mimeType` must match what the provider's
/// vision API expects (e.g. `image/png`, `image/jpeg`, `image/webp`).
/// `label` is a short human-readable source tag — filename for local
/// uploads, `figma:<nodeId>` for Figma renders — used both in the
/// proposed-plan printout and as the saved filename inside `<project>/design/`.
class DesignAsset {
  final Uint8List bytes;
  final String mimeType;
  final String label;

  DesignAsset({
    required this.bytes,
    required this.mimeType,
    required this.label,
  });

  /// Base64 payload sans data-url prefix. Providers wrap this in their
  /// own envelope (Claude `image` block, Gemini `inlineData`, OpenAI
  /// `image_url` with `data:` URI).
  String get base64Data => base64Encode(bytes);

  /// Sensible filename for saving into `<project>/design/`. Strips path
  /// separators so `figma:1:23` becomes `figma_1_23.png`.
  String get savedFilename {
    final safe = label.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    if (safe.contains('.')) return safe;
    final ext = switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      _ => 'png',
    };
    return '$safe.$ext';
  }
}
