---
name: dame-brand-guidelines
description: Apply DAME's official brand guidelines to any document, presentation, or communication. Use when creating or formatting Word docs, PowerPoint slides, emails, or any other material that should follow DAME's visual identity — including colours, typography, logo usage, tone of voice, and naming conventions. Also use when asked about DAME's brand colours, fonts, or style.
---

# DAME Brand Guidelines

Apply DAME's official brand identity consistently across all materials.

## Core Rules

- **Company name:** Always `DAME` — all capitals, no exceptions (it's an acronym: Digital Asset Mining Enterprise)
- **Tone:** Professional, approachable, confident. Clear and concise. No jargon.
- **Logo:** Use short logo by default (1.5cm × 1.5cm). White version on dark backgrounds. Never alter proportions, colours, or orientation.
- **Long logo:** Secondary use only — partnerships or unique diagrams. Board/Executive direction required.

## Colour Palette

See `references/colours.md` for full palette with HEX, RGB, and usage rules.

**Quick reference:**
| Role | Name | HEX |
|---|---|---|
| Primary | Dark Green | `#608B2D` |
| Primary | Light Green | `#7DB935` |
| Secondary | Dark Blue | `#066BB0` |
| Secondary | Light Blue | `#4C9BDC` |
| Default | Black | `#000000` |
| Background | Mid Grey | `#BFBFBF` |
| Alarm/Alert | Red | `#D90D39` |

**Colour intent:**
- 🟢 Green palette → objective / planned outcomes
- 🔵 Blue palette → subjective / pre-planned outcomes  
- ⚫ Monochrome → external constraints or internal reporting

## Typography

- **Primary font:** Neue Haas Grotesk Text Pro
- Fallback: Arial
- All heading/body styles defined in the Word template (SharePoint: `1.3.3 Templates`)
- Hierarchy: Title → Sub-Title → Heading 1 → Heading 2 → Heading 3 → Heading 4 → Body → Bullet (open circle → numeric → alpha)

## Templates & Assets

All official templates are at SharePoint: **`1.3.3 Templates`**
- Word document template (`.dotx`) — see `dame-document-create` skill
- Letterhead
- PowerPoint presentation template
- Stock photo library
- Icon set

## Formatting Rules

- Bullet points or numbered lists for clarity
- Consistent margins (refer to template for exact values)
- Left-align all content unless otherwise specified
- High-resolution professional images only — avoid casual or complex visuals

## Applying Brand in Python (python-pptx / python-docx)

```python
from pptx.util import Pt
from pptx.dml.color import RGBColor

# DAME primary colours
DARK_GREEN  = RGBColor(0x60, 0x8B, 0x2D)
LIGHT_GREEN = RGBColor(0x7D, 0xB9, 0x35)
DARK_BLUE   = RGBColor(0x06, 0x6B, 0xB0)
LIGHT_BLUE  = RGBColor(0x4C, 0x9B, 0xDC)
BLACK       = RGBColor(0x00, 0x00, 0x00)
MID_GREY    = RGBColor(0xBF, 0xBF, 0xBF)
ALARM_RED   = RGBColor(0xD9, 0x0D, 0x39)
```

For full colour application workflow, see `references/colours.md`.
