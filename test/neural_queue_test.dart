import 'package:flutter_test/flutter_test.dart';
import 'package:acervo_hc/src/service/neural_queue.dart';

void main() {
  group('NeuralQueue window', () {
    test('keeps every page ahead and two behind', () {
      final NeuralQueue queue = NeuralQueue()
        ..setAhead(8)
        ..setFocus(10);

      expect(queue.contains(10), isTrue);
      expect(queue.contains(18), isTrue);
      expect(queue.contains(19), isFalse);
      expect(queue.contains(8), isTrue);
      expect(queue.contains(7), isFalse);
    });

    test('page zero does not underflow', () {
      final NeuralQueue queue = NeuralQueue()..setFocus(0);

      expect(queue.contains(0), isTrue);
      expect(queue.contains(-1), isFalse);
      expect(queue.stale(<int>[-1, 0, 1]), <int>[0]);
    });
  });

  group('NeuralQueue ordering', () {
    test('visible page runs first', () {
      final NeuralQueue queue = NeuralQueue()
        ..setAhead(8)
        ..setFocus(10);

      expect(queue.pick(<int>[9, 12, 10, 11]), 2);
    });

    test('ahead pages beat the ones behind', () {
      final NeuralQueue queue = NeuralQueue()
        ..setAhead(8)
        ..setFocus(10);

      expect(queue.pick(<int>[9, 8, 14]), 2);
      expect(queue.pick(<int>[9, 8]), 0);
    });

    test('ties keep the earliest entry', () {
      final NeuralQueue queue = NeuralQueue()..setFocus(10);

      expect(queue.pick(<int>[12, 12]), 0);
    });

    test('empty queue has no next job', () {
      expect(NeuralQueue().pick(<int>[]), -1);
    });
  });

  group('NeuralQueue stale', () {
    test('reports the positions that left the window', () {
      final NeuralQueue queue = NeuralQueue()
        ..setAhead(2)
        ..setFocus(10);

      expect(queue.stale(<int>[2, 9, 12, 30]), <int>[0, 3]);
    });
  });
}
