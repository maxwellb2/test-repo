/**
 * Checks the two properties the visualization depends on:
 *  - the curve is a valid Hilbert tour (every cell once, unit steps),
 *  - the graph built on top of it is one connected cycle with degree 2.
 *
 * Run with `npm test`.
 */
var hilbert3d = require('../lib/hilbert3d.js');
var buildRing = require('../lib/buildRing.js');

var failures = 0;

function check(name, condition, detail) {
  if (condition) {
    console.log('  ok   ' + name);
  } else {
    failures += 1;
    console.log('  FAIL ' + name + (detail === undefined ? '' : ' -> ' + detail));
  }
}

function testCurve(order) {
  console.log('hilbert curve, order ' + order);

  var total = hilbert3d.pointCount(order);
  var side = hilbert3d.sideLength(order);
  var seen = new Set();
  var duplicates = 0;
  var outOfBounds = 0;
  var jumps = 0;
  var prev = null;
  var first = null;
  var last = null;

  hilbert3d(order, total, function (x, y, z, index) {
    var key = x + ':' + y + ':' + z;
    if (seen.has(key)) duplicates += 1;
    seen.add(key);

    if (x < 0 || y < 0 || z < 0 || x >= side || y >= side || z >= side) outOfBounds += 1;

    if (prev !== null) {
      var step = Math.abs(x - prev[0]) + Math.abs(y - prev[1]) + Math.abs(z - prev[2]);
      if (step !== 1) jumps += 1;
    }

    prev = [x, y, z];
    if (index === 0) first = [x, y, z];
    last = [x, y, z];
  });

  check('visits every cell exactly once', seen.size === total && duplicates === 0, seen.size + ' of ' + total);
  check('stays inside the cube', outOfBounds === 0, outOfBounds + ' strays');
  check('every step is one cell', jumps === 0, jumps + ' jumps');
  check('endpoints share an axis so the loop closes cleanly',
    first[1] === last[1] && first[2] === last[2],
    first.join(',') + ' -> ' + last.join(','));
}

function testRing(order) {
  console.log('ring graph, order ' + order);

  var ring = buildRing({ order: order, spacing: 10, count: hilbert3d.pointCount(order) });
  var graph = ring.graph;

  check('node count matches the curve', graph.getNodesCount() === ring.count, graph.getNodesCount());
  check('one edge per node', graph.getLinksCount() === ring.count, graph.getLinksCount());

  var wrongDegree = 0;
  graph.forEachNode(function (node) {
    if (!node.links || node.links.length !== 2) wrongDegree += 1;
  });
  check('every node has exactly two neighbours', wrongDegree === 0, wrongDegree + ' offenders');

  var visited = new Set();
  var current = 0;
  var previous = -1;
  do {
    visited.add(current);
    var next = -1;
    var links = graph.getLinks(current);
    for (var i = 0; i < links.length; ++i) {
      var other = links[i].fromId === current ? links[i].toId : links[i].fromId;
      if (other !== previous) next = other;
    }
    previous = current;
    current = next;
  } while (current !== 0 && current !== -1 && !visited.has(current));

  check('a single walk reaches every node', visited.size === ring.count, visited.size + ' of ' + ring.count);
  check('the walk returns to the start', current === 0, 'stopped at ' + current);

  var maxNeighbourGap = 0;
  graph.forEachLink(function (link) {
    var a = ring.positions[link.fromId];
    var b = ring.positions[link.toId];
    var d = Math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) + (a.z - b.z) * (a.z - b.z));
    if (d > maxNeighbourGap) maxNeighbourGap = d;
  });
  console.log('       longest edge: ' + maxNeighbourGap.toFixed(1) + ' world units (spacing is 10)');
}

testCurve(1);
testCurve(2);
testCurve(4);
testRing(3);
testRing(4);

if (failures > 0) {
  console.log('\n' + failures + ' failing check(s)');
  process.exit(1);
}
console.log('\nall checks passed');
