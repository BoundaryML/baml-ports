// Port of src/parse/line-counter.ts

/// Tracks newlines during parsing in order to provide an efficient API for
/// determining the one-indexed `{ line, col }` position for any offset
/// within the input.
class LineCounter {
  lineStarts: int[]

  /// Should be called in ascending order. Otherwise, call
  /// `lineCounter.lineStarts.sort()` before calling `linePos()`.
  function addNewLine(self, offset: int) -> int {
    self.lineStarts.push(offset)
  }

  /// Performs a binary search and returns the 1-indexed { line, col }
  /// position of `offset`. If `line === 0`, `addNewLine` has never been
  /// called or `offset` is before the first known newline.
  function linePos(self, offset: int) -> LinePos {
    let low = 0;
    let high = self.lineStarts.length();
    while (low < high) {
      let mid = (low + high) >> 1; // Math.floor((low + high) / 2)
      if (self.lineStarts[mid] < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (self.lineStarts.at(low) == offset) {
      return LinePos { line: low + 1, col: 1 };
    }
    if (low == 0) {
      return LinePos { line: 0, col: offset };
    }
    let start = self.lineStarts[low - 1];
    LinePos { line: low, col: offset - start + 1 }
  }
}

class LinePos {
  line: int
  col: int
}

function new_line_counter() -> LineCounter {
  LineCounter { lineStarts: [] }
}
