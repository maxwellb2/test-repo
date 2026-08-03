/**
 * Measures what the graph itself costs before any rendering, which is the limit
 * that actually decides how many nodes we can ask for. Run it with
 * `npm run memory -- 6` (or any order) and add roughly 60-80 MB of WebGL
 * buffers plus the browser's own overhead on top of what it prints.
 */
var buildRing = require('../lib/buildRing.js');
var hilbert3d = require('../lib/hilbert3d.js');

var orders = process.argv.slice(2).map(Number).filter(function (n) {
  return n > 0;
});
if (orders.length === 0) orders = [5, 6];

orders.forEach(function (order) {
  if (global.gc) global.gc();
  var before = process.memoryUsage().heapUsed;
  var started = Date.now();

  var ring = buildRing({ order: order, spacing: 12, count: hilbert3d.pointCount(order) });

  var elapsed = Date.now() - started;
  var used = (process.memoryUsage().heapUsed - before) / (1024 * 1024);

  console.log(
    'order ' + order +
    '  nodes ' + ring.count.toLocaleString() +
    '  edges ' + ring.graph.getLinksCount().toLocaleString() +
    '  heap ' + used.toFixed(0) + ' MB' +
    '  build ' + elapsed + ' ms'
  );
});
