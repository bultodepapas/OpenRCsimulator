---
name: scene-breakdown
description: Break a script or scene into a production breakdown (location, time of day, cast, props, sound, VFX, lighting needs, risks) and suggest an efficient shooting order. Use when the user is preparing a shoot, scheduling, budgeting or doing a script breakdown.
license: MIT
metadata:
  author: Benjamin Leleu
  version: "1.0.0"
---

# Scene Breakdown

Turn script pages into a breakdown sheet a small crew can plan a shoot from.

## Inputs to collect

If not provided, ask once (max 3 questions in one message):

1. The script or scene text (required)
2. Practical limits: number of shoot days, locations available, crew size, gear
3. Delivery format and target runtime

If the user says "just do it", state assumptions in one line and continue.

## Process

1. Split the material into **scenes** (one per location/time change).
2. For each scene extract only what is **in the text**: never invent props, characters or locations.
3. Flag **hidden costs**: night shoots, exteriors that depend on weather, crowds, minors, animals, stunts, VFX, copyrighted music or logos visible on screen, permits.
4. Group scenes by **location and lighting** to propose an efficient shooting order (not story order).
5. Give each scene a **complexity rating** (Low / Medium / High) with a one-line reason.

## Output format

### Scene table

| Sc. | Slug (INT/EXT. LOCATION - TIME) | Cast | Props / wardrobe | Sound / music | VFX / special | Lighting needs | Complexity |
|-----|---------------------------------|------|------------------|---------------|---------------|----------------|------------|

### Risks and unknowns
A short list of items that could break the schedule, each with a cheaper alternative if one exists.

### Suggested shooting order
Group by location/light. Show the grouping logic in one line per group, not a long essay.

### Shopping / prep list
Props, permits, releases and gear to confirm before day one.

## Rules

- Extract from the text only. If something is ambiguous, list it under "Unknowns" instead of deciding for the user.
- Keep it scannable. This is a working document, not prose.
- Mention legal checkpoints (location permits, actor releases, music rights) as reminders, not as legal advice.
