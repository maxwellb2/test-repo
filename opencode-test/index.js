var graph = require('ngraph.graph')();
var renderGraph = require('ngraph.pixel');

var nodeNames = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve', 'Frank'];

nodeNames.forEach(function (name) {
  graph.addNode(name, { label: name });
});

graph.addLink('Alice', 'Bob');
graph.addLink('Alice', 'Charlie');
graph.addLink('Bob', 'Diana');
graph.addLink('Charlie', 'Diana');
graph.addLink('Diana', 'Eve');
graph.addLink('Eve', 'Frank');
graph.addLink('Frank', 'Alice');

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
