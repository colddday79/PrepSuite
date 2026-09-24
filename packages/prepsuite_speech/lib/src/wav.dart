/// Minimal WAV reading/writing (pure Dart + dart:io).
library;

import 'dart:io';
import 'dart:typed_data';

/// Decoded mono audio.
class WavAudio {
  final Float32List samples;
  final int sampleRate;
  const WavAudio(this.samples, this.sampleRate);
}

/// Reads a PCM16/PCM24/PCM32/float32 WAV and down-mixes to mono float.
WavAudio readWav(String path) => parseWav(File(path).readAsBytesSync());

WavAudio parseWav(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('not a RIFF/WAVE file');
  }
  int? format, channels, sampleRate, bits;
  var dataOffset = -1, dataLen = 0;
  var o = 12;
  while (o + 8 <= bytes.length) {
    final id = tag(o);
    final len = bd.getUint32(o + 4, Endian.little);
    final body = o + 8;
    if (id == 'fmt ') {
      format = bd.getUint16(body, Endian.little);
      channels = bd.getUint16(body + 2, Endian.little);
      sampleRate = bd.getUint32(body + 4, Endian.little);
      bits = bd.getUint16(body + 14, Endian.little);
      if (format == 0xFFFE && len >= 26) format = bd.getUint16(body + 24, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      // Streams that were never finalised carry 0 or 0xFFFFFFFF here.
      final avail = bytes.length - body;
      dataLen = (len == 0 || len > avail) ? avail : len;
      break;
    }
    o = body + len + (len.isOdd ? 1 : 0);
  }
  if (format == null || dataOffset < 0 || channels == null || channels < 1) {
    throw const FormatException('missing fmt or data chunk');
  }
  final bytesPer = bits! ~/ 8;
  final frameBytes = bytesPer * channels;
  final n = dataLen ~/ frameBytes;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    var acc = 0.0;
    for (var c = 0; c < channels; c++) {
      final p = dataOffset + i * frameBytes + c * bytesPer;
      double v;
      if (format == 3 && bits == 32) {
        v = bd.getFloat32(p, Endian.little);
      } else if (format == 1 && bits == 16) {
        v = bd.getInt16(p, Endian.little) / 32768.0;
      } else if (format == 1 && bits == 24) {
        var x = bytes[p] | (bytes[p + 1] << 8) | (bytes[p + 2] << 16);
        if (x & 0x800000 != 0) x -= 0x1000000;
        v = x / 8388608.0;
      } else if (format == 1 && bits == 32) {
        v = bd.getInt32(p, Endian.little) / 2147483648.0;
      } else if (format == 1 && bits == 8) {
        v = (bytes[p] - 128) / 128.0;
      } else {
        throw FormatException('unsupported WAV format $format/$bits-bit');
      }
      acc += v;
    }
    out[i] = acc / channels;
  }
  return WavAudio(out, sampleRate!);
}

/// 44-byte PCM16 mono header for [dataBytes] of audio.
Uint8List wavHeader(int sampleRate, int dataBytes, {int channels = 1}) {
  final h = ByteData(44);
  void s(int o, String t) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  s(0, 'RIFF');
  h.setUint32(4, 36 + dataBytes, Endian.little);
  s(8, 'WAVE');
  s(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, channels, Endian.little);
  h.setUint32(24, sampleRate, Endian.little);
  h.setUint32(28, sampleRate * channels * 2, Endian.little);
  h.setUint16(32, channels * 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  s(36, 'data');
  h.setUint32(40, dataBytes, Endian.little);
  return h.buffer.asUint8List();
}

/// Float samples (-1..1) to PCM16 little-endian bytes.
Uint8List floatToPcm16(Float32List samples) {
  final out = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    var v = samples[i];
    if (v > 1) v = 1;
    if (v < -1) v = -1;
    out.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  return out.buffer.asUint8List();
}

/// PCM16 little-endian bytes to float samples.
Float32List pcm16ToFloat(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final n = bytes.length ~/ 2;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Writes a complete PCM16 mono WAV file.
void writeWavFile(String path, Float32List samples, int sampleRate) {
  final pcm = floatToPcm16(samples);
  final f = File(path).openSync(mode: FileMode.write);
  try {
    f.writeFromSync(wavHeader(sampleRate, pcm.length));
    f.writeFromSync(pcm);
  } finally {
    f.closeSync();
  }
}

/// Appends PCM16 audio to a WAV file as it arrives; [close] fixes the header.
class StreamingWavWriter {
  final RandomAccessFile _f;
  final int sampleRate;
  int _dataBytes = 0;

  StreamingWavWriter(String path, this.sampleRate)
      : _f = File(path).openSync(mode: FileMode.write) {
    _f.writeFromSync(wavHeader(sampleRate, 0));
  }

  int get dataBytes => _dataBytes;

  void add(Uint8List pcm16) {
    _f.writeFromSync(pcm16);
    _dataBytes += pcm16.length;
  }

  void close() {
    _f.setPositionSync(0);
    _f.writeFromSync(wavHeader(sampleRate, _dataBytes));
    _f.closeSync();
  }
}
