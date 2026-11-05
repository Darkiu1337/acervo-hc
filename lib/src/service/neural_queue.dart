/// Scheduling policy for the neural upscale queue.
///
/// The reader mounts a few pages around the visible one, so requests arrive out
/// of order and the single GPU process must always start with the page the user
/// is looking at. This class owns only that decision, with no Flutter, files or
/// GPU involved, so the ordering can be unit tested.
///
/// Indexes are absolute page indexes inside the gallery.
class NeuralQueue {
  /// Pages behind the visible one are cheap to skip: revisiting a page usually
  /// hits the disk cache from the previous turns.
  static const int behind = 2;

  int _focus = 0;
  int _ahead = 3;

  /// Visible page index.
  int get focus => _focus;

  /// How many pages ahead of [focus] stay in the queue.
  int get ahead => _ahead;

  void setAhead(int value) {
    _ahead = value < 0 ? 0 : value;
  }

  void setFocus(int index) {
    _focus = index;
  }

  /// Signed distance from the visible page: `0` is the visible one, positive is
  /// ahead of it and negative is behind.
  int distance(int index) => index - _focus;

  /// Whether [index] is close enough to the visible page to be worth
  /// processing right now.
  bool contains(int index) =>
      index >= _focus - behind && index <= _focus + _ahead;

  /// Ordering score: the visible page first, then the pages ahead in reading
  /// order, then the ones behind. The large base keeps every "behind" page
  /// after every "ahead" page.
  int score(int index) {
    final int distance = this.distance(index);
    return distance >= 0 ? distance : 1000 - distance;
  }

  /// Position of the entry that should run next, or `-1` when [indexes] is
  /// empty. Ties keep the earliest position, so the queue stays stable.
  int pick(List<int> indexes) {
    int best = -1;
    int bestScore = 0;
    for (int i = 0; i < indexes.length; i++) {
      final int value = score(indexes[i]);
      if (best < 0 || value < bestScore) {
        best = i;
        bestScore = value;
      }
    }
    return best;
  }

  /// Positions of [indexes] that fell outside the window.
  List<int> stale(List<int> indexes) {
    final List<int> positions = <int>[];
    for (int i = 0; i < indexes.length; i++) {
      if (!contains(indexes[i])) {
        positions.add(i);
      }
    }
    return positions;
  }
}
