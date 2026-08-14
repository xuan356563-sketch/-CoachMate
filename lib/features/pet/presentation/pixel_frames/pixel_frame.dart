import '../../../../data/models/pet.dart';

/// 单张 24×24 点阵主体帧。
class PixelFrame {
  PixelFrame(List<int> rows) : rows = List<int>.unmodifiable(rows) {
    if (rows.length != 24) {
      throw ArgumentError.value(rows.length, 'rows', '点阵帧必须恰好包含 24 行');
    }
    if (rows.any((int row) => row < 0 || row >= (1 << 24))) {
      throw ArgumentError.value(rows, 'rows', '点阵帧每行只能使用低 24 位');
    }
    if (rows.every((int row) => row == 0)) {
      throw ArgumentError.value(rows, 'rows', '点阵主体不能全部为空');
    }
  }

  final List<int> rows;

  bool isOn(int x, int y) {
    if (x < 0 || x >= 24 || y < 0 || y >= 24) return false;
    return (rows[y] & (1 << x)) != 0;
  }

  int get litPixelCount {
    int total = 0;
    for (final int row in rows) {
      int remaining = row;
      while (remaining != 0) {
        total += remaining & 1;
        remaining >>= 1;
      }
    }
    return total;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PixelFrame) return false;
    for (int index = 0; index < 24; index += 1) {
      if (rows[index] != other.rows[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(rows);
}

/// 一个物种在一个阶段的两张基础动作帧。
class PetFormFrames {
  PetFormFrames({
    required this.species,
    required this.stage,
    required this.frameA,
    required this.frameB,
  }) {
    if (frameA == frameB) {
      throw ArgumentError('同一形态的 A/B 两帧必须可区分');
    }
  }

  final PetSpecies species;
  final PetStage stage;
  final PixelFrame frameA;
  final PixelFrame frameB;

  List<PixelFrame> get frames => <PixelFrame>[frameA, frameB];
}
