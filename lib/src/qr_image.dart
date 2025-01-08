import 'package:meta/meta.dart';

import 'mask_pattern.dart' as qr_mask_pattern;
import 'qr_code.dart';
import 'util.dart' as qr_util;

/// Renders the encoded data from a [QrCode] in a portable format.
class QrImage {
  final int moduleCount;
  final int typeNumber;
  final int errorCorrectLevel;
  final int maskPattern;

  final _modules = <List<bool?>>[];

  /// Generates a QrImage with the best mask pattern encoding [qrCode].
  factory QrImage(QrCode qrCode) {
    var minLostPoint = double.infinity;
    QrImage? bestImage;

    for (var i = 0; i < 8; i++) {
      final testImage = QrImage._test(qrCode, i);
      final lostPoint = _lostPoint(testImage);

      if (i == 0 || minLostPoint > lostPoint) {
        minLostPoint = lostPoint;
        bestImage = testImage;
      }
    }

    return QrImage.withMaskPattern(qrCode, bestImage!.maskPattern);
  }

  /// Generates a specific image for the [qrCode] and [maskPattern].
  QrImage.withMaskPattern(QrCode qrCode, this.maskPattern)
      : assert(maskPattern >= 0 && maskPattern <= 7),
        moduleCount = qrCode.moduleCount,
        typeNumber = qrCode.typeNumber,
        errorCorrectLevel = qrCode.errorCorrectLevel {
    _makeImpl(maskPattern, qrCode.dataCache, false);
  }

  QrImage._test(QrCode qrCode, this.maskPattern)
      : moduleCount = qrCode.moduleCount,
        typeNumber = qrCode.typeNumber,
        errorCorrectLevel = qrCode.errorCorrectLevel {
    _makeImpl(maskPattern, qrCode.dataCache, true);
  }

  @visibleForTesting
  List<List<bool?>> get qrModules => _modules;

  void _resetModules() {
    _modules.clear();
    for (var row = 0; row < moduleCount; row++) {
      _modules.add(List<bool?>.filled(moduleCount, null));
    }
  }

  bool isDark(int row, int col) {
    if (row < 0 || moduleCount <= row || col < 0 || moduleCount <= col) {
      throw ArgumentError('$row , $col');
    }
    return _modules[row][col]!;
  }

  void _makeImpl(int maskPattern, List<int> dataCache, bool test) {
    _resetModules();
    _setupPositionProbePattern(0, 0);
    _setupPositionProbePattern(moduleCount - 7, 0);
    _setupPositionProbePattern(0, moduleCount - 7);
    _setupPositionAdjustPattern();
    _setupTimingPattern();
    _setupTypeInfo(maskPattern, test);

    if (typeNumber >= 7) {
      _setupTypeNumber(test);
    }

    _mapData(dataCache, maskPattern);
  }

  void _setupPositionProbePattern(int row, int col) {
    for (var r = -1; r <= 7; r++) {
      if (row + r <= -1 || moduleCount <= row + r) continue;

      for (var c = -1; c <= 7; c++) {
        if (col + c <= -1 || moduleCount <= col + c) continue;

        if ((0 <= r && r <= 6 && (c == 0 || c == 6)) ||
            (0 <= c && c <= 6 && (r == 0 || r == 6)) ||
            (2 <= r && r <= 4 && 2 <= c && c <= 4)) {
          _modules[row + r][col + c] = true;
        } else {
          _modules[row + r][col + c] = false;
        }
      }
    }
  }

  void _setupPositionAdjustPattern() {
    final pos = qr_util.patternPosition(typeNumber);

    for (var i = 0; i < pos.length; i++) {
      for (var j = 0; j < pos.length; j++) {
        final row = pos[i];
        final col = pos[j];

        if (_modules[row][col] != null) {
          continue;
        }

        for (var r = -2; r <= 2; r++) {
          for (var c = -2; c <= 2; c++) {
            if (r == -2 || r == 2 || c == -2 || c == 2 || (r == 0 && c == 0)) {
              _modules[row + r][col + c] = true;
            } else {
              _modules[row + r][col + c] = false;
            }
          }
        }
      }
    }
  }

  void _setupTimingPattern() {
    for (var r = 8; r < moduleCount - 8; r++) {
      if (_modules[r][6] != null) {
        continue;
      }
      _modules[r][6] = r.isEven;
    }

    for (var c = 8; c < moduleCount - 8; c++) {
      if (_modules[6][c] != null) {
        continue;
      }
      _modules[6][c] = c.isEven;
    }
  }

  void _setupTypeInfo(int maskPattern, bool test) {
    final data = (errorCorrectLevel << 3) | maskPattern;
    final bits = qr_util.bchTypeInfo(data);

    int i;
    bool mod;

    // vertical
    for (i = 0; i < 15; i++) {
      mod = !test && ((bits >> i) & 1) == 1;

      if (i < 6) {
        _modules[i][8] = mod;
      } else if (i < 8) {
        _modules[i + 1][8] = mod;
      } else {
        _modules[moduleCount - 15 + i][8] = mod;
      }
    }

    // horizontal
    for (i = 0; i < 15; i++) {
      mod = !test && ((bits >> i) & 1) == 1;

      if (i < 8) {
        _modules[8][moduleCount - i - 1] = mod;
      } else if (i < 9) {
        _modules[8][15 - i - 1 + 1] = mod;
      } else {
        _modules[8][15 - i - 1] = mod;
      }
    }

    // fixed module
    _modules[moduleCount - 8][8] = !test;
  }

  void _setupTypeNumber(bool test) {
    final bits = qr_util.bchTypeNumber(typeNumber);

    for (var i = 0; i < 18; i++) {
      final mod = !test && ((bits >> i) & 1) == 1;
      _modules[i ~/ 3][i % 3 + moduleCount - 8 - 3] = mod;
    }

    for (var i = 0; i < 18; i++) {
      final mod = !test && ((bits >> i) & 1) == 1;
      _modules[i % 3 + moduleCount - 8 - 3][i ~/ 3] = mod;
    }
  }

  void _mapData(List<int> data, int maskPattern) {
    var inc = -1;
    var row = moduleCount - 1;
    var bitIndex = 7;
    var byteIndex = 0;

    for (var col = moduleCount - 1; col > 0; col -= 2) {
      if (col == 6) col--;

      for (;;) {
        for (var c = 0; c < 2; c++) {
          if (_modules[row][col - c] == null) {
            var dark = false;

            if (byteIndex < data.length) {
              dark = ((data[byteIndex] >> bitIndex) & 1) == 1;
            }

            final mask = _mask(maskPattern, row, col - c);

            if (mask) {
              dark = !dark;
            }

            _modules[row][col - c] = dark;
            bitIndex--;

            if (bitIndex == -1) {
              byteIndex++;
              bitIndex = 7;
            }
          }
        }

        row += inc;

        if (row < 0 || moduleCount <= row) {
          row -= inc;
          inc = -inc;
          break;
        }
      }
    }
  }
}

bool _mask(int maskPattern, int i, int j) => switch (maskPattern) {
      qr_mask_pattern.pattern000 => (i + j).isEven,
      qr_mask_pattern.pattern001 => i.isEven,
      qr_mask_pattern.pattern010 => j % 3 == 0,
      qr_mask_pattern.pattern011 => (i + j) % 3 == 0,
      qr_mask_pattern.pattern100 => ((i ~/ 2) + (j ~/ 3)).isEven,
      qr_mask_pattern.pattern101 => (i * j) % 2 + (i * j) % 3 == 0,
      qr_mask_pattern.pattern110 => ((i * j) % 2 + (i * j) % 3).isEven,
      qr_mask_pattern.pattern111 => ((i * j) % 3 + (i + j) % 2).isEven,
      _ => throw ArgumentError('bad maskPattern:$maskPattern')
    };

double _lostPoint(QrImage qrImage) {
  final moduleCount = qrImage.moduleCount;

  var lostPoint = 0.0;
  int row;

  // LEVEL1
  final size = moduleCount;
  var points = 0;
  var sameCountCol = 0;
  var sameCountRow = 0;
  bool? lastCol;
  bool? lastRow;
  for (row = 0; row < moduleCount; row++) {
    sameCountCol = sameCountRow = 0;
    lastCol = lastRow = null;

    for (var col = 0; col < size; col++) {
      var module = qrImage.isDark(row, col);
      if (module == lastCol) {
        sameCountCol++;
      } else {
        if (sameCountCol >= 5) points += 3 + (sameCountCol - 5);
        lastCol = module;
        sameCountCol = 1;
      }

      module = qrImage.isDark(col, row);
      if (module == lastRow) {
        sameCountRow++;
      } else {
        if (sameCountRow >= 5) points += 3 + (sameCountRow - 5);
        lastRow = module;
        sameCountRow = 1;
      }
    }

    if (sameCountCol >= 5) points += 3 + (sameCountCol - 5);
    if (sameCountRow >= 5) points += 3 + (sameCountRow - 5);
  }

  // LEVEL2
  points = 0;
  for (var row = 0; row < size - 1; row++) {
    for (var col = 0; col < size - 1; col++) {
      var count = 0;
      count += qrImage.isDark(row, col) ? 1 : 0;
      count += qrImage.isDark(row, col + 1) ? 1 : 0;
      count += qrImage.isDark(row + 1, col) ? 1 : 0;
      count += qrImage.isDark(row + 1, col + 1) ? 1 : 0;

      if (count == 0 || count == 4) {
        points++;
      }
    }
  }

  lostPoint = points * 3;

  // LEVEL3
  points = 0;
  var bitsCol = 0;
  var bitsRow = 0;

  for (var row = 0; row < size; row++) {
    bitsCol = bitsRow = 0;
    for (var col = 0; col < size; col++) {
      bitsCol = ((bitsCol << 1) & 0x7FF) | (qrImage.isDark(row, col) ? 1 : 0);
      if (col >= 10 && (bitsCol == 0x5D0 || bitsCol == 0x05D)) points++;

      bitsRow = ((bitsRow << 1) & 0x7FF) | (qrImage.isDark(col, row) ? 1 : 0);
      if (col >= 10 && (bitsRow == 0x5D0 || bitsRow == 0x05D)) points++;
    }
  }

  lostPoint = points * 40;

  // LEVEL4
  var darkCount = 0;
  final modulesCount = moduleCount * moduleCount;

  for (var row = 0; row < moduleCount; row++) {
    for (var col = 0; col < moduleCount; col++) {
      if (qrImage.isDark(row, col)) {
        darkCount++;
      }
    }
  }

  final k = (darkCount * 100 / modulesCount).ceil() / 5;
  final ratio = (10 - k).abs();

  return lostPoint += ratio * 10;
}
