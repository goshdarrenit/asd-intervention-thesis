"""Run all validation scenarios back to back and print a summary table."""
import asyncio
import json
import sys
import os
from datetime import datetime

# Allow running from backend/ or backend/scripts/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from validation.scenarios import SCENARIOS
from validation.runner import run_trial


async def main():
    results = []
    total = len(SCENARIOS)

    print(f"\nRunning {total} validation scenarios...\n")
    print("=" * 60)

    for i, scenario in enumerate(SCENARIOS, 1):
        sid = scenario["id"]
        print(f"[{i}/{total}] {sid} ... ", end="", flush=True)
        start = datetime.now()
        try:
            report = await run_trial(scenario)
            elapsed = (datetime.now() - start).seconds
            print(f"done ({elapsed}s) — mean={report.mean_score:.1f} -> {report.recommendation}")
            results.append({"scenario_id": sid, "report": report, "error": None})
        except Exception as exc:
            elapsed = (datetime.now() - start).seconds
            print(f"FAILED ({elapsed}s): {exc}")
            results.append({"scenario_id": sid, "report": None, "error": str(exc)})

    # Summary table
    print("\n" + "=" * 60)
    print(f"{'Scenario':<35} {'Mean':>5}  {'Rec':<8}  {'Flags'}")
    print("-" * 60)
    for r in results:
        if r["report"]:
            rep = r["report"]
            flags = len(rep.safety_flags)
            print(f"{r['scenario_id']:<35} {rep.mean_score:>5.1f}  {rep.recommendation:<8}  {flags} flag(s)")
        else:
            print(f"{r['scenario_id']:<35} {'ERR':>5}  {'failed':<8}")

    # Save full results to JSON
    out_path = os.path.join(os.path.dirname(__file__), "..", "data", "validation_results.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(
            [
                {
                    "scenario_id": r["scenario_id"],
                    "report": r["report"].model_dump() if r["report"] else None,
                    "error": r["error"],
                }
                for r in results
            ],
            f,
            indent=2,
        )
    print(f"\nFull results saved to: {os.path.abspath(out_path)}")


if __name__ == "__main__":
    asyncio.run(main())
