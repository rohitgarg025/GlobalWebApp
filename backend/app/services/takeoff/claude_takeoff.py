"""Claude's part of the takeoff: interpret the drawing, never do the arithmetic.

Claude receives what the code measured (grid, beams, columns, slab labels,
cut-outs, notes) plus a rendered image of the floor, and returns:
  * slab panels by grid bay (thickness, PT or not) and slab deductions,
  * fixes for beams whose size label couldn't be matched confidently,
  * labelled members that aren't drawn as geometry,
  * the floor-to-floor height if the drawing states it, plus notes.
"""
from __future__ import annotations

import base64
import json
import re
from collections import Counter, defaultdict

import anthropic

from app.services.takeoff.drawing import FloorData

MODEL = "claude-opus-5"
# Server-side refusal fallback: a declined request is re-run on Anthropic's
# recommended fallback model instead of failing the job.
FALLBACK_BETA = "server-side-fallback-2026-07-01"


class TakeoffAIError(Exception):
    pass


# The API caps union/nullable parameters per schema (16), so "unknown" is sent
# as 0 for numbers and "" for strings instead of null; _unknowns_to_none()
# converts them back after parsing.
_NUM = {"type": "number"}
_STR = {"type": "string"}
_CONF = {"type": "string", "enum": ["high", "medium", "low"]}

_PANEL = {
    "type": "object",
    "additionalProperties": False,
    "required": ["x_from", "x_to", "y_from", "y_to", "length_m", "breadth_m", "location",
                 "thickness_mm", "is_pt", "description", "confidence", "evidence"],
    "properties": {
        "x_from": _STR, "x_to": _STR,
        "y_from": _STR, "y_to": _STR,
        "length_m": _NUM, "breadth_m": _NUM,
        "location": _STR,
        "thickness_mm": _NUM,
        "is_pt": {"type": "boolean"},
        "description": {"type": "string"},
        "confidence": _CONF,
        "evidence": {"type": "string"},
    },
}

OUTPUT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["floor_to_floor_height_m", "height_evidence", "typical_slab_thickness_mm",
                 "slab_panels", "slab_deductions", "beam_fixes", "exclude_beam_ids",
                 "extra_members", "notes", "missing_info"],
    "properties": {
        "floor_to_floor_height_m": _NUM,
        "height_evidence": _STR,
        "typical_slab_thickness_mm": _NUM,
        "slab_panels": {"type": "array", "items": _PANEL},
        "slab_deductions": {"type": "array", "items": _PANEL},
        "beam_fixes": {"type": "array", "items": {
            "type": "object", "additionalProperties": False,
            "required": ["beam_id", "depth_mm", "mark", "reason"],
            "properties": {
                "beam_id": {"type": "string"}, "depth_mm": _NUM,
                "mark": _STR, "reason": {"type": "string"},
            },
        }},
        "exclude_beam_ids": {"type": "array", "items": {"type": "string"}},
        "extra_members": {"type": "array", "items": {
            "type": "object", "additionalProperties": False,
            "required": ["member_type", "mark", "count", "breadth_mm", "depth_mm", "location", "reason"],
            "properties": {
                "member_type": {"type": "string", "enum": ["column", "wall", "other"]},
                "mark": _STR, "count": {"type": "integer"},
                "breadth_mm": _NUM, "depth_mm": _NUM,
                "location": _STR, "reason": {"type": "string"},
            },
        }},
        "notes": {"type": "array", "items": {"type": "string"}},
        "missing_info": {"type": "array", "items": {"type": "string"}},
    },
}

SYSTEM = """You are a senior quantity surveyor in India with decades of experience in billing, \
planning and measurement of RCC framed buildings to IS 1200 (Part 2 concrete, Part 5 formwork).

You are reviewing one floor of a structural framing drawing. Software has already measured the \
geometry exactly: grid lines, beams (drawn outlines, clear lengths between column faces, and their \
size labels where matched), columns (drawn outlines) and cut-outs. Treat those measurements as \
reliable. Your job is interpretation, not arithmetic:

1. Slab panels. Using the rendered plan and the slab labels (with the grid bay each label sits in), \
lay out the floor slab as panels by grid bay. Give each panel its grid range (x_from/x_to on the \
vertical grid lines, y_from/y_to on the horizontal ones, exactly as labelled in the grid list), its \
thickness in mm and whether it is a PT slab. Adjacent bays with the same slab may be combined into one \
panel. Only use explicit length_m/breadth_m (with a location) for slab areas that don't align with \
grids, such as cantilevers. Do not cover double-height voids or areas with no slab. If a PT slab \
label gives no thickness, use the thickness written next to it or in the notes; otherwise leave it 0.
   If grids.auto_generated is true, the drawing had no grid: the listed lines were derived from the \
beam layout (X1… left to right, Y1… top to bottom); use them the same way. If the plan has no slab \
labels at all, still lay out the slab by structural bays (areas enclosed by beams in the image), give \
thickness_mm 0 unless the drawing states one elsewhere (the surveyor's default thickness will then \
apply), and mark those panels confidence "low". Leave out voids, cut-outs, stair wells and areas \
that clearly carry no slab (e.g. plinth-level ground-bearing areas, if the notes say so).
2. Slab deductions. List openings, shafts, stair and lift cut-outs larger than 0.1 m² that fall \
inside your panels, from the cut-out list and the X-marked areas in the image.
3. Beam fixes. For each beam listed as uncertain, choose its depth (and mark if evident) from the \
nearby labels and the image, or leave it out of beam_fixes if you can't tell. Put beam ids that \
are not structural beams (e.g. drawn by mistake, parapet lines) in exclude_beam_ids.
4. Extra members. If size labels clearly denote columns or walls that aren't drawn as geometry, \
list them with count and size so the surveyor can confirm them. Be conservative.
5. Height. Report the floor-to-floor height only if the drawing states it (levels, sections, \
notes), with the evidence. Otherwise null.
6. Notes and missing info. Record assumptions a checking engineer should verify, and anything \
needed for an accurate takeoff that the drawing doesn't show.

Every field is required. When a value is unknown or doesn't apply, use 0 for numbers and an empty \
string for text (e.g. grid fields are "" for a panel given by explicit length_m/breadth_m, and \
length_m/breadth_m are 0 for a panel given by grids). Never invent dimensions: prefer 0 or "" \
plus a note over a guess."""


def _unknowns_to_none(v):
    """0 / "" (the schema's 'unknown') → None, recursively; counts and booleans kept."""
    if isinstance(v, dict):
        return {k: (x if k in ("count", "is_pt") else _unknowns_to_none(x)) for k, x in v.items()}
    if isinstance(v, list):
        return [_unknowns_to_none(x) for x in v]
    if v == "" or (isinstance(v, (int, float)) and not isinstance(v, bool) and v == 0):
        return None
    return v


def _digest(fd: FloorData) -> dict:
    u = fd.unit_m
    gx = [g for g in fd.grids if g.axis == "x"]
    gy = [g for g in fd.grids if g.axis == "y"]
    ox = min((g.pos for g in gx), default=0.0)
    oy = min((g.pos for g in gy), default=0.0)

    slab_by_bay: dict[str, Counter] = defaultdict(Counter)
    for s in fd.slab_labels:
        slab_by_bay[s.location][s.text] += 1

    beam_sizes = Counter()
    beam_len = Counter()
    uncertain = []
    for b in fd.beams:
        key = f"{b.breadth_mm}x{b.depth_mm or '?'}"
        beam_sizes[key] += 1
        beam_len[key] += b.clear_length_m
        if b.confidence != "high":
            uncertain.append({
                "beam_id": b.id, "bay": b.location, "drawn_width_mm": b.breadth_mm,
                "clear_length_m": b.clear_length_m, "current_depth_mm": b.depth_mm,
                "nearby_size_labels": b.nearby_sizes, "why_uncertain": b.evidence,
            })

    return {
        "floor": fd.floor.title,
        "grids": {
            "auto_generated": fd.auto_grid,
            "vertical_x": [{"label": g.label, "x_m": round((g.pos - ox) * u, 3)} for g in gx],
            "horizontal_y": [{"label": g.label, "y_m": round((g.pos - oy) * u, 3)} for g in gy],
        },
        "slab_labels_present": bool(fd.slab_labels),
        "slab_labels_by_bay": {bay: dict(c) for bay, c in sorted(slab_by_bay.items())},
        "cutouts": [{"bay": c.location, "length_m": c.length_m, "breadth_m": c.breadth_m} for c in fd.cutouts],
        "beams_measured": {
            "count": len(fd.beams),
            "by_size": {k: {"spans": beam_sizes[k], "clear_length_m": round(beam_len[k], 2)}
                        for k in sorted(beam_sizes)},
            "uncertain": uncertain[:200],
        },
        "columns_measured": dict(Counter(f"{c.breadth_mm}x{c.depth_mm}" for c in fd.columns)),
        "warnings": fd.warnings,
        "notes_on_drawing": fd.notes,
    }


def interpret_floor(fd: FloorData, image_png: bytes, level_texts: list[str],
                    default_slab_mm: int | None = None) -> tuple[dict, dict]:
    """Returns (interpretation, usage). Raises TakeoffAIError with a user-facing message."""
    digest = _digest(fd)
    digest["levels_and_heights_found_anywhere_in_drawing"] = level_texts
    digest["surveyor_default_slab_thickness_mm"] = default_slab_mm or 0
    content = [
        {"type": "image", "source": {"type": "base64", "media_type": "image/png",
                                     "data": base64.standard_b64encode(image_png).decode()}},
        {"type": "text", "text": (
            f"Floor: {fd.floor.title}. Measured data (drawing units converted to metres/mm):\n\n"
            + json.dumps(digest, ensure_ascii=False)
        )},
    ]

    try:
        client = anthropic.Anthropic()
    except anthropic.AnthropicError as e:  # no API key configured on the server
        raise TakeoffAIError(
            "Claude isn't configured on the server (ANTHROPIC_API_KEY is not set)."
        ) from e
    try:
        with client.beta.messages.stream(
            model=MODEL,
            max_tokens=64000,
            system=SYSTEM,
            thinking={"type": "adaptive"},
            output_config={
                "effort": "high",
                "format": {"type": "json_schema", "schema": OUTPUT_SCHEMA},
            },
            betas=[FALLBACK_BETA],
            fallbacks="default",
            messages=[{"role": "user", "content": content}],
        ) as stream:
            msg = stream.get_final_message()
    except anthropic.AuthenticationError as e:
        raise TakeoffAIError("The server's Claude API key is missing or invalid.") from e
    except anthropic.RateLimitError as e:
        raise TakeoffAIError("Claude is busy (rate limited). Try again in a minute.") from e
    except anthropic.BadRequestError as e:
        raise TakeoffAIError(f"Claude rejected the request: {e.message}") from e
    except anthropic.APIStatusError as e:
        raise TakeoffAIError(f"Claude API error ({e.status_code}). Try again shortly.") from e
    except anthropic.APIConnectionError as e:
        raise TakeoffAIError("Couldn't reach the Claude API from the server.") from e
    except TypeError as e:
        # SDK 1.x raises this when no credentials can be resolved
        if "authentication" in str(e).lower():
            raise TakeoffAIError(
                "Claude isn't configured on the server (ANTHROPIC_API_KEY is not set)."
            ) from e
        raise

    if msg.stop_reason == "refusal":
        raise TakeoffAIError("Claude declined to analyse this drawing.")
    if msg.stop_reason == "max_tokens":
        raise TakeoffAIError("Claude's answer was cut off; the drawing may be too large for one pass.")
    text = "".join(b.text for b in msg.content if b.type == "text")
    try:
        result = _unknowns_to_none(json.loads(text))
    except json.JSONDecodeError as e:
        raise TakeoffAIError("Claude returned an unreadable answer; please retry.") from e
    for key in ("slab_panels", "slab_deductions", "beam_fixes", "exclude_beam_ids",
                "extra_members", "notes", "missing_info"):
        result[key] = result.get(key) or []

    usage = {
        "input_tokens": getattr(msg.usage, "input_tokens", 0) or 0,
        "output_tokens": getattr(msg.usage, "output_tokens", 0) or 0,
        "model": msg.model,
    }
    return result, usage


def level_texts(doc, limit: int = 60) -> list[str]:
    """Level / height annotations anywhere in the drawing (sections, elevations, notes)."""
    pat = re.compile(r"(FFL|SFL|TOS|LVL|LEVEL|FLOOR HT|FLOOR HEIGHT|F\.F\.L|[+-]\s?\d{1,3}\.\d{2,3}\s*(M|m)?\b)")
    seen = Counter()
    for e in doc.modelspace().query("TEXT MTEXT"):
        try:
            s = e.dxf.text if e.dxftype() == "TEXT" else e.plain_text()
        except Exception:
            continue
        s = " ".join(s.split())
        if 3 <= len(s) <= 120 and pat.search(s):
            seen[s] += 1
    return [s for s, _ in seen.most_common(limit)]
