import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Where the model files live on the device once [SpeechModels.ensureReady]
/// has finished.
class SpeechModelPaths {
  final String root;
  const SpeechModelPaths(this.root);

  String get asrEncoder => '$root/asr/encoder.onnx';
  String get asrDecoder => '$root/asr/decoder.onnx';
  String get asrJoiner => '$root/asr/joiner.onnx';
  String get asrTokens => '$root/asr/tokens.txt';
  String get ttsModel => '$root/tts/en_US-norman-medium.onnx';
  String get ttsTokens => '$root/tts/tokens.txt';
  String get espeakData => '$root/tts/espeak-ng-data';

  Map<String, String> toMap() => {
        'asrEncoder': asrEncoder,
        'asrDecoder': asrDecoder,
        'asrJoiner': asrJoiner,
        'asrTokens': asrTokens,
        'ttsModel': ttsModel,
        'ttsTokens': ttsTokens,
        'espeakData': espeakData,
      };
}

/// Thrown when the model assets are not bundled in the app.
class SpeechModelsMissing implements Exception {
  final String message;
  const SpeechModelsMissing(this.message);
  @override
  String toString() => 'SpeechModelsMissing: $message';
}

/// Makes the bundled models usable by the native engine, which needs real
/// files. On Android (and as a fallback on iOS) the assets are copied once to
/// app support storage; on iOS the files inside the app bundle are used
/// directly when present. A manifest (file list + sizes + version) decides
/// whether a copy is needed, so app updates with new models re-copy.
class SpeechModels {
  SpeechModels._();

  /// Asset key prefix (files live in this package under assets/models/, which
  /// its pubspec declares, so apps bundle them automatically).
  static const String assetRoot = 'packages/prepsuite_speech/assets/models';

  static SpeechModelPaths? _paths;
  static Future<SpeechModelPaths>? _pending;
  static final StreamController<double> _progress = StreamController<double>.broadcast();

  /// Paths once ready, otherwise null.
  static SpeechModelPaths? get paths => _paths;

  /// Copy progress 0..1 for whoever is waiting.
  static Stream<double> get progress => _progress.stream;

  /// Returns model paths, copying bundled assets on first run.
  /// [onProgress] receives 0..1 by bytes copied. Throws [SpeechModelsMissing]
  /// if the app does not bundle the assets.
  static Future<SpeechModelPaths> ensureReady({
    void Function(double progress)? onProgress,
    AssetBundle? bundle,
  }) async {
    final ready = _paths;
    if (ready != null) {
      onProgress?.call(1);
      return ready;
    }
    final sub = onProgress == null ? null : _progress.stream.listen(onProgress);
    try {
      final paths = await (_pending ??= _prepare(bundle ?? rootBundle));
      onProgress?.call(1);
      return paths;
    } finally {
      await sub?.cancel();
      _pending = null;
    }
  }

  static Future<SpeechModelPaths> _prepare(AssetBundle bundle) async {
    final String manifestText;
    try {
      manifestText = await bundle.loadString('$assetRoot/manifest.json', cache: false);
    } catch (_) {
      throw const SpeechModelsMissing(
        'Model assets not found in this build. Run tools/voice/fetch_models.sh, '
        'then rebuild the app.',
      );
    }
    final manifest = jsonDecode(manifestText) as Map<String, dynamic>;
    final files = [
      for (final f in manifest['files'] as List) (f['path'] as String, f['bytes'] as int),
    ];

    bool complete(String root) => files.every((f) {
          final file = File('$root/${f.$1}');
          return file.existsSync() && file.lengthSync() == f.$2;
        });

    // iOS: Flutter assets are plain files inside the app bundle.
    if (Platform.isIOS) {
      final bundled =
          '${File(Platform.resolvedExecutable).parent.path}/Frameworks/App.framework/flutter_assets/$assetRoot';
      if (complete(bundled)) return _paths = SpeechModelPaths(bundled);
    }

    final support = await getApplicationSupportDirectory();
    final root = '${support.path}/prepsuite_speech/models';
    final installed = File('$root/manifest.json');
    if (installed.existsSync() && installed.readAsStringSync() == manifestText && complete(root)) {
      _progress.add(1);
      return _paths = SpeechModelPaths(root);
    }

    // (Re)copy everything; the manifest is written last as the "done" marker.
    if (installed.existsSync()) installed.deleteSync();
    final total = files.fold<int>(0, (a, f) => a + f.$2);
    var copied = 0;
    _progress.add(0);
    for (final (rel, bytes) in files) {
      final dest = File('$root/$rel');
      if (!(dest.existsSync() && dest.lengthSync() == bytes)) {
        await dest.parent.create(recursive: true);
        final data = await bundle.load('$assetRoot/$rel');
        final tmp = File('${dest.path}.part');
        await tmp.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        await tmp.rename(dest.path);
      }
      copied += bytes;
      _progress.add(total == 0 ? 1 : copied / total);
    }
    await installed.writeAsString(manifestText, flush: true);
    return _paths = SpeechModelPaths(root);
  }
}
