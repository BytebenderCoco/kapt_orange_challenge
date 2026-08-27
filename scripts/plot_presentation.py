#!/usr/bin/env python3
"""Generate the presentation charts (SVG) for the Orange ROADEF 2026 deck.

Reads the committed t0/t1 result JSONs and data/*.json and writes five SVGs
into presentation/assets/plots/, matching the deck's "Cartesian" palette
(ink / taupe / hairline) so they sit cleanly on the slides.

Charts:
  network_scale.svg   nodes / arcs / demands across all 20 setA instances (log y)
  benchmark_mlu.svg   t0 MLU per instance (optimal = solid ink, time-limit = outline)
  solve_time.svg      t0 CPU time vs instance (log y) + 900 s limit line
  t1_mlu.svg          grouped t0-nominal vs t1-combined MLU for setA-01/02/03
  load_profile.svg    sorted per-arc utilization after lexicographic descent (setA-01)

Data notes:
  - t0 benchmark + solve time come from the complete 900 s sweep run
    `20260826-080344` (14 instances).
  - t1 MLU is read from the *loadVector top* (the true final max utilization),
    not the `mlu` field, which for setA-02 reports a stale level-1 lambda (1.098
    vs the real 0.943).
  - the load profile uses `t0-overnight/01.json` (schema 1.4.0, has loadVector).

Usage:  python3 scripts/plot_presentation.py
"""

import glob
import json
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLOTS = os.path.join(ROOT, "presentation", "assets", "plots")
DATA = os.path.join(ROOT, "data")
T0_RUN = os.path.join(ROOT, "t0_results", "20260826-080344")
T1_RUN = os.path.join(ROOT, "t1_results", "t1-overnight")
T0_LEX = os.path.join(ROOT, "t0_results", "t0-overnight")

INK = "#000000"
GRAY = "#3C3C3C"
TAUPE = "#898989"
LINE = "#C9C9C9"
STONE2 = "#F1F5F9"
ACCENT = "#164194"

plt.rcParams.update({
    "font.family": "serif",
    "font.serif": ["Palatino", "DejaVu Serif", "serif"],
    "text.color": INK,
    "axes.edgecolor": LINE,
    "axes.labelcolor": INK,
    "xtick.color": TAUPE,
    "ytick.color": TAUPE,
    "axes.titlecolor": INK,
    "figure.facecolor": "white",
    "axes.facecolor": "white",
    "grid.color": STONE2,
    "grid.linewidth": 1,
    "axes.titleweight": "normal",
    "axes.titlelocation": "left",
    "savefig.bbox": "tight",
})


def index(name):
    m = None
    for m_ in __import__("re").finditer(r"\d+$", name):
        m = m_
    return int(m.group(0)) if m else 0


# ---------------------------------------------------------------------------
# Data readers
# ---------------------------------------------------------------------------

def read_run(run_dir):
    """Return a list of dicts sorted by instance index for one run directory."""
    rows = []
    for f in glob.glob(os.path.join(run_dir, "*.json")):
        doc = json.load(open(f))
        r = doc.get("results", {})
        rows.append({
            "instance": int(doc.get("instance") or index(f)),
            "vertices": r.get("vertices"),
            "links": r.get("links"),
            "demands": r.get("demands"),
            "status": r.get("status"),
            "mlu": r.get("mlu"),
            "lowerBound": r.get("lowerBound"),
            "gap": r.get("gap"),
            "cpuTime": r.get("cpuTime"),
        })
    rows.sort(key=lambda r: r["instance"])
    return rows


def load_vector_top(run_dir, instance):
    """Top (max) utilization from a result's loadVector, else the mlu field."""
    f = os.path.join(run_dir, "%02d.json" % instance)
    doc = json.load(open(f))
    r = doc.get("results", {})
    lv = r.get("loadVector")
    if lv:
        return max(e["util"] for e in lv)
    return r.get("mlu")


def instance_scale():
    """Nodes / links / demands per instance, from data/*-net.json and *-tm.json."""
    rows = []
    for net in sorted(glob.glob(os.path.join(DATA, "*-net.json"))):
        stem = os.path.basename(net)[:-len("-net.json")]
        d = json.load(open(net))
        tm = json.load(open(os.path.join(DATA, stem + "-tm.json")))
        rows.append({
            "instance": index(stem),
            "nodes": len(d["nodes"]),
            "links": len(d["links"]),
            "demands": len(tm["demands"]),
        })
    rows.sort(key=lambda r: r["instance"])
    return rows


# ---------------------------------------------------------------------------
# Charts
# ---------------------------------------------------------------------------

def make_network_scale():
    rows = instance_scale()
    xs = [r["instance"] for r in rows]
    labels = ["setA-%02d" % r["instance"] for r in rows]
    fig, ax = plt.subplots(figsize=(9, 4.8))
    ax.plot(xs, [r["nodes"] for r in rows], marker="o", ms=4, color=INK, lw=2, label="nodes")
    ax.plot(xs, [r["links"] for r in rows], marker="D", ms=4, color=GRAY, lw=2, label="arcs")
    ax.plot(xs, [r["demands"] for r in rows], marker="s", ms=4, color=TAUPE, lw=2, label="demands")
    ax.set_yscale("log")
    ax.set_xticks(xs)
    ax.set_xticklabels(labels, rotation=90, fontsize=7)
    ax.grid(True)
    ax.set_title("Set A instance scale (log scale)", fontsize=14)
    ax.set_xlabel("instance")
    ax.set_ylabel("count")
    ax.legend(frameon=False, fontsize=11, loc="center left", bbox_to_anchor=(1.01, 0.5))
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)
    fig.subplots_adjust(right=0.74)
    fig.savefig(os.path.join(PLOTS, "network_scale.svg"), bbox_inches="tight")
    plt.close(fig)


def make_benchmark_mlu():
    rows = read_run(T0_RUN)
    labels = ["setA-%02d" % r["instance"] for r in rows]
    heights, fills, outline = [], [], []
    for r in rows:
        y = r["mlu"] if r["mlu"] is not None else r["lowerBound"]
        heights.append(y if y is not None else 0.0)
        opt = r["status"] == "OPTIMAL"
        fills.append(INK if opt else LINE)
        outline.append(not opt)
    xs = list(range(len(rows)))
    fig, ax = plt.subplots(figsize=(9, 4.8))
    for x, h, c, o in zip(xs, heights, fills, outline):
        ax.bar(x, h, color="white" if o else c, edgecolor=c, linewidth=2,
               fill=not o, width=0.7)
    for x, r in enumerate(rows):
        if r["mlu"] is not None:
            if r["gap"] is not None and r["gap"] < 1e-4:
                ann = "gap 0%"
            elif r["gap"] is not None:
                ann = "gap %.0f%%" % round(100 * r["gap"])
            else:
                ann = ""
            if ann:
                ax.annotate(ann, (x, heights[x]), textcoords="offset points",
                            xytext=(0, 3), ha="center", va="bottom",
                            fontsize=8, color=GRAY)
        else:
            ax.annotate("time limit", (x, heights[x] + 0.02),
                        textcoords="offset points", xytext=(0, 3),
                        ha="center", va="bottom", fontsize=8, color=TAUPE)
    ax.set_xticks(xs)
    ax.set_xticklabels(labels, fontsize=8)
    ax.set_ylim(0, max(heights) * 1.28 + 0.05)
    ax.grid(True, axis="y")
    ax.set_title("Maximum link utilization — nominal period (t = 0)", fontsize=14)
    ax.set_ylabel("MLU  (λ*)")
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)
    fig.tight_layout()
    fig.savefig(os.path.join(PLOTS, "benchmark_mlu.svg"))
    plt.close(fig)


def make_solve_time():
    rows = read_run(T0_RUN)
    xs = [r["instance"] for r in rows]
    ys = [r["cpuTime"] or 0.0 for r in rows]
    ok = [r["status"] == "OPTIMAL" for r in rows]
    fig, ax = plt.subplots(figsize=(9, 4.8))
    ax.scatter([x for x, o in zip(xs, ok) if o], [y for y, o in zip(ys, ok) if o],
               color=INK, s=28, zorder=3, label="optimal")
    ax.scatter([x for x, o in zip(xs, ok) if not o], [y for y, o in zip(ys, ok) if not o],
               facecolors="white", edgecolors=LINE, linewidths=2, s=28, zorder=3,
               label="time limit")
    ax.axhline(900, color=GRAY, linestyle="--", linewidth=1.5, label="time limit (900 s)")
    ax.set_yscale("log")
    ax.set_xticks(xs)
    ax.set_xticklabels(["setA-%02d" % x for x in xs], fontsize=8)
    ax.grid(True, which="both")
    ax.set_title("Solve time vs instance size (log scale)", fontsize=14)
    ax.set_xlabel("instance index")
    ax.set_ylabel("CPU time (s)")
    ax.legend(frameon=False, fontsize=11, loc="center left", bbox_to_anchor=(1.01, 0.5))
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)
    fig.subplots_adjust(right=0.74)
    fig.savefig(os.path.join(PLOTS, "solve_time.svg"), bbox_inches="tight")
    plt.close(fig)


def make_t1_mlu():
    t0 = read_run(T0_RUN)
    t0_mlu = {r["instance"]: r["mlu"] for r in t0 if r["mlu"] is not None}
    instances = [1, 2, 3]
    labels = ["setA-%02d" % i for i in instances]
    nominal = [t0_mlu[i] for i in instances]
    maint = [load_vector_top(T1_RUN, i) for i in instances]
    x = list(range(len(instances)))
    w = 0.35
    fig, ax = plt.subplots(figsize=(9, 4.8))
    ax.bar([i - w / 2 for i in x], nominal, w, color=INK, label="nominal  (t = 0)")
    ax.bar([i + w / 2 for i in x], maint, w, color=ACCENT, label="maintenance  (t = 1)")
    for i in x:
        ax.annotate("%.2f" % nominal[i], (i - w / 2, nominal[i]),
                    textcoords="offset points", xytext=(0, 3), ha="center",
                    va="bottom", fontsize=8, color=GRAY)
        ax.annotate("%.2f" % maint[i], (i + w / 2, maint[i]),
                    textcoords="offset points", xytext=(0, 3), ha="center",
                    va="bottom", fontsize=8, color=GRAY)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=10)
    ax.set_ylim(0, max(nominal + maint) * 1.25)
    ax.grid(True, axis="y")
    ax.set_title("MLU — nominal vs maintenance (β(1) budget)", fontsize=14)
    ax.set_ylabel("MLU  (λ*)")
    ax.legend(frameon=False, fontsize=11, loc="center left", bbox_to_anchor=(1.01, 0.5))
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)
    fig.subplots_adjust(right=0.72)
    fig.savefig(os.path.join(PLOTS, "t1_mlu.svg"), bbox_inches="tight")
    plt.close(fig)


def make_load_profile():
    f = os.path.join(T0_LEX, "01.json")
    doc = json.load(open(f))
    lv = doc["results"]["loadVector"]
    utils = sorted((e["util"] for e in lv), reverse=True)
    fig, ax = plt.subplots(figsize=(9, 4.8))
    ax.plot(range(1, len(utils) + 1), utils, color=INK, lw=2)
    ax.axhline(utils[0], color=GRAY, linestyle="--", linewidth=1.2)
    ax.annotate("MLU = %.3f" % utils[0], (1, utils[0]), textcoords="offset points",
                xytext=(8, 4), fontsize=10, color=GRAY)
    ax.grid(True)
    ax.set_title("Sorted arc loads after lexicographic descent (setA-01, t = 0)", fontsize=14)
    ax.set_xlabel("rank (descending)")
    ax.set_ylabel("utilization  λ(a)")
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)
    fig.tight_layout()
    fig.savefig(os.path.join(PLOTS, "load_profile.svg"))
    plt.close(fig)


def main():
    os.makedirs(PLOTS, exist_ok=True)
    make_network_scale()
    make_benchmark_mlu()
    make_solve_time()
    make_t1_mlu()
    make_load_profile()
    print("wrote 5 charts to", PLOTS)


if __name__ == "__main__":
    main()
