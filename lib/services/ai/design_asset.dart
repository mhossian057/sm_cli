import 'dart:convert';
import 'dart:typed_data';

/// One image attached to an AI plan request.
///
/// `bytes` is the raw PNG/JPEG. `mimeType` must match what the provider's
/// vision API expects (e.g. `image/png`, `image/jpeg`, `image/webp`).
/// `label` is a short human-readable source tag — filename for local
/// uploads, `figma_<nodeId>` for Figma renders — used in the proposed-plan
/// printout. `displayName`, when set, becomes the basis for [savedFilename]
/// so Figma frames land on disk as `login_screen.png` instead of
/// `figma_1_23.png`.
class DesignAsset {
  final Uint8List bytes;
  final String mimeType;
  final String label;
  final String? displayName;

  DesignAsset({
    required this.bytes,
    required this.mimeType,
    required this.label,
    this.displayName,
  });

  /// Base64 payload sans data-url prefix. Providers wrap this in their
  /// own envelope (Claude `image` block, Gemini `inlineData`, OpenAI
  /// `image_url` with `data:` URI).
  String get base64Data => base64Encode(bytes);

  /// Sensible filename for saving into `<project>/design/`. Prefers
  /// `displayName` sanitized to snake_case; falls back to [label] with
  /// path separators stripped.
  String get savedFilename {
    final base = displayName ?? label;
    final hasExt = RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false)
        .hasMatch(base);
    final stem = hasExt
        ? base.replaceAll(RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false), '')
        : base;
    var safe = stem
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (safe.isEmpty) safe = 'design';
    final ext = hasExt
        ? RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false)
            .firstMatch(base)!
            .group(0)!
            .toLowerCase()
            .substring(1)
        : switch (mimeType) {
            'image/jpeg' => 'jpg',
            'image/webp' => 'webp',
            _ => 'png',
          };
    return '$safe.$ext';
  }
}
