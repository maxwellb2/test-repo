/**
 * Generates points of a 3d Hilbert curve.
 *
 * The curve is what lets us push the node count so high: it visits every cell
 * of a 2^order cube exactly once, consecutive points are always one cell apart,
 * and nearby points on the curve stay nearby in space. That gives us a very
 * long, evenly spread path - the maximum amount of "visible graph" you can pack
 * into a viewing volume before nodes start overlapping each other on screen.
 */
module.exports = walk;
module.exports.pointCount = pointCount;
module.exports.sideLength = sideLength;

var DIMENSIONS = 3;

function pointCount(order) {
  return Math.pow(8, order);
}

function sideLength(order) {
  return Math.pow(2, order);
}

/**
 * Visits the first `count` points of an order-`order` curve, in curve order.
 *
 * @param {number} order - number of subdivisions. Cube side is 2^order.
 * @param {number} count - how many points to visit. Any prefix of the curve is
 *   itself a connected path, so this can be smaller than 8^order.
 * @param {Function} visit - called as visit(x, y, z, index) with integer
 *   coordinates in [0, 2^order).
 */
function walk(order, count, visit) {
  var axes = [0, 0, 0];

  for (var index = 0; index < count; ++index) {
    indexToAxes(index, order, axes);
    visit(axes[0], axes[1], axes[2], index);
  }
}

function indexToAxes(index, order, out) {
  out[0] = 0;
  out[1] = 0;
  out[2] = 0;

  // Split the index into `order` groups of three bits, most significant first.
  // Each group contributes one bit to every axis, which produces Skilling's
  // "transpose" form of the index.
  for (var i = 0; i < order; ++i) {
    var shift = order - 1 - i;
    var triple = (index >>> (3 * shift)) & 7;

    out[0] |= ((triple >>> 2) & 1) << shift;
    out[1] |= ((triple >>> 1) & 1) << shift;
    out[2] |= (triple & 1) << shift;
  }

  transposeToAxes(out, order);
}

/**
 * Skilling's transpose-to-axes conversion (Programming the Hilbert curve, 2004).
 */
function transposeToAxes(X, bits) {
  var side = 1 << bits;
  var i, t, p, q;

  // Gray decode.
  t = X[DIMENSIONS - 1] >>> 1;
  for (i = DIMENSIONS - 1; i > 0; --i) X[i] ^= X[i - 1];
  X[0] ^= t;

  // Undo excess work.
  for (q = 2; q !== side; q <<= 1) {
    p = q - 1;
    for (i = DIMENSIONS - 1; i >= 0; --i) {
      if (X[i] & q) {
        X[0] ^= p;
      } else {
        t = (X[0] ^ X[i]) & p;
        X[0] ^= t;
        X[i] ^= t;
      }
    }
  }
}
