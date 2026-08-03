module.exports = createPalette;

/**
 * Precomputes a rainbow ramp that we index by position along the ring, so the
 * colour of a node tells you where you are on the curve. Edges get a darker
 * shade of the same hue: at this density fully lit edges wash out the nodes.
 *
 * Precomputed because at a quarter million nodes even a cheap HSL conversion
 * per node is wasted work - a few thousand steps are indistinguishable from a
 * continuous ramp.
 *
 * @param {number} steps - how many distinct colours to generate.
 * @param {number} edgeDim - 0..1 lightness multiplier applied to edge colours.
 */
function createPalette(steps, edgeDim) {
  var node = new Array(steps);
  var edge = new Array(steps);

  for (var i = 0; i < steps; ++i) {
    var hue = i / steps;
    node[i] = hslToHex(hue, 0.85, 0.62);
    edge[i] = hslToHex(hue, 0.85, 0.62 * edgeDim);
  }

  return {
    steps: steps,
    node: node,
    edge: edge
  };
}

function hslToHex(h, s, l) {
  var c = (1 - Math.abs(2 * l - 1)) * s;
  var hp = h * 6;
  var x = c * (1 - Math.abs((hp % 2) - 1));
  var m = l - c / 2;
  var r = 0, g = 0, b = 0;

  if (hp < 1) { r = c; g = x; }
  else if (hp < 2) { r = x; g = c; }
  else if (hp < 3) { g = c; b = x; }
  else if (hp < 4) { g = x; b = c; }
  else if (hp < 5) { r = x; b = c; }
  else { r = c; b = x; }

  return (to255(r + m) << 16) | (to255(g + m) << 8) | to255(b + m);
}

function to255(v) {
  return Math.max(0, Math.min(255, Math.round(v * 255)));
}
