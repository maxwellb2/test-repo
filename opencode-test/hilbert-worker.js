/* global hilbert3d */
importScripts('lib/hilbert3d.js');

self.onmessage = function (event) {
  var order = event.data.order;
  var count = event.data.count;
  var side = hilbert3d.sideLength(order);

  // Order 8 has coordinates 0..255, so each complete 3D position fits in
  // three bytes. Ten million nodes therefore cost 30 MB rather than hundreds
  // of megabytes of JS objects.
  if (side > 256) {
    self.postMessage({ type: 'error', message: 'Packed renderer supports Hilbert orders up to 8.' });
    return;
  }

  var positions = new Uint8Array(count * 3);
  var progressEvery = 250000;

  hilbert3d(order, count, function (x, y, z, index) {
    var offset = index * 3;
    positions[offset] = x;
    positions[offset + 1] = y;
    positions[offset + 2] = z;

    if (index > 0 && index % progressEvery === 0) {
      self.postMessage({ type: 'progress', completed: index, count: count });
    }
  });

  self.postMessage({
    type: 'complete',
    count: count,
    order: order,
    side: side,
    positions: positions.buffer
  }, [positions.buffer]);
};
