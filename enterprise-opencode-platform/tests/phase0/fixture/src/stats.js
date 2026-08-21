// Two deliberate defects, both covered by test/stats.test.js:
//   1. even-length input returns the upper middle element instead of the mean
//   2. empty input returns undefined instead of throwing
export function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}
