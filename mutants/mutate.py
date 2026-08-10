#!/usr/bin/env python3
"""
mutants/mutate.py -- bug-injection (mutation testing) harness.

The point of this project's headline result: prove the testbench actually
*catches* bugs, not just that coverage is high. We do that by planting known
bugs ("mutants") into the DUT one at a time and checking whether the existing
tests turn red.

For each mutant we:
  1. copy rtl/apb_slave.sv into build/mut_<id>/apb_slave.sv,
  2. apply one textual edit (the seeded bug),
  3. rebuild + run the sim against the mutated DUT,
  4. read the UVM report summary to decide the outcome.

Outcomes:
  CAUGHT     -- sim ran and the testbench flagged it (UVM_ERROR/UVM_FATAL > 0).
                This is what we want.
  ESCAPED    -- sim passed clean. The bug slipped through -> a coverage hole in
                your tests. These are the interesting ones to explain.
  STILLBORN  -- the mutant didn't compile/elaborate. Excluded from the score
                (a mutant that breaks the build isn't a fair test of the TB).

Headline number = CAUGHT / (CAUGHT + ESCAPED).

Config: mutants/mutants.yaml  (see that file for the format and examples).
You add the seeded bugs; this runner just executes and tallies them.

Usage:
    python3 mutants/mutate.py                       # uses mutants/mutants.yaml
    python3 mutants/mutate.py --config other.yaml
    python3 mutants/mutate.py --only decode_off_by_one
    python3 mutants/mutate.py --test apb_random_test
    python3 mutants/mutate.py --keep                # keep build dirs for debug
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

import yaml

# Repo root = parent of this file's directory (mutants/..).
ROOT = Path(__file__).resolve().parent.parent
RTL_SLAVE = ROOT / "rtl" / "apb_slave.sv"
BUILD = ROOT / "build"

# UVM prints an end-of-run summary like:
#   UVM_ERROR :    0
#   UVM_FATAL :    0
RE_ERROR = re.compile(r"UVM_ERROR\s*:\s*(\d+)")
RE_FATAL = re.compile(r"UVM_FATAL\s*:\s*(\d+)")


@dataclass
class Mutant:
    id: str
    desc: str
    find: str
    replace: str
    regex: bool = False
    file: str = "rtl/apb_slave.sv"  # default DUT; allows mutating other files later


@dataclass
class Result:
    mutant: Mutant
    outcome: str          # CAUGHT | ESCAPED | STILLBORN
    errors: int = 0
    fatals: int = 0
    note: str = ""


def load_mutants(cfg_path: Path) -> list[Mutant]:
    data = yaml.safe_load(cfg_path.read_text()) or {}
    raw = data.get("mutants", [])
    if not raw:
        sys.exit(f"No mutants defined in {cfg_path}. Add some under 'mutants:'.")
    mutants = []
    for i, m in enumerate(raw):
        try:
            mutants.append(
                Mutant(
                    id=str(m["id"]),
                    desc=m.get("desc", ""),
                    find=m["find"],
                    replace=m["replace"],
                    regex=bool(m.get("regex", False)),
                    file=m.get("file", "rtl/apb_slave.sv"),
                )
            )
        except KeyError as e:
            sys.exit(f"Mutant #{i} is missing required key {e}.")
    return mutants


def apply_mutation(src_text: str, m: Mutant) -> str:
    """Return mutated text, or raise if the pattern isn't found / changes nothing."""
    if m.regex:
        new_text, n = re.subn(m.find, m.replace, src_text)
        if n == 0:
            raise ValueError(f"regex '{m.find}' matched nothing")
    else:
        if m.find not in src_text:
            raise ValueError(f"string '{m.find}' not found in source")
        new_text = src_text.replace(m.find, m.replace)
    if new_text == src_text:
        raise ValueError("mutation did not change the file (find == replace?)")
    return new_text


def run_sim(rtl_path: Path, obj_dir: Path, log_path: Path, test: str) -> tuple[bool, str]:
    """make run with the given DUT. Returns (build_ok, sim_log_text)."""
    cmd = [
        "make", "run",
        f"RTL_SLAVE={rtl_path}",
        f"OBJ_DIR={obj_dir}",
        f"SIM_LOG={log_path}",
        f"TEST={test}",
    ]
    proc = subprocess.run(
        cmd, cwd=ROOT, capture_output=True, text=True, timeout=900
    )
    combined = proc.stdout + proc.stderr
    # Prefer the sim log if make wrote one; otherwise use captured output.
    log_text = log_path.read_text() if log_path.exists() else combined
    build_ok = proc.returncode == 0
    return build_ok, log_text


def classify(build_ok: bool, log_text: str) -> tuple[str, int, int, str]:
    err = RE_ERROR.findall(log_text)
    fat = RE_FATAL.findall(log_text)
    errors = int(err[-1]) if err else 0
    fatals = int(fat[-1]) if fat else 0

    if not build_ok and not err and not fat:
        # make/verilator failed before the UVM summary was ever printed.
        return "STILLBORN", errors, fatals, "did not compile/elaborate"
    if errors > 0 or fatals > 0:
        return "CAUGHT", errors, fatals, ""
    # build ok, summary present, zero errors/fatals -> the bug went undetected.
    if not err and not fat:
        return "STILLBORN", errors, fatals, "no UVM summary found (hang/early exit?)"
    return "ESCAPED", errors, fatals, ""


def run_one(m: Mutant, test: str, keep: bool) -> Result:
    target = ROOT / m.file
    if not target.exists():
        return Result(m, "STILLBORN", note=f"source file {m.file} not found")

    mut_dir = BUILD / f"mut_{m.id}"
    if mut_dir.exists():
        shutil.rmtree(mut_dir)
    mut_dir.mkdir(parents=True)

    mutated_path = mut_dir / target.name
    try:
        mutated_path.write_text(apply_mutation(target.read_text(), m))
    except ValueError as e:
        return Result(m, "STILLBORN", note=f"could not apply mutation: {e}")

    try:
        build_ok, log_text = run_sim(
            mutated_path, mut_dir / "obj_dir", mut_dir / "sim.log", test
        )
    except subprocess.TimeoutExpired:
        return Result(m, "CAUGHT", note="timeout (likely a hang the watchdog tripped)")

    outcome, errors, fatals, note = classify(build_ok, log_text)
    if not keep:
        shutil.rmtree(mut_dir, ignore_errors=True)
    return Result(m, outcome, errors, fatals, note)


def run_baseline(test: str) -> bool:
    """The unmutated DUT must pass clean, else the score is meaningless."""
    print(">> baseline: building + running the UNMUTATED DUT ...")
    try:
        build_ok, log_text = run_sim(
            RTL_SLAVE, BUILD / "baseline" / "obj_dir",
            BUILD / "baseline" / "sim.log", test
        )
    except subprocess.TimeoutExpired:
        print("!! baseline TIMED OUT. The unmutated DUT must run clean before "
              "mutant results are meaningful.")
        return False
    outcome, errors, fatals, note = classify(build_ok, log_text)
    if outcome == "CAUGHT":
        print(f"!! baseline FAILS ({errors} errors, {fatals} fatals). The mutant "
              "score is only meaningful once the clean DUT passes.")
        return False
    if outcome == "STILLBORN":
        print(f"!! baseline did not produce a clean pass: {note}")
        return False
    print(">> baseline PASSED clean.\n")
    return True


def report(results: list[Result]) -> int:
    caught = [r for r in results if r.outcome == "CAUGHT"]
    escaped = [r for r in results if r.outcome == "ESCAPED"]
    stillborn = [r for r in results if r.outcome == "STILLBORN"]
    scored = len(caught) + len(escaped)

    print("\n" + "=" * 70)
    print("MUTATION TESTING REPORT")
    print("=" * 70)
    for r in results:
        tag = {"CAUGHT": "[CAUGHT ]", "ESCAPED": "[ESCAPED]", "STILLBORN": "[skip   ]"}[r.outcome]
        extra = f"  ({r.note})" if r.note else ""
        print(f"  {tag} {r.mutant.id:<24} {r.mutant.desc}{extra}")

    print("-" * 70)
    if scored:
        pct = 100.0 * len(caught) / scored
        print(f"  CAUGHT  {len(caught)} of {scored}  ({pct:.0f}% mutation score)")
    else:
        print("  No scorable mutants (all stillborn).")
    if stillborn:
        print(f"  ({len(stillborn)} stillborn / excluded -- did not compile or no-op)")

    if escaped:
        print("\n  ESCAPED mutants -- not detected by the testbench (indicates a")
        print("  stimulus, coverage, or checker gap):")
        for r in escaped:
            print(f"    - {r.mutant.id}: {r.mutant.desc}")
    print("=" * 70)

    # Non-zero exit if anything escaped, so this can gate CI later.
    return 1 if escaped else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="APB DUT mutation-testing harness.")
    ap.add_argument("--config", default=str(ROOT / "mutants" / "mutants.yaml"))
    ap.add_argument("--test", default="apb_base_test", help="UVM test to run")
    ap.add_argument("--only", help="run only the mutant with this id")
    ap.add_argument("--keep", action="store_true", help="keep build/mut_* dirs")
    ap.add_argument("--skip-baseline", action="store_true",
                    help="don't require the clean DUT to pass first (not recommended)")
    args = ap.parse_args()

    mutants = load_mutants(Path(args.config))
    if args.only:
        mutants = [m for m in mutants if m.id == args.only]
        if not mutants:
            sys.exit(f"No mutant with id '{args.only}'.")

    if not args.skip_baseline and not run_baseline(args.test):
        return 2

    results = []
    for i, m in enumerate(mutants, 1):
        print(f">> mutant {i}/{len(mutants)}: {m.id} -- {m.desc}")
        r = run_one(m, args.test, args.keep)
        print(f"   -> {r.outcome}" + (f" ({r.note})" if r.note else ""))
        results.append(r)

    return report(results)


if __name__ == "__main__":
    sys.exit(main())
