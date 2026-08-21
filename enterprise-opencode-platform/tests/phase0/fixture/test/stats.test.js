import test from "node:test";
import assert from "node:assert/strict";
import { median } from "../src/stats.js";

test("odd length returns the middle element", () => {
  assert.equal(median([3, 1, 2]), 2);
});

test("even length averages the middle pair", () => {
  assert.equal(median([4, 1, 3, 2]), 2.5);
});

test("empty input throws", () => {
  assert.throws(() => median([]));
});
