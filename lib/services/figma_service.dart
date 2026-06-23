import 'dart:convert';
import 'package:http/http.dart' as http;

import 'ai/design_asset.dart';

/// One Figma node we plan to render: API id + human-readable frame name.
class _FigmaNode {
  final String id;
  final String name;
  _FigmaNode(this.id, this.name);
}

/// Renders frames from a Figma file as PNG `DesignAsset`s.
///
/// Two-step flow:
///   1. If no node IDs are supplied, GET `/v1/files/<key>` and pick the
///      top-level frames from the first page (with their names).
///   2. POST those node IDs to `/v1/images/<key>?ids=...&format=png` →
///      Figma returns S3 URLs we then download.
///
/// When the caller supplies explicit `nodeIds`, names are resolved via
/// `/v1/files/<key>/nodes?ids=...` so the manifest stays human-readable.
///
/// Auth is a Figma Personal Access Token (free on every Figma plan,
/// generated from Account Settings → Personal access tokens) passed in
/// the `X-Figma-Token` header.
class FigmaService {
  static const _base = 'https://api.figma.com/v1';

  /// Frames per `/v1/images` call. Figma's renderer times out around 10
  /// large frames in one request, so we chunk conservatively.
  static const _batchSize = 5;

  /// Resolves [nodeIds] (or auto-discovers screen-like frames when empty)
  /// and downloads each as a PNG. Renders are batched to avoid Figma's
  /// "Render timeout" 400 on files with many or large frames.
  static Future<List<DesignAsset>> renderFrames({
    required String fileKey,
    required String token,
    List<String> nodeIds = const [],
    int scale = 1,
  }) async {
    // Users often paste node IDs straight from Figma URLs (`1-23`), but
    // the API wants colons (`1:23`). Normalize so either form works.
    final nodes = nodeIds.isNotEmpty
        ? await _resolveNamesForIds(
            fileKey: fileKey,
            token: token,
            ids: nodeIds.map((n) => n.replaceAll('-', ':')).toList(),
          )
        : await _discoverTopLevelFrames(fileKey: fileKey, token: token);
    if (nodes.isEmpty) {
      throw Exception(
        'No renderable frames found in Figma file $fileKey.\n'
        'To target a specific node:\n'
        '  1. Open the file in Figma and click the frame you want.\n'
        '  2. Look at the URL — it includes `?node-id=1-23` (the ID).\n'
        '  3. Re-run with --figma-node 1:23 '
        '(Figma URLs use a dash, the API uses a colon).',
      );
    }

    // Dedupe sanitized names so two frames called "Login" don't collide
    // on disk. Build once here so every batch sees a consistent map.
    final nameById = _uniqueNames(nodes);

    final assets = <DesignAsset>[];
    final totalBatches = (nodes.length + _batchSize - 1) ~/ _batchSize;
    for (var i = 0; i < nodes.length; i += _batchSize) {
      final batch =
          nodes.sublist(i, (i + _batchSize).clamp(0, nodes.length));
      final batchNum = (i ~/ _batchSize) + 1;
      if (totalBatches > 1) {
        print('   Rendering batch $batchNum/$totalBatches '
            '(${batch.length} frame(s) at scale ${scale}x)...');
      }
      assets.addAll(await _renderBatch(
        fileKey: fileKey,
        token: token,
        nodes: batch,
        nameById: nameById,
        scale: scale,
      ));
      // Small pause between batches keeps us under Figma's per-second
      // budget on multi-batch jobs. Skip on the last batch.
      if (i + _batchSize < nodes.length) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    return assets;
  }

  /// Backoff delays (seconds) when Figma returns 429. Three tries total —
  /// covers a transient rate-limit window without making the user wait
  /// forever if the limit is sustained.
  static const _backoffSeconds = [5, 15, 30];

  static Future<List<DesignAsset>> _renderBatch({
    required String fileKey,
    required String token,
    required List<_FigmaNode> nodes,
    required Map<String, String> nameById,
    required int scale,
  }) async {
    final ids = nodes.map((n) => n.id).toList();
    final uri = Uri.parse('$_base/images/$fileKey').replace(queryParameters: {
      'ids': ids.join(','),
      'format': 'png',
      'scale': '$scale',
    });

    http.Response res = await http.get(uri, headers: {'X-Figma-Token': token});
    for (var attempt = 0;
        res.statusCode == 429 && attempt < _backoffSeconds.length;
        attempt++) {
      final wait = _backoffSeconds[attempt];
      print('   ⏳ Figma rate limit hit, waiting ${wait}s '
          'before retry ${attempt + 1}/${_backoffSeconds.length}...');
      await Future<void>.delayed(Duration(seconds: wait));
      res = await http.get(uri, headers: {'X-Figma-Token': token});
    }

    if (res.statusCode != 200) {
      String hint;
      if (res.statusCode == 429) {
        // Figma exposes a Retry-After header (seconds). Short waits mean
        // a transient throttle; long waits mean you've hit the daily
        // image-render quota that resets in days, not minutes.
        final retryAfter = int.tryParse(res.headers['retry-after'] ?? '');
        final limitType = res.headers['x-figma-rate-limit-type'];
        if (retryAfter != null && retryAfter > 600) {
          final hours = (retryAfter / 3600).round();
          hint = '\n\nThis is a daily image-render quota lockout, NOT a '
              'transient throttle.\n'
              '  • Quota tier: ${limitType ?? "unknown"}\n'
              '  • Reset in: ~${hours}h\n'
              '\nWorkaround: export the frames manually from Figma '
              '(File → Export... → PNG) and use --design <folder> '
              'instead of --figma. Same result, no Figma API quota.';
        } else {
          hint = '\nFigma rate limit sustained. Wait a minute, then '
              'retry — or pass --figma-node <id> to render fewer frames.';
        }
      } else {
        hint = '\nTip: pass --figma-node <id> to render fewer frames.';
      }
      throw Exception(
        'Figma /images failed (${res.statusCode}): ${res.body}$hint',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final images = (body['images'] as Map?)?.cast<String, dynamic>() ?? {};

    final assets = <DesignAsset>[];
    for (final node in nodes) {
      final url = images[node.id] as String?;
      if (url == null) continue;
      final png = await http.get(Uri.parse(url));
      if (png.statusCode != 200) {
        throw Exception(
          'Figma PNG download for node ${node.id} failed (${png.statusCode})',
        );
      }
      assets.add(DesignAsset(
        bytes: png.bodyBytes,
        mimeType: 'image/png',
        label: 'figma_${node.id}',
        displayName: nameById[node.id] ?? node.name,
      ));
    }
    return assets;
  }

  /// Pulls the file structure and returns every direct child of the
  /// first canvas (page). Keeps the request light — we don't recurse.
  static Future<List<_FigmaNode>> _discoverTopLevelFrames({
    required String fileKey,
    required String token,
  }) async {
    // depth=3 covers: document → page → SECTION → frame. Without it
    // frames nested inside a section on the page are invisible.
    final res = await http.get(
      Uri.parse('$_base/files/$fileKey?depth=3'),
      headers: {'X-Figma-Token': token},
    );
    if (res.statusCode != 200) {
      throw Exception('Figma /files failed (${res.statusCode}): ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final document = body['document'] as Map<String, dynamic>?;
    final pages = (document?['children'] as List?) ?? const [];
    if (pages.isEmpty) return const [];

    // Walk EVERY page, descend into SECTION containers, collect screen-
    // like nodes. INSTANCE and COMPONENT_SET are excluded: instances are
    // duplicates of placed components, and a component set is a variant
    // collection rather than a screen.
    const renderable = {'FRAME', 'COMPONENT'};
    final nodes = <_FigmaNode>[];
    void walk(Map node) {
      final type = node['type'];
      if (renderable.contains(type)) {
        final id = node['id'] as String;
        final name = (node['name'] as String?)?.trim();
        nodes.add(_FigmaNode(id, name == null || name.isEmpty ? id : name));
        return; // don't descend into a frame's children
      }
      final kids = node['children'];
      if (kids is List) {
        for (final k in kids) {
          if (k is Map) walk(k);
        }
      }
    }
    for (final page in pages.whereType<Map>()) {
      final pageChildren = page['children'];
      if (pageChildren is List) {
        for (final c in pageChildren.whereType<Map>()) {
          walk(c);
        }
      }
    }
    return nodes;
  }

  /// Look up names for user-supplied node IDs via `/v1/files/<key>/nodes`.
  /// Falls back to the ID as the name when the lookup fails or returns
  /// nothing — rendering should never be blocked by a name fetch.
  static Future<List<_FigmaNode>> _resolveNamesForIds({
    required String fileKey,
    required String token,
    required List<String> ids,
  }) async {
    try {
      final uri = Uri.parse('$_base/files/$fileKey/nodes').replace(
        queryParameters: {'ids': ids.join(',')},
      );
      final res = await http.get(uri, headers: {'X-Figma-Token': token});
      if (res.statusCode != 200) {
        return [for (final id in ids) _FigmaNode(id, id)];
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final nodes = (body['nodes'] as Map?)?.cast<String, dynamic>() ?? {};
      return [
        for (final id in ids)
          _FigmaNode(
            id,
            ((nodes[id] as Map?)?['document'] as Map?)?['name'] as String? ??
                id,
          ),
      ];
    } catch (_) {
      return [for (final id in ids) _FigmaNode(id, id)];
    }
  }

  /// Sanitize frame names to snake_case filenames and dedupe collisions
  /// with `_2`, `_3`, ... suffixes. Returns id → unique stem.
  static Map<String, String> _uniqueNames(List<_FigmaNode> nodes) {
    final used = <String>{};
    final out = <String, String>{};
    for (final n in nodes) {
      var stem = n.name
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      if (stem.isEmpty) stem = 'frame_${n.id.replaceAll(':', '_')}';
      var unique = stem;
      var i = 2;
      while (used.contains(unique)) {
        unique = '${stem}_$i';
        i++;
      }
      used.add(unique);
      out[n.id] = unique;
    }
    return out;
  }
}
