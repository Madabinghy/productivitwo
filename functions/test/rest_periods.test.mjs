import test from "node:test";
import assert from "node:assert/strict";
import { parseRestPeriods, withRestSet, withRestLifted } from "../lib/rest_periods.js";

test("veille : poser, prolonger, lever (aligné sur rest_periods.dart)", () => {
  let p = withRestSet([], "sante", "2026-10-20", "2026-10-26");
  assert.deepEqual(p, [{ domainId: "sante", from: "2026-10-20", to: "2026-10-26" }]);
  p = withRestSet(p, "sante", "2026-10-22", "2026-10-30");
  assert.deepEqual(p, [{ domainId: "sante", from: "2026-10-20", to: "2026-10-30" }]);
  p = withRestLifted(p, "sante", "2026-10-24");
  assert.deepEqual(p, [{ domainId: "sante", from: "2026-10-20", to: "2026-10-23" }]);
  assert.deepEqual(withRestLifted(withRestSet([], "x", "2026-10-24", "2026-10-30"), "x", "2026-10-24"), []);
});

test("veille : jamais rétroactive, lecture tolérante", () => {
  assert.deepEqual(withRestSet([], "sante", "2026-10-20", "2026-10-19"), []);
  assert.deepEqual(
    parseRestPeriods([{ domainId: "a", from: "2026-10-01", to: "2026-10-03" }, { domainId: "b", from: "2026-10-05", to: "2026-10-01" }, "x"]),
    [{ domainId: "a", from: "2026-10-01", to: "2026-10-03" }],
  );
});
