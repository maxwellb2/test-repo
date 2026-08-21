var createPackedRenderer = require('./lib/packedRenderer.js');

var query = new URLSearchParams(window.location.search);
var count = clamp(parseInt(query.get('count'), 10) || 10000000, 2, 16777216);
var order = clamp(parseInt(query.get('order'), 10) || requiredOrder(count), requiredOrder(count), 8);
var pointSize = clamp(parseFloat(query.get('size')) || 2, 1, 8);
var statusEl = document.getElementById('status');
var hudEl = document.getElementById('hud');
var started = performance.now();

setStatus('Allocating ' + count.toLocaleString() + ' packed nodes…');

requestAnimationFrame(function () {
  startWorker();
});

function startWorker() {
  var worker = new Worker('hilbert-worker.js');

  worker.onmessage = function (event) {
    var message = event.data;
    if (message.type === 'progress') {
      var percent = Math.floor(message.completed / message.count * 100);
      setStatus('Generating ' + count.toLocaleString() + ' nodes… ' + percent + '%');
    } else if (message.type === 'error') {
      fail(message.message);
    } else if (message.type === 'complete') {
      worker.terminate();
      upload(message);
    }
  };
  worker.onerror = function (event) {
    fail(event.message || 'Hilbert worker failed.');
  };
  worker.postMessage({ order: order, count: count });
}

function upload(message) {
  var generatedAt = performance.now();
  setStatus('Uploading ' + count.toLocaleString() + ' nodes (' +
    formatBytes(count * 3) + ') to the GPU…');

  requestAnimationFrame(function () {
    try {
      var firstFrame = true;
      createPackedRenderer(
        document.getElementById('scene'),
        new Uint8Array(message.positions),
        {
          count: count,
          side: message.side,
          pointSize: pointSize,
          onRender: function (frameMs, state) {
            showHud({
              generatedMs: generatedAt - started,
              totalMs: performance.now() - started,
              frameMs: frameMs,
              edges: state.edges,
              points: state.points
            });
            if (firstFrame) {
              firstFrame = false;
              hideStatus();
            }
          }
        }
      );
    } catch (error) {
      fail(error.message);
    }
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
    '<div class="title">10M Hilbert ring</div>' +
    '<div><b>' + count.toLocaleString() + '</b> nodes · <b>' +
      count.toLocaleString() + '</b> edges · degree <b>2</b></div>' +
    '<div>order ' + order + ' · packed XYZ ' +
      formatBytes(count * 3) + ' · point size ' + pointSize + '</div>' +
    '<div>generated ' + Math.round(info.generatedMs) + ' ms · last draw ' +
      info.frameMs.toFixed(1) + ' ms</div>' +
    '<div class="hint">drag orbit · wheel zoom · E edges · P points</div>' +
    '<div class="hint">edges ' + (info.edges ? 'on' : 'off') +
      ' · points ' + (info.points ? 'on' : 'off') + '</div>';
}

function fail(message) {
  setStatus('Could not render: ' + message);
  statusEl.className = 'error';
}

function requiredOrder(nodeCount) {
  return Math.ceil(Math.log(nodeCount) / Math.log(8));
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function formatBytes(bytes) {
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}
