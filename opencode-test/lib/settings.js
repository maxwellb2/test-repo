var hilbert3d = require('./hilbert3d.js');

module.exports = resolveSettings;

/**
 * Default settings are tuned for a modern laptop: order 6 fills a 64^3 cube
 * (262 144 nodes) for about 200 MB of JS heap plus ~80 MB of WebGL buffers.
 * Order 7 would be another 8x and pushes past a gigabyte - still reachable via
 * the URL, but not the default.
 *
 * Override any of them from the query string, e.g.
 *   ?order=5&spacing=20&size=14
 */
function resolveSettings(search) {
  var query = parseQuery(search || '');

  var order = clampInt(query.order, 1, 7, 6);
  var maxCount = hilbert3d.pointCount(order);
  var count = clampInt(query.count, 2, maxCount, maxCount);
  var spacing = clampNumber(query.spacing, 1, 200, defaultSpacing(order));
  var size = clampNumber(query.size, 1, 80, defaultSize(order, count));

  return {
    order: order,
    count: count,
    spacing: spacing,
    size: size,
    // Small enough that consecutive nodes on the rainbow still look distinct,
    // large enough that we never recompute HSL at runtime.
    paletteSteps: 2048,
    edgeDim: 0.45,
    background: 0x05070b
  };
}

function defaultSpacing(order) {
  // Keep the filled cube roughly the same screen size as the order grows, so
  // switching between orders doesn't fling the camera into empty space.
  return Math.max(4, Math.round(900 / hilbert3d.sideLength(order)));
}

function defaultSize(order, count) {
  // Point size is in "pixel-ish" units the shader scales by distance. Smaller
  // as density rises so neighbouring nodes don't blot each other out.
  if (count >= 1000000) return 6;
  if (count >= 200000) return 8;
  if (count >= 30000) return 12;
  return 18;
}

function parseQuery(search) {
  var out = Object.create(null);
  var raw = search.charAt(0) === '?' ? search.slice(1) : search;
  if (!raw) return out;

  raw.split('&').forEach(function (pair) {
    if (!pair) return;
    var parts = pair.split('=');
    var key = decodeURIComponent(parts[0]);
    var value = decodeURIComponent(parts.slice(1).join('=') || '');
    out[key] = value;
  });
  return out;
}

function clampInt(value, min, max, fallback) {
  var n = parseInt(value, 10);
  if (!isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

function clampNumber(value, min, max, fallback) {
  var n = parseFloat(value);
  if (!isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}
