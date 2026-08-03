var createGraph = require('ngraph.graph');
var hilbert3d = require('./hilbert3d.js');

module.exports = buildRing;

/**
 * Builds the graph we render: a single closed ring threaded along a 3d Hilbert
 * curve.
 *
 * Every node has exactly two neighbours (the previous and the next point on the
 * curve) and the last node links back to the first, so the whole thing is one
 * cycle - connected, no stragglers, and exactly one edge per node no matter how
 * many nodes we ask for.
 *
 * @param {Object} options
 * @param {number} options.order - Hilbert order. Cube is 2^order cells per side.
 * @param {number} options.count - how many nodes to place (<= 8^order).
 * @param {number} options.spacing - world distance between neighbouring nodes.
 * @returns {Object} { graph, positions, count, radius, spacing }
 */
function buildRing(options) {
  var order = options.order;
  var spacing = options.spacing;
  var total = hilbert3d.pointCount(order);
  var count = Math.max(2, Math.min(options.count || total, total));

  var side = hilbert3d.sideLength(order);
  var offset = (side - 1) / 2;

  // uniqueLinkId costs an O(degree) lookup per link and a hash table we never
  // read; the curve can't produce duplicate edges, so turn it off.
  var graph = createGraph({ uniqueLinkId: false });
  var positions = new Array(count);

  hilbert3d(order, count, function (x, y, z, index) {
    positions[index] = {
      x: (x - offset) * spacing,
      y: (y - offset) * spacing,
      z: (z - offset) * spacing
    };

    // No per-node data object: at this scale that allocation alone is tens of
    // megabytes, and the id already tells us everything we show.
    graph.addNode(index);
    if (index > 0) graph.addLink(index - 1, index);
  });

  graph.addLink(count - 1, 0);

  return {
    graph: graph,
    positions: positions,
    count: count,
    spacing: spacing,
    // Half the diagonal of the filled cube - what the camera has to clear.
    radius: (side - 1) * spacing * Math.sqrt(3) / 2
  };
}
