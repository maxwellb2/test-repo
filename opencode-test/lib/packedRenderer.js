module.exports = createPackedRenderer;

/**
 * Draws an implicit cycle straight from one packed XYZ buffer.
 *
 * There are no node objects, edge objects, colors, sizes, edge positions, or
 * index buffers. Vertex i connects to i + 1 and LINE_LOOP closes the final
 * edge, so topology is implicit and every vertex has degree exactly two.
 */
function createPackedRenderer(container, packedPositions, options) {
  var canvas = document.createElement('canvas');
  container.appendChild(canvas);

  var gl = canvas.getContext('webgl2', {
    antialias: false,
    alpha: false,
    depth: false,
    powerPreference: 'high-performance',
    preserveDrawingBuffer: false
  });
  if (!gl) throw new Error('WebGL 2 is required for the 10-million-node renderer.');

  var program = createProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER);
  var positionLocation = gl.getAttribLocation(program, 'a_position');
  var matrixLocation = gl.getUniformLocation(program, 'u_matrix');
  var sideLocation = gl.getUniformLocation(program, 'u_side');
  var countLocation = gl.getUniformLocation(program, 'u_count');
  var pointSizeLocation = gl.getUniformLocation(program, 'u_pointSize');
  var brightnessLocation = gl.getUniformLocation(program, 'u_brightness');

  var buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, packedPositions, gl.STATIC_DRAW);
  gl.enableVertexAttribArray(positionLocation);
  gl.vertexAttribPointer(positionLocation, 3, gl.UNSIGNED_BYTE, false, 3, 0);

  gl.useProgram(program);
  gl.uniform1f(sideLocation, options.side - 1);
  gl.uniform1f(countLocation, options.count);
  gl.uniform1f(pointSizeLocation, options.pointSize);
  gl.clearColor(0.02, 0.027, 0.043, 1);
  gl.disable(gl.DEPTH_TEST);
  gl.disable(gl.BLEND);

  var state = {
    yaw: 0.65,
    pitch: 0.45,
    distance: 3.15,
    edges: true,
    points: true,
    rendering: false
  };
  var projection = new Float32Array(16);
  var view = new Float32Array(16);
  var matrix = new Float32Array(16);
  var renderQueued = false;
  var lastFrameMs = 0;

  installControls();
  resize();

  return {
    render: requestRender,
    stats: function () {
      return {
        frameMs: lastFrameMs,
        gpuBytes: packedPositions.byteLength
      };
    }
  };

  function requestRender() {
    if (renderQueued) return;
    renderQueued = true;
    requestAnimationFrame(render);
  }

  function render() {
    renderQueued = false;
    var started = performance.now();

    var width = canvas.clientWidth;
    var height = canvas.clientHeight;
    var targetWidth = Math.max(1, Math.floor(width));
    var targetHeight = Math.max(1, Math.floor(height));
    // Deliberately cap at CSS-pixel resolution. Retina resolution would
    // quadruple fragment work without revealing more of a 10M-node cloud.
    if (canvas.width !== targetWidth || canvas.height !== targetHeight) {
      canvas.width = targetWidth;
      canvas.height = targetHeight;
      gl.viewport(0, 0, targetWidth, targetHeight);
    }

    perspective(projection, Math.PI / 3, targetWidth / targetHeight, 0.01, 100);
    var cosPitch = Math.cos(state.pitch);
    var eye = [
      state.distance * Math.sin(state.yaw) * cosPitch,
      state.distance * Math.sin(state.pitch),
      state.distance * Math.cos(state.yaw) * cosPitch
    ];
    lookAt(view, eye, [0, 0, 0], [0, 1, 0]);
    multiply(matrix, projection, view);

    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(program);
    gl.uniformMatrix4fv(matrixLocation, false, matrix);

    if (state.edges) {
      gl.uniform1f(brightnessLocation, 0.28);
      gl.drawArrays(gl.LINE_LOOP, 0, options.count);
    }
    if (state.points) {
      gl.uniform1f(brightnessLocation, 1);
      gl.drawArrays(gl.POINTS, 0, options.count);
    }

    // flush() makes upload/render failures surface promptly without stalling
    // the CPU for a synchronous finish().
    gl.flush();
    lastFrameMs = performance.now() - started;
    options.onRender(lastFrameMs, state);
  }

  function resize() {
    requestRender();
  }

  function installControls() {
    var dragging = false;
    var lastX = 0;
    var lastY = 0;

    canvas.addEventListener('pointerdown', function (event) {
      dragging = true;
      lastX = event.clientX;
      lastY = event.clientY;
      canvas.setPointerCapture(event.pointerId);
    });
    canvas.addEventListener('pointermove', function (event) {
      if (!dragging) return;
      state.yaw -= (event.clientX - lastX) * 0.006;
      state.pitch += (event.clientY - lastY) * 0.006;
      state.pitch = Math.max(-1.5, Math.min(1.5, state.pitch));
      lastX = event.clientX;
      lastY = event.clientY;
      requestRender();
    });
    canvas.addEventListener('pointerup', function () {
      dragging = false;
    });
    canvas.addEventListener('wheel', function (event) {
      event.preventDefault();
      state.distance *= Math.exp(event.deltaY * 0.001);
      state.distance = Math.max(0.08, Math.min(20, state.distance));
      requestRender();
    }, { passive: false });
    window.addEventListener('resize', resize);
    window.addEventListener('keydown', function (event) {
      if (event.key === 'e' || event.key === 'E') state.edges = !state.edges;
      else if (event.key === 'p' || event.key === 'P') state.points = !state.points;
      else return;
      requestRender();
    });
  }
}

var VERTEX_SHADER = [
  '#version 300 es',
  'in vec3 a_position;',
  'uniform mat4 u_matrix;',
  'uniform float u_side;',
  'uniform float u_count;',
  'uniform float u_pointSize;',
  'out vec3 v_color;',
  '',
  'vec3 hue(float h) {',
  '  vec3 p = abs(fract(h + vec3(0.0, 0.666667, 0.333333)) * 6.0 - 3.0);',
  '  return clamp(p - 1.0, 0.0, 1.0);',
  '}',
  '',
  'void main() {',
  '  vec3 position = (a_position / u_side - 0.5) * 2.0;',
  '  gl_Position = u_matrix * vec4(position, 1.0);',
  '  gl_PointSize = u_pointSize;',
  '  float progress = float(gl_VertexID) / u_count;',
  '  v_color = mix(vec3(1.0), hue(progress), 0.82);',
  '}'
].join('\n');

var FRAGMENT_SHADER = [
  '#version 300 es',
  'precision mediump float;',
  'in vec3 v_color;',
  'uniform float u_brightness;',
  'out vec4 outColor;',
  'void main() {',
  '  outColor = vec4(v_color * u_brightness, 1.0);',
  '}'
].join('\n');

function createProgram(gl, vertexSource, fragmentSource) {
  var vertex = compile(gl, gl.VERTEX_SHADER, vertexSource);
  var fragment = compile(gl, gl.FRAGMENT_SHADER, fragmentSource);
  var program = gl.createProgram();
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw new Error('Could not link WebGL program: ' + gl.getProgramInfoLog(program));
  }
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);
  return program;
}

function compile(gl, type, source) {
  var shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error('Could not compile WebGL shader: ' + gl.getShaderInfoLog(shader));
  }
  return shader;
}

function perspective(out, fovy, aspect, near, far) {
  var f = 1 / Math.tan(fovy / 2);
  out[0] = f / aspect; out[1] = 0; out[2] = 0; out[3] = 0;
  out[4] = 0; out[5] = f; out[6] = 0; out[7] = 0;
  out[8] = 0; out[9] = 0; out[10] = (far + near) / (near - far); out[11] = -1;
  out[12] = 0; out[13] = 0; out[14] = (2 * far * near) / (near - far); out[15] = 0;
}

function lookAt(out, eye, center, up) {
  var zx = eye[0] - center[0], zy = eye[1] - center[1], zz = eye[2] - center[2];
  var length = Math.hypot(zx, zy, zz);
  zx /= length; zy /= length; zz /= length;
  var xx = up[1] * zz - up[2] * zy;
  var xy = up[2] * zx - up[0] * zz;
  var xz = up[0] * zy - up[1] * zx;
  length = Math.hypot(xx, xy, xz);
  xx /= length; xy /= length; xz /= length;
  var yx = zy * xz - zz * xy;
  var yy = zz * xx - zx * xz;
  var yz = zx * xy - zy * xx;

  out[0] = xx; out[1] = yx; out[2] = zx; out[3] = 0;
  out[4] = xy; out[5] = yy; out[6] = zy; out[7] = 0;
  out[8] = xz; out[9] = yz; out[10] = zz; out[11] = 0;
  out[12] = -(xx * eye[0] + xy * eye[1] + xz * eye[2]);
  out[13] = -(yx * eye[0] + yy * eye[1] + yz * eye[2]);
  out[14] = -(zx * eye[0] + zy * eye[1] + zz * eye[2]);
  out[15] = 1;
}

function multiply(out, a, b) {
  for (var column = 0; column < 4; ++column) {
    for (var row = 0; row < 4; ++row) {
      out[column * 4 + row] =
        a[row] * b[column * 4] +
        a[4 + row] * b[column * 4 + 1] +
        a[8 + row] * b[column * 4 + 2] +
        a[12 + row] * b[column * 4 + 3];
    }
  }
}
