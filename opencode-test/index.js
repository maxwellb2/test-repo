var graph = require('ngraph.graph')();
var renderGraph = require('ngraph.pixel');

var nodeCount = 30;

for (var i = 0; i < nodeCount; ++i) {
  graph.addNode(i, { label: 'Node ' + i });
}

for (var from = 0; from < nodeCount; ++from) {
  for (var to = from + 1; to < nodeCount; to += 3) {
    graph.addLink(from, to);
  }
}

var renderer = renderGraph(graph, {
  node: function (node) {
    return {
      color: 0x4285F4,
      size: 30
    };
  },
  link: function () {
    return {
      fromColor: 0xEA4335,
      toColor: 0xFBBC05
    };
  }
});

renderer.on('nodeclick', function (node) {
  var ui = renderer.getNode(node.id);
  ui.color = 0x34A853;
  console.log('Clicked node:', node.data.label);
});

renderer.on('nodehover', function (node) {
  if (node) {
    document.title = 'Hovering: ' + node.data.label;
  }
});
