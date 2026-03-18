# DAME Colour Palette — Full Reference

## Primary Palette (Green — Objective / Planned Outcomes)

| Name | HEX | RGB | Use |
|---|---|---|---|
| Dark Green | `#608B2D` | 096, 139, 045 | Primary headings, key elements |
| Light Green | `#7DB935` | 125, 185, 053 | Accents, highlights, secondary elements |

## Secondary Palette (Blue — Subjective / Pre-Planned Outcomes)

| Name | HEX | RGB | Use |
|---|---|---|---|
| Dark Blue | `#066BB0` | 006, 107, 176 | Secondary headings, links, callouts |
| Light Blue | `#4C9BDC` | 076, 155, 220 | Accents, backgrounds, supporting elements |

## Monochrome Palette (External Constraints / Internal Reporting)

| Name | HEX | RGB | Use |
|---|---|---|---|
| Black | `#000000` | 000, 000, 000 | Default text |
| Mid Grey | `#BFBFBF` | 191, 191, 191 | Backgrounds, dividers, subtle elements |

## Alert Colour

| Name | HEX | RGB | Use |
|---|---|---|---|
| Alarm Red | `#D90D39` | 217, 013, 057 | Warnings, alerts, critical statuses only |

---

## Python Constants

```python
from pptx.dml.color import RGBColor
from docx.shared import RGBColor as DocxRGB

# Base colour tuples — single source of truth
_DARK_GREEN  = (0x60, 0x8B, 0x2D)
_LIGHT_GREEN = (0x7D, 0xB9, 0x35)
_DARK_BLUE   = (0x06, 0x6B, 0xB0)
_LIGHT_BLUE  = (0x4C, 0x9B, 0xDC)
_BLACK       = (0x00, 0x00, 0x00)
_MID_GREY    = (0xBF, 0xBF, 0xBF)
_ALARM_RED   = (0xD9, 0x0D, 0x39)

# python-pptx
DARK_GREEN  = RGBColor(*_DARK_GREEN)
LIGHT_GREEN = RGBColor(*_LIGHT_GREEN)
DARK_BLUE   = RGBColor(*_DARK_BLUE)
LIGHT_BLUE  = RGBColor(*_LIGHT_BLUE)
BLACK       = RGBColor(*_BLACK)
MID_GREY    = RGBColor(*_MID_GREY)
ALARM_RED   = RGBColor(*_ALARM_RED)

# python-docx
DARK_GREEN_DOCX  = DocxRGB(*_DARK_GREEN)
LIGHT_GREEN_DOCX = DocxRGB(*_LIGHT_GREEN)
DARK_BLUE_DOCX   = DocxRGB(*_DARK_BLUE)
LIGHT_BLUE_DOCX  = DocxRGB(*_LIGHT_BLUE)
```

## Colour Intent Guide

| Scenario | Use |
|---|---|
| Deliverables, project outputs, planned milestones | 🟢 Green palette |
| Proposals, forecasts, estimates, assumptions | 🔵 Blue palette |
| Financial reporting, compliance, external comms | ⚫ Monochrome |
| Risk items, blockers, critical alerts | 🔴 Alarm Red (sparingly) |
| Dark/image backgrounds | White `#FFFFFF` text + white logo |

## Background Contrast Guide

| Background | Recommended Text | Logo Version |
|---|---|---|
| White / Light Grey | Dark Green, Dark Blue, Black | Colour logo |
| Dark Green / Dark Blue | White | White logo |
| Mid Grey | Black | Colour logo |
| Black | White or Light Blue | White logo |
