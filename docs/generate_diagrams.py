#!/usr/bin/env python3
"""
generate_diagrams.py — Hyperion Compute HPC architecture diagrams
Generates 6 SVG diagrams using only matplotlib (no graphviz CLI required).
Run from repo root: python3 docs/generate_diagrams.py
"""

from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Rectangle
import matplotlib.patheffects as patheffects
import numpy as np

# ---------------------------------------------------------------------------
# Color palette — Hyperion Compute dark sci-fi branding
# ---------------------------------------------------------------------------
BG         = '#0D1117'   # near-black background
BLUE       = '#58A6FF'   # electric blue primary accent
GREEN      = '#7EE787'   # neon green secondary
PURPLE     = '#D2A8FF'   # purple tertiary
ORANGE     = '#FFA657'   # orange compute/warning
TEXT       = '#E6EDF3'   # near-white text
DIM        = '#8B949E'   # dimmed gray
TEAL       = '#39D0D8'   # teal for pipelines

# Panel fills (very dark versions of accent colors)
PANEL_BLUE   = '#0D2137'
PANEL_GREEN  = '#0D2116'
PANEL_ORANGE = '#211608'
PANEL_PURPLE = '#1A0D2E'
PANEL_GRAY   = '#161B22'

# Panel borders
BORDER_BLUE   = '#1A4A7A'
BORDER_GREEN  = '#1A4A1A'
BORDER_ORANGE = '#4A2A0D'
BORDER_PURPLE = '#3A1A5A'
BORDER_GRAY   = '#30363D'

OUT_DIR = Path(__file__).parent / 'img'


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def _pe():
    """Path effects for text legibility."""
    return [patheffects.withStroke(linewidth=3, foreground=BG)]


def draw_box(ax, x, y, w, h, label, sublabel=None,
             color=PANEL_BLUE, text_color=TEXT, border_color=BORDER_BLUE,
             border_width=1.5, corner_radius=0.3, fontsize=9,
             label_family='sans-serif', bold=False):
    """Draw a rounded rectangle with centered label and optional sublabel."""
    box = FancyBboxPatch(
        (x, y), w, h,
        boxstyle=f"round,pad=0.05,rounding_size={corner_radius}",
        facecolor=color,
        edgecolor=border_color,
        linewidth=border_width,
        zorder=3
    )
    ax.add_patch(box)
    cy = y + h / 2
    if sublabel:
        cy = y + h * 0.62
    weight = 'bold' if bold else 'normal'
    ax.text(x + w / 2, cy, label,
            ha='center', va='center',
            color=text_color, fontsize=fontsize,
            fontfamily=label_family,
            fontweight=weight,
            zorder=4,
            path_effects=_pe())
    if sublabel:
        ax.text(x + w / 2, y + h * 0.3, sublabel,
                ha='center', va='center',
                color=DIM, fontsize=max(fontsize - 1.5, 6),
                fontfamily='monospace',
                zorder=4,
                path_effects=_pe())


def draw_arrow(ax, x1, y1, x2, y2, color=BLUE, style='->', linewidth=1.5,
               label=None, label_color=None, dashed=False, zorder=2):
    """Draw a connecting arrow between two points."""
    ls = '--' if dashed else '-'
    ax.annotate(
        '', xy=(x2, y2), xytext=(x1, y1),
        arrowprops=dict(
            arrowstyle=style,
            color=color,
            lw=linewidth,
            linestyle=ls,
            connectionstyle='arc3,rad=0.0'
        ),
        zorder=zorder
    )
    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        lc = label_color or DIM
        ax.text(mx, my, label, ha='center', va='bottom',
                color=lc, fontsize=7, fontfamily='sans-serif',
                zorder=5, path_effects=_pe())


def draw_panel(ax, x, y, w, h, title,
               fill_color=PANEL_BLUE, border_color=BORDER_BLUE,
               title_color=BLUE, fontsize=8.5):
    """Draw a labeled background panel / subgraph."""
    rect = Rectangle((x, y), w, h,
                      facecolor=fill_color,
                      edgecolor=border_color,
                      linewidth=1.2,
                      zorder=1)
    ax.add_patch(rect)
    ax.text(x + 0.12, y + h - 0.12, title,
            ha='left', va='top',
            color=title_color, fontsize=fontsize,
            fontfamily='monospace', fontweight='bold',
            zorder=2, path_effects=_pe())


def add_watermark(fig):
    """Add a small Hyperion Compute watermark to the bottom-right."""
    fig.text(0.99, 0.01, 'Hyperion Compute · UT Dallas',
             ha='right', va='bottom',
             color=DIM, fontsize=6.5,
             fontfamily='sans-serif',
             alpha=0.7)


def new_figure(title_text):
    """Create a new dark figure with the Hyperion branding title."""
    fig, ax = plt.subplots(figsize=(14, 9), facecolor=BG)
    ax.set_facecolor(BG)
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.set_xticks([])
    ax.set_yticks([])
    fig.text(0.5, 0.97, title_text,
             ha='center', va='top',
             color=BLUE, fontsize=13,
             fontfamily='monospace', fontweight='bold',
             path_effects=_pe())
    add_watermark(fig)
    return fig, ax


# ---------------------------------------------------------------------------
# Diagram 1 — System Architecture Overview
# ---------------------------------------------------------------------------

def draw_diagram_1(out_dir: Path):
    fig, ax = new_figure('HYPERION COMPUTE — System Architecture')
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 9)
    ax.set_aspect('equal')

    # ── Row 0 (top) : USER INTERFACE ──────────────────────────────────────
    draw_panel(ax, 0.2, 6.9, 10.5, 1.8, 'USER INTERFACE',
               PANEL_BLUE, BORDER_BLUE, BLUE)
    ui_items = [
        ('tjp-setup', 'one-time init'),
        ('tjp-launch', 'submit job'),
        ('tjp-batch', 'samplesheet'),
        ('labdata', 'metadata CLI'),
        ('tjp-test', 'smoke test'),
    ]
    bw = 1.8
    for i, (lbl, sub) in enumerate(ui_items):
        draw_box(ax, 0.35 + i * 2.05, 7.1, bw, 1.35, lbl, sub,
                 color='#0D2A4A', border_color=BLUE,
                 text_color=BLUE, fontsize=8, label_family='monospace')

    # ── Row 1 : EXECUTION ENGINE ───────────────────────────────────────────
    draw_panel(ax, 0.2, 5.0, 10.5, 1.65, 'EXECUTION ENGINE',
               PANEL_ORANGE, BORDER_ORANGE, ORANGE)
    draw_box(ax, 0.45, 5.2, 1.9, 1.2, 'SLURM', 'job scheduler',
             color='#2A1500', border_color=ORANGE, text_color=ORANGE,
             fontsize=9, label_family='monospace', bold=True)
    draw_box(ax, 2.7, 5.2, 3.8, 1.2, 'Apptainer + Nextflow',
             'container pipelines',
             color='#0D1E2E', border_color=BLUE, text_color=BLUE, fontsize=9)
    draw_box(ax, 6.75, 5.2, 3.8, 1.2, 'Native Tools',
             '10x Genomics — no container',
             color='#1E1200', border_color=ORANGE, text_color=ORANGE, fontsize=9)

    # ── Row 2 : PIPELINE LAYER ─────────────────────────────────────────────
    draw_panel(ax, 0.2, 2.85, 10.5, 1.9, 'PIPELINE LAYER',
               '#0D1E1E', '#1A3E3E', TEAL)
    draw_box(ax, 0.45, 3.05, 1.6, 1.45, 'addone', 'inline Python demo',
             color='#161E1E', border_color=DIM, text_color=DIM, fontsize=8)
    sub_items = [
        ('bulkrnaseq', 'STAR/DESeq2'),
        ('psoma', 'HISAT2/Trim'),
        ('virome', 'Kraken2'),
        ('sqanti3', 'long-read DAG'),
        ('wf-tx', 'EPI2ME ONT'),
    ]
    for i, (lbl, sub) in enumerate(sub_items):
        draw_box(ax, 2.3 + i * 1.42, 3.05, 1.28, 1.45, lbl, sub,
                 color='#0D1E2E', border_color=BLUE, text_color=BLUE, fontsize=7.5)
    native_items = [('cellranger', 'scRNA-seq'), ('spaceranger', 'spatial'),
                    ('xeniumranger', 'in situ')]
    for i, (lbl, sub) in enumerate(native_items):
        draw_box(ax, 9.45 + i * 1.12, 3.05, 1.05, 1.45, lbl, sub,
                 color='#1E1200', border_color=ORANGE, text_color=ORANGE, fontsize=7)

    # ── Row 3 (bottom) : STORAGE LAYER ────────────────────────────────────
    draw_panel(ax, 0.2, 0.55, 10.5, 2.05, 'STORAGE LAYER',
               PANEL_GRAY, BORDER_GRAY, DIM)
    draw_box(ax, 0.45, 0.75, 2.5, 1.55,
             '/groups/tprice/', 'shared repo — read-only',
             color='#161B22', border_color=DIM, text_color=DIM,
             fontsize=8, label_family='monospace')
    draw_box(ax, 3.2, 0.75, 2.5, 1.55,
             '/scratch/juno/$USER', 'ephemeral compute',
             color='#211608', border_color=ORANGE, text_color=ORANGE,
             fontsize=8, label_family='monospace')
    draw_box(ax, 6.0, 0.75, 2.5, 1.55,
             '/work/$USER', 'archived runs',
             color='#0D2116', border_color=GREEN, text_color=GREEN,
             fontsize=8, label_family='monospace')
    draw_box(ax, 8.7, 0.75, 2.0, 1.55,
             'Titan /store/', 'FUTURE — Titan NFS',
             color='#1A0D2E', border_color=PURPLE, text_color=PURPLE,
             fontsize=7.5, label_family='monospace')

    # ── Far right: METADATA panel ──────────────────────────────────────────
    draw_panel(ax, 11.0, 0.55, 2.75, 8.15, 'METADATA',
               PANEL_PURPLE, BORDER_PURPLE, PURPLE)
    draw_box(ax, 11.15, 6.9, 2.45, 1.3,
             'tjp-launch', 'writes PLR-xxxx.json',
             color='#150D2A', border_color=PURPLE, text_color=PURPLE,
             fontsize=8, label_family='monospace')
    draw_box(ax, 11.15, 4.85, 2.45, 1.55,
             'Local JSON', '/work/.../metadata/\npipeline_runs/',
             color='#150D2A', border_color=PURPLE, text_color=TEXT,
             fontsize=7.5, label_family='monospace')
    draw_box(ax, 11.15, 2.7, 2.45, 1.7,
             'Titan PostgreSQL', 'FUTURE\npipeline_runs table',
             color='#1A0D2E', border_color=PURPLE, text_color=PURPLE,
             fontsize=7.5, label_family='monospace')

    ax.text(12.37, 4.32, 'v  today', ha='center', va='center',
            color=GREEN, fontsize=7, path_effects=_pe())
    ax.text(12.37, 4.55, 'v  future', ha='center', va='center',
            color=PURPLE, fontsize=7, path_effects=_pe(), style='italic')
    draw_arrow(ax, 12.37, 6.9, 12.37, 6.42,
               color=PURPLE, linewidth=1.2)
    draw_arrow(ax, 12.37, 4.85, 12.37, 4.42,
               color=PURPLE, linewidth=1.2, dashed=True)

    # Vertical flow arrows (center of each layer)
    for y_top, y_bot in [(6.9, 6.65), (5.65, 5.0), (3.8, 2.85)]:
        draw_arrow(ax, 5.45, y_top, 5.45, y_bot,
                   color=DIM, linewidth=1.0)

    # rsync arrow between scratch and work
    draw_arrow(ax, 5.7, 1.52, 6.0, 1.52,
               color=GREEN, linewidth=1.2, label='rsync\nstage-out')

    plt.tight_layout(rect=[0, 0.02, 1, 0.95])
    _save(fig, out_dir, '01_system_architecture.svg')


# ---------------------------------------------------------------------------
# Diagram 2 — Single Pipeline Execution Flow (swimlane)
# ---------------------------------------------------------------------------

def draw_diagram_2(out_dir: Path):
    fig, ax = new_figure('HYPERION COMPUTE — Pipeline Execution Flow')
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 9)
    ax.set_aspect('equal')

    lane_labels = ['User', 'tjp-launch', 'SLURM', 'Container /\nPipeline', 'Stage-out']
    lane_colors = [PANEL_BLUE, PANEL_BLUE, PANEL_ORANGE, '#0D1E1E', PANEL_GREEN]
    lane_borders = [BORDER_BLUE, BORDER_BLUE, BORDER_ORANGE, '#1A3E3E', BORDER_GREEN]
    lane_title_colors = [BLUE, BLUE, ORANGE, TEAL, GREEN]
    lane_h = 1.45
    lane_y_starts = [7.2, 5.5, 3.8, 2.1, 0.45]

    for i, (lbl, fc, bc, tc) in enumerate(
            zip(lane_labels, lane_colors, lane_borders, lane_title_colors)):
        draw_panel(ax, 0.2, lane_y_starts[i], 13.5, lane_h,
                   lbl, fc, bc, tc, fontsize=8)

    # ── Lane 0: User ──────────────────────────────────────────────────────
    draw_box(ax, 0.55, 7.38, 2.2, 1.1, 'Edit config.yaml', None,
             color='#0D2137', border_color=BLUE, text_color=TEXT, fontsize=8)
    draw_box(ax, 3.3, 7.38, 2.6, 1.1, 'tjp-launch psoma', None,
             color='#0D2137', border_color=BLUE, text_color=BLUE,
             fontsize=8, label_family='monospace')

    # ── Lane 1: tjp-launch ────────────────────────────────────────────────
    lx = [0.55, 2.95, 5.55, 8.1, 10.7]
    launch_items = [
        ('Validate\nconfig', None),
        ('Create run dir\n/work/.../runs/\n20260405_143022/', None),
        ('Snapshot config\n+ manifest.json\n+ PLR-xxxx', None),
        ('sbatch submit\nJob ID: 12345', None),
        ('Register\nPLR-xxxx', None),
    ]
    for i, (lbl, sub) in enumerate(launch_items):
        draw_box(ax, lx[i], 5.65, 2.1, 1.15, lbl, sub,
                 color='#0D1E30', border_color=BLUE, text_color=TEXT,
                 fontsize=7.5)
    for i in range(len(lx) - 1):
        draw_arrow(ax, lx[i] + 2.1, 6.22, lx[i + 1], 6.22,
                   color=BLUE, linewidth=1.2)

    # ── Lane 2: SLURM ────────────────────────────────────────────────────
    slurm_items = [
        (0.55, 'Allocate\nnode'),
        (3.8, 'Set up\nenvironment'),
        (7.1, 'Run job\nscript'),
    ]
    for sx, lbl in slurm_items:
        draw_box(ax, sx, 3.95, 2.4, 1.1, lbl, None,
                 color='#211608', border_color=ORANGE, text_color=ORANGE,
                 fontsize=8)
    draw_arrow(ax, 2.95, 4.5, 3.8, 4.5, color=ORANGE, linewidth=1.2)
    draw_arrow(ax, 6.2, 4.5, 7.1, 4.5, color=ORANGE, linewidth=1.2)

    # ── Lane 3: Container / Pipeline ──────────────────────────────────────
    pipeline_items = [
        (0.55, 'Load\nApptainer SIF'),
        (3.5, 'Execute\nNextflow'),
        (6.5, 'Write outputs\nto /scratch/...'),
        (9.5, 'Pipeline\ncomplete'),
    ]
    for px, lbl in pipeline_items:
        draw_box(ax, px, 2.26, 2.5, 1.1, lbl, None,
                 color='#0D1E1E', border_color=TEAL, text_color=TEAL,
                 fontsize=8)
    for i in range(len(pipeline_items) - 1):
        x1 = pipeline_items[i][0] + 2.5
        x2 = pipeline_items[i + 1][0]
        draw_arrow(ax, x1, 2.81, x2, 2.81, color=TEAL, linewidth=1.2)

    # ── Lane 4: Stage-out ─────────────────────────────────────────────────
    stageout_items = [
        (0.55, 'rsync outputs/\n→ /work/.../outputs/'),
        (3.8, 'rsync inputs/\n→ /work/.../inputs/'),
        (7.1, 'Checksum\nverify'),
        (10.2, 'Archive\ncomplete'),
    ]
    for ssx, lbl in stageout_items:
        draw_box(ax, ssx, 0.6, 2.6, 1.1, lbl, None,
                 color='#0D2116', border_color=GREEN, text_color=GREEN,
                 fontsize=7.5)
    for i in range(len(stageout_items) - 1):
        x1 = stageout_items[i][0] + 2.6
        x2 = stageout_items[i + 1][0]
        draw_arrow(ax, x1, 1.15, x2, 1.15, color=GREEN, linewidth=1.2)

    # ── Vertical lane-crossing arrows ────────────────────────────────────
    # User → tjp-launch
    draw_arrow(ax, 4.6, 7.38, 4.6, 6.8, color=BLUE, linewidth=1.2)
    # tjp-launch → SLURM (sbatch)
    draw_arrow(ax, 9.15, 5.65, 9.15, 5.05, color=ORANGE, linewidth=1.2,
               label='sbatch')
    # SLURM → Container
    draw_arrow(ax, 8.3, 3.95, 8.3, 3.36, color=TEAL, linewidth=1.2)
    # Container → Stage-out
    draw_arrow(ax, 11.0, 2.26, 11.0, 1.7, color=GREEN, linewidth=1.2)

    # Timeline bar at the bottom
    ax.annotate('', xy=(13.5, 0.18), xytext=(0.4, 0.18),
                arrowprops=dict(arrowstyle='->', color=DIM, lw=1.5))
    ax.text(6.9, 0.06, 'TIME →', ha='center', va='bottom',
            color=DIM, fontsize=7.5, fontfamily='sans-serif',
            path_effects=_pe())

    plt.tight_layout(rect=[0, 0.02, 1, 0.95])
    _save(fig, out_dir, '02_execution_flow.svg')


# ---------------------------------------------------------------------------
# Diagram 3 — Pipeline Taxonomy
# ---------------------------------------------------------------------------

def draw_diagram_3(out_dir: Path):
    fig, ax = new_figure('HYPERION COMPUTE — Pipeline Taxonomy')
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 9)
    ax.set_aspect('equal')

    # Root
    rx, ry, rw, rh = 4.7, 7.8, 4.6, 0.9
    draw_box(ax, rx, ry, rw, rh, 'Hyperion Compute Pipelines',
             color='#0D2137', border_color=BLUE, text_color=BLUE,
             fontsize=11, bold=True)
    root_cx = rx + rw / 2
    root_by = ry  # bottom y

    # Branch roots
    branches = [
        (1.0,  'INLINE',   DIM,    PANEL_GRAY,   BORDER_GRAY),
        (5.4,  'SUBMODULED\nNextflow + Apptainer', BLUE, PANEL_BLUE, BORDER_BLUE),
        (11.2, 'NATIVE\n10x Genomics', ORANGE, PANEL_ORANGE, BORDER_ORANGE),
    ]
    branch_centers = []
    for bx, lbl, tc, fc, bc in branches:
        bw = 2.5 if 'NATIVE' not in lbl and 'INLINE' not in lbl else 2.0
        if 'NATIVE' in lbl:
            bw = 2.5
        draw_box(ax, bx, 6.3, bw, 1.0, lbl,
                 color=fc, border_color=bc, text_color=tc,
                 fontsize=9, bold=True, label_family='monospace')
        branch_centers.append(bx + bw / 2)

    # Connector lines from root to branches
    for bcx in branch_centers:
        ax.plot([root_cx, bcx], [root_by, 7.3],
                color=DIM, linewidth=1.0, linestyle='--', zorder=1)

    # ── Inline leaves ─────────────────────────────────────────────────────
    draw_box(ax, 0.5, 4.5, 2.5, 1.1, 'addone',
             'Python demo\ninput→output+1',
             color=PANEL_GRAY, border_color=DIM, text_color=DIM,
             fontsize=8)
    ax.plot([2.0, 2.0], [6.3, 5.6], color=DIM, lw=1.0, ls='--', zorder=1)
    _badge(ax, 1.75, 4.5, 'Python', DIM, '#161B22')

    # ── Submoduled leaves ─────────────────────────────────────────────────
    # Sub-group labels
    ax.text(5.0, 6.0, 'Short-read RNA-seq', color=BLUE, fontsize=7.5,
            ha='left', fontfamily='sans-serif',
            path_effects=_pe())
    ax.text(7.8, 6.0, 'Long-read', color=PURPLE, fontsize=7.5,
            ha='left', fontfamily='sans-serif',
            path_effects=_pe())

    short_leaves = [
        ('bulkrnaseq', 'STAR/DESeq2', BLUE),
        ('psoma',      'HISAT2/Trim', BLUE),
        ('virome',     'Kraken2/\nMetaPhlAn3', BLUE),
    ]
    for i, (lbl, sub, tc) in enumerate(short_leaves):
        lx = 4.2 + i * 1.35
        draw_box(ax, lx, 4.45, 1.2, 1.25, lbl, sub,
                 color=PANEL_BLUE, border_color=BORDER_BLUE,
                 text_color=tc, fontsize=7.5)
        ax.plot([lx + 0.6, 6.65], [5.7, 6.3],
                color=BLUE, lw=0.8, ls='--', zorder=1)
        _badge(ax, lx + 0.02, 4.45, 'Nextflow', BLUE, PANEL_BLUE)

    long_leaves = [
        ('sqanti3',        'SQANTI3 v5.5\n4-stage DAG', PURPLE),
        ('wf-transcriptomes', 'EPI2ME ONT\nlong-read', PURPLE),
    ]
    for i, (lbl, sub, tc) in enumerate(long_leaves):
        lx = 7.6 + i * 1.55
        draw_box(ax, lx, 4.45, 1.35, 1.25, lbl, sub,
                 color=PANEL_PURPLE, border_color=BORDER_PURPLE,
                 text_color=tc, fontsize=7.5)
        ax.plot([lx + 0.675, 6.65], [5.7, 6.3],
                color=PURPLE, lw=0.8, ls='--', zorder=1)
        badge_lbl = 'SLURM DAG' if 'sqanti3' in lbl else 'Nextflow'
        _badge(ax, lx + 0.02, 4.45, badge_lbl, PURPLE, PANEL_PURPLE)

    # ── Native leaves ──────────────────────────────────────────────────────
    native_leaves = [
        ('cellranger',    'scRNA-seq\n10x Chromium'),
        ('spaceranger',   'Spatial\n10x Visium'),
        ('xeniumranger',  'In Situ\n10x Xenium'),
    ]
    for i, (lbl, sub) in enumerate(native_leaves):
        lx = 10.05 + i * 1.28
        draw_box(ax, lx, 4.45, 1.15, 1.25, lbl, sub,
                 color=PANEL_ORANGE, border_color=BORDER_ORANGE,
                 text_color=ORANGE, fontsize=7.5)
        ax.plot([lx + 0.575, 12.45], [5.7, 6.3],
                color=ORANGE, lw=0.8, ls='--', zorder=1)
        _badge(ax, lx + 0.02, 4.45, 'Native Bin', ORANGE, PANEL_ORANGE)

    # ── Legend ────────────────────────────────────────────────────────────
    legend_y = 3.3
    legend_items = [
        (DIM,    PANEL_GRAY,   BORDER_GRAY,   'Inline'),
        (BLUE,   PANEL_BLUE,   BORDER_BLUE,   'Submoduled (short-read)'),
        (PURPLE, PANEL_PURPLE, BORDER_PURPLE, 'Submoduled (long-read)'),
        (ORANGE, PANEL_ORANGE, BORDER_ORANGE, 'Native 10x'),
    ]
    ax.text(1.0, legend_y + 0.55, 'Legend:', color=DIM, fontsize=8,
            fontfamily='sans-serif', path_effects=_pe())
    for i, (tc, fc, bc, lbl) in enumerate(legend_items):
        lx = 1.0 + i * 3.1
        draw_box(ax, lx, legend_y - 0.05, 2.7, 0.5, lbl,
                 color=fc, border_color=bc, text_color=tc, fontsize=7.5)

    # Execution engine note
    ax.text(7.0, 2.5, 'Execution Engines:  '
            'Nextflow (Submoduled)  ·  SLURM DAG (sqanti3)  ·  Native Binary (10x)',
            ha='center', va='center', color=DIM, fontsize=8,
            fontfamily='sans-serif', path_effects=_pe())

    plt.tight_layout(rect=[0, 0.02, 1, 0.95])
    _save(fig, out_dir, '03_pipeline_taxonomy.svg')


def _badge(ax, x, y, text, tc, fc):
    """Draw a small badge at top-left of a box."""
    bx = FancyBboxPatch((x + 0.04, y + 0.85), 0.72, 0.28,
                        boxstyle='round,pad=0.03,rounding_size=0.06',
                        facecolor=fc, edgecolor=tc, linewidth=0.8, zorder=5)
    ax.add_patch(bx)
    ax.text(x + 0.04 + 0.36, y + 0.85 + 0.14, text,
            ha='center', va='center',
            color=tc, fontsize=5.5, fontfamily='monospace',
            zorder=6, path_effects=_pe())


# ---------------------------------------------------------------------------
# Diagram 4 — Filesystem Layout
# ---------------------------------------------------------------------------

def draw_diagram_4(out_dir: Path):
    fig, ax = new_figure('HYPERION COMPUTE — Filesystem Layout (Juno HPC)')
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 9)
    ax.set_aspect('equal')

    def tree_item(ax, x, y, text, indent=0, color=TEXT, fs=7.8,
                  icon='', mono=False):
        prefix = '│   ' * indent + ('├── ' if indent > 0 else '')
        full = prefix + icon + text
        ff = 'monospace' if mono else 'sans-serif'
        ax.text(x, y, full, ha='left', va='top',
                color=color, fontsize=fs, fontfamily=ff,
                path_effects=_pe(), zorder=4)

    # Panel 1 — Shared repo (blue tint)
    draw_panel(ax, 0.2, 1.5, 4.1, 7.0,
               '/groups/tprice/pipelines/   [SHARED]',
               PANEL_BLUE, BORDER_BLUE, BLUE, fontsize=7.5)
    items_shared = [
        (0, '[d] bin/', BLUE),
        (1, 'tjp-launch', TEXT),
        (1, 'tjp-batch', TEXT),
        (1, 'labdata', TEXT),
        (1, '[d] lib/', DIM),
        (0, '[d] templates/', BLUE),
        (1, '<pipeline>/config.yaml', TEXT),
        (0, '[d] containers/', BLUE),
        (1, 'bulkrnaseq/  [submodule]', TEXT),
        (1, 'psoma/       [submodule]', TEXT),
        (1, '10x/         [submodule]', TEXT),
        (1, 'sqanti3/     [submodule]', TEXT),
        (0, '[d] slurm_templates/', BLUE),
        (1, '<pipeline>_slurm_template.sh', TEXT),
        (0, '[d] pipelines/', BLUE),
        (1, 'addone/', TEXT),
        (0, '[d] references/', BLUE),
        (1, 'GRCh38, Gencode GTF', DIM),
        (0, '[d] metadata/', BLUE),
        (1, 'SCHEMA.md', DIM),
    ]
    y = 8.15
    for indent, lbl, col in items_shared:
        tree_item(ax, 0.35, y, lbl, indent=indent, color=col, fs=7.0, mono=True)
        y -= 0.33

    # Panel 2 — Work (green tint)
    draw_panel(ax, 4.65, 1.5, 4.4, 7.0,
               '/work/$USER/pipelines/   [ARCHIVED]',
               PANEL_GREEN, BORDER_GREEN, GREEN, fontsize=7.5)
    items_work = [
        (0, '[d] <pipeline>/', GREEN),
        (1, '[d] runs/', TEXT),
        (2, '[d] <timestamp>/', GREEN),
        (3, 'config.yaml  [snapshot]', TEXT),
        (3, 'manifest.json', TEXT),
        (3, 'titan_metadata.json', TEXT),
        (3, '[d] inputs/', DIM),
        (4, "rsync'd FASTQs", DIM),
        (3, '[d] outputs/', GREEN),
        (4, "rsync'd results", TEXT),
        (3, '[d] logs/', DIM),
        (4, 'slurm.out / slurm.err', DIM),
        (0, '[d] metadata/', GREEN),
        (1, '[d] pipeline_runs/', TEXT),
        (2, 'PLR-xxxx.json', GREEN),
    ]
    y = 8.15
    for indent, lbl, col in items_work:
        tree_item(ax, 4.8, y, lbl, indent=indent, color=col, fs=7.0, mono=True)
        y -= 0.38

    # Panel 3 — Scratch (orange tint)
    draw_panel(ax, 9.35, 1.5, 4.4, 7.0,
               '/scratch/juno/$USER/   [EPHEMERAL]',
               PANEL_ORANGE, BORDER_ORANGE, ORANGE, fontsize=7.5)
    ax.text(9.5, 5.1, '** wiped after stage-out',
            color=ORANGE, fontsize=7, ha='left',
            fontfamily='sans-serif', path_effects=_pe(), zorder=4)
    items_scratch = [
        (0, '[d] pipelines/', ORANGE),
        (1, '[d] <pipeline>/', TEXT),
        (2, '[d] runs/', TEXT),
        (3, '[d] <timestamp>/', ORANGE),
        (4, '(same timestamp as work)', DIM),
        (4, '[d] 2_trim_output/', TEXT),
        (4, '[d] 3_hisat2_mapping/', TEXT),
        (4, '[d] 4_filter_output/', TEXT),
        (4, '[d] 5_stringtie/', TEXT),
        (4, '[d] 6_raw_counts/', TEXT),
        (4, '*.sorted.bam', DIM),
        (4, 'raw_htseq_counts.csv', DIM),
    ]
    y = 8.15
    for indent, lbl, col in items_scratch:
        tree_item(ax, 9.5, y, lbl, indent=indent, color=col, fs=7.0, mono=True)
        y -= 0.41

    # Future Titan box at the bottom
    draw_panel(ax, 2.5, 0.15, 9.0, 1.1,
               'Future: /store/<project>/   [TITAN NFS — COMING SOON]',
               PANEL_PURPLE, BORDER_PURPLE, PURPLE, fontsize=8)
    ax.text(7.0, 0.55, '/store/<project>/runs/  ·  /store/<project>/refs/',
            ha='center', va='center', color=PURPLE, fontsize=7.5,
            fontfamily='monospace', path_effects=_pe(), zorder=4)

    # Connecting arrows
    # scratch → rsync → work
    draw_arrow(ax, 9.35, 4.2, 9.05, 4.2,
               color=GREEN, linewidth=1.5, label='rsync\nstage-out')
    # shared repo → templates → work
    draw_arrow(ax, 4.3, 6.5, 4.65, 6.5,
               color=BLUE, linewidth=1.2, label='config\ntemplates')
    # work → future titan
    draw_arrow(ax, 6.85, 1.5, 6.85, 1.25,
               color=PURPLE, linewidth=1.0, dashed=True)

    plt.tight_layout(rect=[0, 0.02, 1, 0.95])
    _save(fig, out_dir, '04_filesystem_layout.svg')


# ---------------------------------------------------------------------------
# Diagram 5 — Titan Integration Roadmap
# ---------------------------------------------------------------------------

def draw_diagram_5(out_dir: Path):
    fig, ax = new_figure('HYPERION COMPUTE — Titan Integration Roadmap')
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 9)
    ax.set_aspect('equal')

    # Background halves
    rect_left = Rectangle((0.15, 0.4), 6.5, 8.2,
                           facecolor=PANEL_BLUE, edgecolor=BORDER_BLUE,
                           linewidth=1.0, zorder=1)
    rect_right = Rectangle((7.35, 0.4), 6.5, 8.2,
                            facecolor=PANEL_PURPLE, edgecolor=BORDER_PURPLE,
                            linewidth=1.0, zorder=1)
    ax.add_patch(rect_left)
    ax.add_patch(rect_right)

    # Phase labels
    ax.text(3.4, 8.35, 'PHASE 1: TODAY (v6.0.0)',
            ha='center', va='center', color=GREEN,
            fontsize=10, fontfamily='monospace', fontweight='bold',
            path_effects=_pe(), zorder=3)
    ax.text(10.6, 8.35, 'PHASE 2: TITAN ONLINE (~6 months)',
            ha='center', va='center', color=PURPLE,
            fontsize=10, fontfamily='monospace', fontweight='bold',
            path_effects=_pe(), zorder=3)

    # Center divider
    ax.plot([6.95, 6.95], [0.5, 8.55], color=DIM, linewidth=1.5,
            linestyle='--', zorder=2)
    ax.text(6.95, 4.6, 'Same labdata\ninterface',
            ha='center', va='center', color=TEXT, fontsize=7.5,
            fontfamily='sans-serif', rotation=90,
            path_effects=_pe(), zorder=3)
    ax.text(6.95, 6.2, 'Zero-migration\nfor users',
            ha='center', va='center', color=GREEN, fontsize=7,
            fontfamily='sans-serif', rotation=90,
            path_effects=_pe(), zorder=3)
    ax.text(6.95, 3.0, 'Backend\nswap only',
            ha='center', va='center', color=PURPLE, fontsize=7,
            fontfamily='sans-serif', rotation=90,
            path_effects=_pe(), zorder=3)

    # ── Phase 1 (left) ──────────────────────────────────────────────────
    # tjp-launch box
    draw_box(ax, 0.8, 7.15, 2.8, 0.85, 'tjp-launch',
             'submits job + calls labdata',
             color='#0D2137', border_color=BLUE, text_color=BLUE,
             fontsize=9, label_family='monospace')
    draw_arrow(ax, 2.2, 7.15, 2.2, 6.45, color=BLUE, linewidth=1.2)

    # labdata CLI
    draw_box(ax, 0.8, 5.65, 2.8, 0.75, 'labdata register-run',
             'writes local JSON',
             color='#0D2137', border_color=BLUE, text_color=TEXT,
             fontsize=8.5, label_family='monospace')
    draw_arrow(ax, 2.2, 5.65, 2.2, 4.95, color=BLUE, linewidth=1.2)

    # Local JSON box with fields
    draw_box(ax, 0.5, 3.5, 5.7, 1.35, 'Local JSON — PLR-xxxx.json',
             color='#0D1E30', border_color=BLUE, text_color=BLUE,
             fontsize=9, bold=True)
    json_fields = [
        '  pipeline: "psoma"',
        '  status: "completed"',
        '  slurm_job_id: 12345',
        '  titan_registered: false',
    ]
    for i, fld in enumerate(json_fields):
        ax.text(0.65, 4.72 - i * 0.27, fld,
                color=GREEN, fontsize=7.5, fontfamily='monospace',
                path_effects=_pe(), zorder=4)

    # Work dir arrow
    draw_arrow(ax, 2.2, 3.5, 2.2, 2.7, color=BLUE, linewidth=1.2)
    draw_box(ax, 0.5, 1.85, 5.7, 0.8,
             '/work/$USER/pipelines/metadata/pipeline_runs/',
             color='#0D1E30', border_color=BORDER_BLUE,
             text_color=DIM, fontsize=7.5, label_family='monospace')

    # ── Phase 2 (right) ──────────────────────────────────────────────────
    draw_box(ax, 7.7, 7.15, 2.8, 0.85, 'tjp-launch',
             'submits job + calls labdata',
             color='#1A0D2E', border_color=PURPLE, text_color=PURPLE,
             fontsize=9, label_family='monospace')
    draw_arrow(ax, 9.1, 7.15, 9.1, 6.45, color=PURPLE, linewidth=1.2)

    draw_box(ax, 7.7, 5.65, 2.8, 0.75, 'labdata register-run',
             'writes to PostgreSQL',
             color='#1A0D2E', border_color=PURPLE, text_color=TEXT,
             fontsize=8.5, label_family='monospace')
    draw_arrow(ax, 9.1, 5.65, 9.1, 4.95, color=PURPLE, linewidth=1.2)

    # PostgreSQL box
    draw_box(ax, 7.5, 3.5, 6.0, 1.35, 'Titan PostgreSQL DB',
             color='#1A0D2E', border_color=PURPLE, text_color=PURPLE,
             fontsize=9, bold=True)
    pg_fields = [
        '  pipeline_runs  (table)',
        '  sample_metadata  (table)',
        '  project_registry  (table)',
        '  titan_registered: true',
    ]
    for i, fld in enumerate(pg_fields):
        ax.text(7.65, 4.72 - i * 0.27, fld,
                color=PURPLE, fontsize=7.5, fontfamily='monospace',
                path_effects=_pe(), zorder=4)

    draw_arrow(ax, 9.1, 3.5, 9.1, 2.7, color=PURPLE, linewidth=1.2)
    draw_box(ax, 7.5, 1.85, 6.0, 0.8,
             '/store/<project>/   [Titan NFS]',
             color='#1A0D2E', border_color=BORDER_PURPLE,
             text_color=DIM, fontsize=8, label_family='monospace')

    # ── Timeline bar ─────────────────────────────────────────────────────
    tl_y = 1.0
    ax.annotate('', xy=(13.5, tl_y), xytext=(0.5, tl_y),
                arrowprops=dict(arrowstyle='->', color=DIM, lw=1.5))
    milestones = [
        (1.5,  'v6.0.0\n(TODAY)',         GREEN),
        (4.5,  'Hardware\nProvisioning',  DIM),
        (7.5,  'Titan\nOnline',           PURPLE),
        (10.5, 'DB\nMigration',           PURPLE),
        (13.0, 'Full\nIntegration',       PURPLE),
    ]
    for mx, mlbl, mc in milestones:
        ax.plot([mx, mx], [tl_y - 0.08, tl_y + 0.08],
                color=mc, linewidth=2, zorder=3)
        ax.text(mx, tl_y - 0.25, mlbl,
                ha='center', va='top', color=mc,
                fontsize=7, fontfamily='sans-serif',
                path_effects=_pe())

    plt.tight_layout(rect=[0, 0.02, 1, 0.95])
    _save(fig, out_dir, '05_titan_roadmap.svg')


# ---------------------------------------------------------------------------
# Diagram 6 — Batch Execution Workflow
# ---------------------------------------------------------------------------

def draw_diagram_6(out_dir: Path):
    fig, ax = new_figure('HYPERION COMPUTE — Batch Execution Workflow')
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 9)
    ax.set_aspect('equal')

    cx = 7.0  # horizontal center

    # ── Top: samplesheet input ────────────────────────────────────────────
    draw_box(ax, cx - 1.6, 8.05, 3.2, 0.75,
             'samplesheet.csv',
             color='#0D2116', border_color=GREEN, text_color=GREEN,
             fontsize=9.5, label_family='monospace', bold=True)
    draw_arrow(ax, cx, 8.05, cx, 7.45, color=BLUE, linewidth=1.5)

    # tjp-batch command
    draw_box(ax, cx - 3.4, 6.65, 6.8, 0.75,
             'tjp-batch <pipeline> samplesheet.csv [--config base.yaml]',
             color='#0D2137', border_color=BLUE, text_color=BLUE,
             fontsize=8.5, label_family='monospace')
    draw_arrow(ax, cx, 6.65, cx, 6.05, color=BLUE, linewidth=1.5)

    # Validate + Load
    draw_box(ax, cx - 2.5, 5.25, 2.2, 0.72, 'Validate\nsamplesheet',
             color='#0D2137', border_color=BLUE, text_color=TEXT, fontsize=8.5)
    draw_box(ax, cx + 0.3, 5.25, 2.2, 0.72, 'Load base\nconfig',
             color='#0D2137', border_color=BLUE, text_color=TEXT, fontsize=8.5)
    draw_arrow(ax, cx - 0.3, 5.61, cx + 0.3, 5.61,
               color=BLUE, linewidth=1.2)
    draw_arrow(ax, cx, 6.05, cx - 1.4, 5.97, color=BLUE, linewidth=1.2)
    draw_arrow(ax, cx + 1.4, 5.25, cx + 1.4, 4.65, color=BLUE, linewidth=1.2)

    # Decision diamond
    diamond_cx, diamond_cy = cx, 4.3
    dw, dh = 1.6, 0.7
    diamond = plt.Polygon(
        [[diamond_cx, diamond_cy + dh / 2],
         [diamond_cx + dw / 2, diamond_cy],
         [diamond_cx, diamond_cy - dh / 2],
         [diamond_cx - dw / 2, diamond_cy]],
        facecolor='#0D2137', edgecolor=ORANGE, linewidth=1.5, zorder=3
    )
    ax.add_patch(diamond)
    ax.text(diamond_cx, diamond_cy, 'Batch\nMode?',
            ha='center', va='center', color=ORANGE,
            fontsize=8, fontfamily='sans-serif',
            fontweight='bold', zorder=4, path_effects=_pe())

    # ── Left branch: Per-Row ──────────────────────────────────────────────
    draw_panel(ax, 0.2, 0.45, 5.7, 3.55,
               'PER-ROW — One Job per Sample',
               PANEL_ORANGE, BORDER_ORANGE, ORANGE, fontsize=8)
    ax.text(0.4, 3.55, 'cellranger · spaceranger · xeniumranger · sqanti3 · wf-tx',
            color=ORANGE, fontsize=6.5, ha='left',
            fontfamily='monospace', path_effects=_pe(), zorder=3)

    row_items = [
        ('Row 1', 'SLURM Job #1'),
        ('Row 2', 'SLURM Job #2'),
        ('Row N', 'SLURM Job #N'),
    ]
    row_ys = [3.1, 2.4, 1.7]
    for (row_lbl, job_lbl), ry in zip(row_items, row_ys):
        draw_box(ax, 0.4, ry, 1.0, 0.55, row_lbl,
                 color='#211608', border_color=ORANGE,
                 text_color=ORANGE, fontsize=7.5)
        draw_box(ax, 1.65, ry, 1.3, 0.55, 'gen\nconfig',
                 color='#211608', border_color=DIM,
                 text_color=DIM, fontsize=7.5)
        draw_box(ax, 3.2, ry, 1.3, 0.55, 'tjp-launch',
                 color='#211608', border_color=ORANGE,
                 text_color=ORANGE, fontsize=7.5, label_family='monospace')
        draw_box(ax, 4.75, ry, 1.0, 0.55, job_lbl,
                 color='#211608', border_color=ORANGE,
                 text_color=TEXT, fontsize=7)
        draw_arrow(ax, 1.4, ry + 0.275, 1.65, ry + 0.275,
                   color=ORANGE, linewidth=1.0)
        draw_arrow(ax, 2.95, ry + 0.275, 3.2, ry + 0.275,
                   color=ORANGE, linewidth=1.0)
        draw_arrow(ax, 4.5, ry + 0.275, 4.75, ry + 0.275,
                   color=ORANGE, linewidth=1.0)

    ax.text(2.95, 1.15, 'N parallel jobs →',
            ha='center', va='center', color=ORANGE,
            fontsize=8.5, fontfamily='sans-serif',
            fontweight='bold', path_effects=_pe(), zorder=3)

    # Arrow from diamond to left
    draw_arrow(ax, diamond_cx - dw / 2, diamond_cy, 5.9, diamond_cy,
               color=ORANGE, linewidth=1.3)
    ax.text(4.7, 4.4, 'Per-Row', ha='center', va='bottom',
            color=ORANGE, fontsize=7.5, path_effects=_pe())

    # ── Right branch: Per-Sheet ───────────────────────────────────────────
    draw_panel(ax, 8.1, 0.45, 5.7, 3.55,
               'PER-SHEET — One Job for All',
               PANEL_BLUE, BORDER_BLUE, BLUE, fontsize=8)
    ax.text(8.3, 3.55, 'bulkrnaseq · psoma · virome',
            color=BLUE, fontsize=6.5, ha='left',
            fontfamily='monospace', path_effects=_pe(), zorder=3)

    draw_box(ax, 8.3, 2.6, 1.8, 0.7, 'All rows →\ngen samplesheet',
             color='#0D1E30', border_color=BLUE,
             text_color=TEXT, fontsize=7.5)
    draw_box(ax, 10.35, 2.6, 1.3, 0.7, 'tjp-launch',
             color='#0D1E30', border_color=BLUE,
             text_color=BLUE, fontsize=8, label_family='monospace')
    draw_box(ax, 11.9, 2.6, 1.7, 0.7, 'SLURM\nJob #1',
             color='#0D1E30', border_color=BLUE,
             text_color=TEXT, fontsize=8)

    draw_arrow(ax, 10.1, 2.95, 10.35, 2.95, color=BLUE, linewidth=1.2)
    draw_arrow(ax, 11.65, 2.95, 11.9, 2.95, color=BLUE, linewidth=1.2)

    # Nextflow fan-out
    draw_arrow(ax, 12.75, 2.6, 12.75, 2.1, color=BLUE, linewidth=1.2)
    nf_items = [('Sample 1', 1.45), ('Sample 2', 1.75), ('Sample N', 2.05)]
    nf_base_x = 11.0
    for lbl, nf_y in nf_items:
        draw_box(ax, nf_base_x, 2.6 - nf_y, 3.5, 0.4, f'Nextflow → {lbl}',
                 color='#0D1E30', border_color=TEAL,
                 text_color=TEAL, fontsize=7)
        ax.plot([12.75, nf_base_x + 1.75], [2.1, 2.6 - nf_y + 0.4],
                color=TEAL, lw=0.9, ls='--', zorder=2)

    ax.text(12.75, 0.88, '1 job, N samples →',
            ha='center', va='center', color=BLUE,
            fontsize=8.5, fontfamily='sans-serif',
            fontweight='bold', path_effects=_pe(), zorder=3)

    # Arrow from diamond to right
    draw_arrow(ax, diamond_cx + dw / 2, diamond_cy, 8.1, diamond_cy,
               color=BLUE, linewidth=1.3)
    ax.text(9.2, 4.4, 'Per-Sheet', ha='center', va='bottom',
            color=BLUE, fontsize=7.5, path_effects=_pe())

    # ── Convergence at bottom ─────────────────────────────────────────────
    draw_arrow(ax, 2.95, 0.45, 2.95, 0.25, color=DIM, linewidth=1.0)
    draw_arrow(ax, 11.0, 0.45, 11.0, 0.25, color=DIM, linewidth=1.0)
    draw_box(ax, cx - 2.8, 0.05, 5.6, 0.62,
             'PLR-xxxx metadata per job  →  labdata find runs',
             color='#0D1A10', border_color=GREEN, text_color=GREEN,
             fontsize=8.5, label_family='monospace')

    plt.tight_layout(rect=[0, 0.02, 1, 0.95])
    _save(fig, out_dir, '06_batch_workflow.svg')


# ---------------------------------------------------------------------------
# Save helper
# ---------------------------------------------------------------------------

def _save(fig, out_dir: Path, filename: str):
    out_path = out_dir / filename
    fig.savefig(str(out_path), format='svg',
                bbox_inches='tight', facecolor=BG)
    plt.close(fig)
    print(f'[✓] Saved docs/img/{filename}')


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print('Hyperion Compute — generating architecture diagrams...')
    draw_diagram_1(OUT_DIR)
    draw_diagram_2(OUT_DIR)
    draw_diagram_3(OUT_DIR)
    draw_diagram_4(OUT_DIR)
    draw_diagram_5(OUT_DIR)
    draw_diagram_6(OUT_DIR)
    print('Done. All 6 diagrams written to docs/img/')


if __name__ == '__main__':
    main()
