import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prepsuite_speech/delivery_analyzer.dart';
import 'package:prepsuite_speech/src/wav.dart';

void main() {
  group('countFillers', () {
    test('hesitations and discourse markers', () {
      expect(
        countFillers('So, um, I was like, you know, basically running the place. Uh, I mean, '
            'we\'d like to help, and I actually did.'),
        {'um': 1, 'like': 1, 'you know': 1, 'basically': 1, 'uh': 1, 'i mean': 1, 'actually': 1},
      );
    });

    test('literal uses are not counted', () {
      expect(
        countFillers('I like coffee. It looks like rain. What kind of job is it? '
            'Do you know the menu? I mean it. That sort of thing works.'),
        isEmpty,
      );
    });

    test('variants map to canonical keys', () {
      expect(countFillers('Umm, uhh, erm, hmm, ah'), {'um': 2, 'uh': 2, 'er': 1});
    });

    test('kind of / sort of as hedges', () {
      expect(countFillers('It was kind of hard and sort of slow.'), {'kind of': 1, 'sort of': 1});
    });

    test('works on all-caps recogniser output after normalising', () {
      expect(countFillers(normalizeTranscriptText('SO UM I BASICALLY AH SET IT UP')),
          {'um': 1, 'basically': 1, 'uh': 1});
    });
  });

  group('tokensToWords', () {
    test('merges BPE pieces, drops punctuation, removes the lead offset', () {
      final w = tokensToWords(
        [' I', "'", 'm', ' app', 'ly', 'ing', ',', ' um', ',', ' b', 'ar', 'ista', '.'],
        [0.50, 0.62, 0.66, 0.78, 0.94, 1.06, 1.20, 1.40, 1.60, 2.00, 2.08, 2.20, 2.60],
        offsetMs: 300,
      );
      expect(w.map((e) => e.text), ["I'm", 'applying', 'um', 'barista']);
      expect(w.map((e) => e.startMs), [200, 480, 1100, 1700]);
      for (var i = 0; i < w.length; i++) {
        expect(w[i].endMs, greaterThan(w[i].startMs));
        if (i + 1 < w.length) expect(w[i].endMs, lessThanOrEqualTo(w[i + 1].startMs));
      }
    });

    test('a bare space token starts a new word (Kroko "Saturday night")', () {
      final w = tokensToWords(
        [' S', 'at', 'ur', 'd', 'a', 'y', ' ', 'n', 'ight'],
        [5.36, 5.40, 5.52, 5.56, 5.64, 5.68, 5.80, 5.84, 5.88],
        offsetMs: 300,
      );
      expect(w.map((e) => e.text), ['Saturday', 'night']);
      expect(w[1].startMs, 5540);
    });

    test('normalises all-caps text', () {
      expect(normalizeTranscriptText("I'M APPLYING  FOR A JOB "), "I'm applying for a job");
      expect(normalizeTranscriptText('Already Mixed case.'), 'Already Mixed case.');
    });
  });

  group('wav', () {
    test('streaming writer patches the header; reader round-trips', () {
      final dir = Directory.systemTemp.createTempSync('psx_wav');
      final path = '${dir.path}/a.wav';
      final w = StreamingWavWriter(path, 16000);
      final src = Float32List.fromList([for (var i = 0; i < 1600; i++) (i % 50) / 50.0 - 0.5]);
      final pcm = floatToPcm16(src);
      w.add(Uint8List.sublistView(pcm, 0, 1000));
      w.add(Uint8List.sublistView(pcm, 1000));
      w.close();
      final bytes = File(path).readAsBytesSync();
      expect(bytes.length, 44 + 3200);
      final a = readWav(path);
      expect(a.sampleRate, 16000);
      expect(a.samples.length, 1600);
      for (var i = 0; i < src.length; i++) {
        expect(a.samples[i], closeTo(src[i], 1 / 16000));
      }
      dir.deleteSync(recursive: true);
    });
  });
}
