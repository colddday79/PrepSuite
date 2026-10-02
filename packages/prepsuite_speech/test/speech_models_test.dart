import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite_speech/prepsuite_speech.dart';

class _ModelBundle extends CachingAssetBundle {
  _ModelBundle(this.assets);

  final Map<String, List<int>> assets;
  final List<String> loaded = [];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final bytes = assets[key];
    if (bytes == null) throw StateError('Missing test asset: $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('model setup retries missing assets, repairs partial copies and shares preparation', () async {
    final support = await Directory.systemTemp.createTemp(
      'prepsuite_models_test_',
    );
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'getApplicationSupportDirectory') return support.path;
      return null;
    });
    addTearDown(() async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      await support.delete(recursive: true);
    });

    await expectLater(
      SpeechModels.ensureReady(bundle: _ModelBundle({})),
      throwsA(isA<SpeechModelsMissing>()),
    );

    const encoder = [1, 2, 3];
    const tokens = [4, 5];
    final manifest = jsonEncode({
      'version': 'test',
      'files': [
        {'path': 'asr/encoder.onnx', 'bytes': encoder.length},
        {'path': 'asr/tokens.txt', 'bytes': tokens.length},
      ],
    });
    final root = '${support.path}/prepsuite_speech/models';
    await Directory('$root/asr').create(recursive: true);
    await File('$root/asr/encoder.onnx').writeAsBytes(encoder);
    await File('$root/asr/tokens.txt').writeAsBytes([0]);
    // A prior interrupted installation left its marker but a truncated file.
    await File('$root/manifest.json').writeAsString(manifest);
    final bundle = _ModelBundle({
      '${SpeechModels.assetRoot}/manifest.json': utf8.encode(manifest),
      '${SpeechModels.assetRoot}/asr/encoder.onnx': encoder,
      '${SpeechModels.assetRoot}/asr/tokens.txt': tokens,
    });
    final progress = <double>[];
    final paths = await Future.wait([
      SpeechModels.ensureReady(bundle: bundle, onProgress: progress.add),
      SpeechModels.ensureReady(bundle: bundle),
    ]);

    expect(identical(paths.first, paths.last), isTrue);
    expect(await File(paths.first.asrTokens).readAsBytes(), tokens);
    expect(await File(paths.first.asrEncoder).readAsBytes(), encoder);
    expect(await File('$root/manifest.json').readAsString(), manifest);
    expect(bundle.loaded.where((key) => key.endsWith('encoder.onnx')), isEmpty);
    expect(
      bundle.loaded.where((key) => key.endsWith('tokens.txt')),
      hasLength(1),
    );
    expect(progress.last, 1);
    expect(await File('$root/asr/tokens.txt.part').exists(), isFalse);
    // Reusing a loaded model needs neither disk copies nor bundle reads.
    expect(
      await SpeechModels.ensureReady(bundle: _ModelBundle({})),
      same(paths.first),
    );
  });
}
