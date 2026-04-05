# ga-godot

A **Godot 4.6** exploratory engine for 3D music-theory visualization and governance modeling. Prototypes immersive interaction patterns for Guitar Alchemist.

## Status

**Experimental / Prototype** — This repo explores Godot as a visualization and interaction surface for the Guitar Alchemist product. It is not yet integrated into the main product pipeline.

## Purpose

`ga-godot` implements early-stage 3D scenes and interaction patterns for governance visualization and music-theory immersion:

- **Prime Radiant (Solar System)** — Models the Demerzel governance hierarchy as a physics-driven celestial system. Repos become planets, governance artifacts become orbiting bodies. Belief states and confidence metrics drive visual properties (color, glow, orbit).
- **Demerzel Face** — Procedural 3D face with blend-shape expressions, driven by emotion states (calm, concerned, thinking, pleased, alert). Intended to humanize governance personas.
- **Governance Nodes** — Extends Godot's Node3D to represent viable-system-model (VSM) cells. Each node emits algedonic signals (pain/pleasure) and manages belief state transitions.

## Relationship to GA

This repo is a **visualization layer** exploring what Godot uniquely enables:

- **Main GA** (`/ga`) owns the React UI, domain logic, and music-theory courses.
- **ga-godot** owns the 3D viewport and immersive interaction prototypes.
- Future: Godot may become an optional **desktop surface** alongside the web React UI, bridged via WebSocket (Galactic Protocol event schema).

## How to Run

1. Install Godot 4.6+ (via `winget` or godotengine.org)
2. Open the project in Godot Editor: `File → Open Project → project.godot`
3. Play the main scene: `Run → Play` or press `F5`

Main scene: `res://scenes/prime_radiant.tscn`

## Current Features

- **Solar system physics** with planets representing Demerzel, ix, TARS, and GA repos
- **Governance node hierarchy** with VSM role tagging and belief state tracking
- **MCP Pro addon** integration — 163 AI-assistant tools for scene manipulation and testing
- **Custom shaders** (WIP) for glow, atmospheric effects
- **Algedonic signals** — mock pain/pleasure propagation up governance hierarchies

## Next Milestone

- [ ] **Constitutional Gravity Engine** — Implement physics-based policy orbits (more citations = closer orbit to center)
- [ ] **Godot-React Bridge** — Design WebSocket protocol for sending scene updates from Prime Radiant (React) to Godot viewport
- [ ] **Web Export (WASM)** — Test Godot web export size and startup time for embedded preview
- [ ] **Autonomous Loop** — First MCP test: Godot scene → AI vision critique → governance fix → render

## Technical Notes

- **Godot Version:** 4.6 (C#/.NET support enabled via Mono)
- **Editor Plugins:** godot_mcp (MCP Pro addon for Claude Code integration)
- **Main Scenes:**
  - `scenes/prime_radiant.tscn` — Solar system with governance hierarchy
  - `scenes/demerzel_face.tscn` — Animated face with emotion expressions
- **Key Scripts:**
  - `scripts/prime_radiant.gd` — Solar system orchestrator
  - `scripts/governance_node.gd` — VSM cell with belief/algedonic state
  - `scripts/demerzel_face.gd` — Facial expression controller

## Governance

This repo is **experimental** per the portfolio `ACTIVE_BOUNDARIES.md`. Do not treat as canonical product infrastructure. Coordinate major changes with the GA team.
