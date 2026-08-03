var renderGraph = require('ngraph.pixel');
var resolveSettings = require('./lib/settings.js');
var buildRing = require('./lib/buildRing.js');
var createStaticLayout = require('./lib/staticLayout.js');
var createPalette = require('./lib/palette.js');

var settings = resolveSettings(window.location.search);
var statusEl = document.getElementById('status');
var hudEl = document.getElementById('hud');

setStatus('Building ' + settings.count.toLocaleString() + ' node Hilbert ring…');

// Yield once so the loading text paints before we block the main thread.
requestAnimationFrame(function () {
  setTimeout(boot, 0);
});

function boot() {
  var started = performance.now();
  var ring = buildRing(settings);
  var palette = createPalette(settings.paletteSteps, settings.edgeDim);
  var builtAt = performance.now();

  setStatus('Uploading ' + ring.count.toLocaleString() + ' nodes to the GPU…');

  requestAnimationFrame(function () {
    var renderer = renderGraph(ring.graph, {
      container: document.getElementById('scene'),
      autoFit: true,
      clearColor: settings.background,
      // Skip the makeActive proxy wrappers - with a static layout they only cost
      // memory (one Map + property getters per node and per edge).
      activeNode: false,
      activeLink: false,
      createLayout: createStaticLayout(ring.positions),
      node: function (node) {
        return {
          color: palette.node[node.id % palette.steps],
          size: settings.size
        };
      },
      link: function (link) {
        // Colour the edge by the midpoint of the two nodes so it blends into
        // the rainbow rather than looking like a separate overlay.
        var mid = ((link.fromId + link.toId) / 2) | 0;
        var color = palette.edge[mid % palette.steps];
        return {
          fromColor: color,
          toColor: color
        };
      }
    });

    // Pull the camera far enough back that the initial autofit doesn't clip
    // the corners of a large cube (PerspectiveCamera.far defaults to 20000).
    var camera = renderer.camera();
    camera.far = Math.max(20000, ring.radius * 20);
    camera.updateProjectionMatrix();

    var announced = false;
    renderer.on('stable', function () {
      if (announced) return;
      announced = true;

      var elapsed = performance.now() - started;
      showHud({
        nodes: ring.count,
        edges: ring.graph.getLinksCount(),
        order: settings.order,
        spacing: settings.spacing,
        size: settings.size,
        buildMs: Math.round(builtAt - started),
        totalMs: Math.round(elapsed),
        radius: Math.round(ring.radius)
      });
      hideStatus();
    });
  });
}

function setStatus(text) {
  if (!statusEl) return;
  statusEl.textContent = text;
  statusEl.hidden = false;
}

function hideStatus() {
  if (!statusEl) return;
  statusEl.hidden = true;
}

function showHud(info) {
  if (!hudEl) return;
  hudEl.hidden = false;
  hudEl.innerHTML =
    '<div class="title">Hilbert ring</div>' +
    '<div><b>' + info.nodes.toLocaleString() + '</b> nodes · <b>' +
      info.edges.toLocaleString() + '</b> edges</div>' +
    '<div>order ' + info.order + ' · spacing ' + info.spacing +
      ' · size ' + info.size + '</div>' +
    '<div>built ' + info.buildMs + ' ms · ready ' + info.totalMs + ' ms</div>' +
    '<div class="hint">WASD move · RF up/down · drag look · QE roll</div>' +
    '<div class="hint">?order=6&amp;count=262144&amp;spacing=14&amp;size=8</div>';
}
