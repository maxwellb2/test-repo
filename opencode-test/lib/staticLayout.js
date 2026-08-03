module.exports = createStaticLayout;

/**
 * A layout provider for ngraph.pixel that hands back precomputed positions.
 *
 * The default force layout is what normally caps the node count: it runs a
 * Barnes-Hut simulation step on every frame and never converges on a graph this
 * size. Reporting "stable" on the first step means the renderer uploads the
 * vertex buffers once and then does nothing but draw.
 *
 * @param {Array} positions - {x, y, z} indexed by node id.
 */
function createStaticLayout(positions) {
  return function () {
    return {
      step: step,
      getNodePosition: getNodePosition
    };
  };

  function step() {
    return true; // already stable, never simulate.
  }

  function getNodePosition(nodeId) {
    return positions[nodeId];
  }
}
