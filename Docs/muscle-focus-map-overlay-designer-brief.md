# Designer Brief: Muscle Focus Map Overlay Assets

**Product:** Pulsar Fitness — Muscle Focus Map  
**Date:** 2026-07-10  
**Priority:** High — blocks premium visual quality  
**Owner:** Design + iOS engineering  

---

## 1. Goal

Produce **anatomically registered, baked-color muscle overlay PNGs** that sit perfectly on the existing dark 3D body bases.

The current overlays share the correct canvas size but the **painted muscle regions are wrong**: too large, too far from the midline, bleeding into adjacent muscles, and looking detached / floating.

**Success looks like:** trained muscles glow *inside* the real pecs, delts, quads, etc. — embedded in the anatomy, not stickers on top.

---

## 2. Source of truth (do not invent a new body)

Use these existing app assets as the locked master:

| Asset | Path | Canvas |
|---|---|---|
| Front base | `Pulsar/Assets.xcassets/MuscleFocusMap/body_front_base.imageset/body_front_base.png` | **822 × 1913 px** |
| Back base | `Pulsar/Assets.xcassets/MuscleFocusMap/body_back_base.imageset/body_back_base.png` | **821 × 1915 px** |

### Critical rules

1. Open the base PNG as the bottom layer.
2. Paint / mask overlays **on that exact canvas**.
3. Do **not** rescale, crop, rotate, or reframe the body.
4. Do **not** generate a new body silhouette.
5. Prefer normalizing the back set to **822 × 1913** if you re-export both sides (ideal). If not, keep back at **821 × 1915** and match that exactly for all back overlays.

---

## 3. Style direction

| Do | Don’t |
|---|---|
| Dark graphite body (already done) | Medical textbook labels |
| Soft neon muscle illumination | Flat paint-bucket fills |
| Internal fiber / gradient lighting | Hard white cutout borders |
| Color follows real muscle contours | Soft circular blobs |
| Subtle outer feather (≤ 8–12 px) | Huge bloom that floats off-body |
| Premium Apple Fitness / WHOOP feel | Cartoon / childish neon |
| Readable at ~150 pt wide on iPhone | Fine detail that vanishes at small size |

**Reference feel:** dark anatomical figure + embedded neon muscle heat, not a heatmap sticker sheet.

---

## 4. Color specification (match app legend)

Bake these hues into the overlays (gradients OK; keep midtones near these values):

| Muscle | App token | Target hue | Hex guide |
|---|---|---|---|
| Chest | push blue | Electric blue | `#99A8FF` → `#4D6BFF` |
| Delts (shoulders) | push purple-blue | Soft purple | `#9B7AFF` → `#7B5FD4` |
| Triceps | push violet | Violet | `#8B7AFF` → `#6E5FD4` |
| Back | pull cyan | Cyan / teal | `#61D1FF` → `#2AABB8` |
| Biceps | pull light blue | Light cyan-blue | `#6EC8FF` → `#4AA8E8` |
| Core | warm orange | Amber orange | `#FFB847` → `#E8922E` |
| Glutes | warm orange-green | Warm orange | `#FFAA55` → `#E88830` |
| Quads | teal-green | Mint teal | `#4DEBB8` → `#2BB88A` |
| Hamstrings | green | Soft green | `#4DDB90` → `#30BB70` |
| Calves | soft green | Light green | `#5EE8A0` → `#3CC880` |
| Cardio | cyan accent | Cyan waveform | `#26C7D1` |

Overlays should include:
- Soft internal gradient (brighter core, darker edges)
- Subtle fiber direction matching the base body
- Soft edge feather into transparency
- **No** hard white/grey stroke borders

---

## 5. Exact file list & naming

Place final PNGs into:

`Pulsar/Assets.xcassets/MuscleFocusMap/<name>.imageset/<name>.png`

### Front (canvas **822 × 1913**)

| Filename | Muscle region to paint |
|---|---|
| `body_front_chest_overlay.png` | Left + right **pectoralis major** only |
| `body_front_delts_overlay.png` | Left + right **anterior / lateral deltoids** |
| `body_front_biceps_overlay.png` | Left + right **biceps** |
| `body_front_triceps_overlay.png` | Visible **triceps** from front (outer arm) |
| `body_front_core_overlay.png` | **Rectus abdominis + obliques** (front core) |
| `body_front_quads_overlay.png` | Left + right **quadriceps** |
| `body_front_calves_overlay.png` | Left + right **front calves** |
| `body_front_cardio_overlay.png` | Optional subtle cyan accent (see §7) |

### Back (canvas **821 × 1915**, or **822 × 1913** if normalized)

| Filename | Muscle region to paint |
|---|---|
| `body_back_back_overlay.png` | **Lats / mid-upper back** (not full body) |
| `body_back_delts_overlay.png` | **Rear / lateral delts** |
| `body_back_triceps_overlay.png` | **Triceps** (back view) |
| `body_back_glutes_overlay.png` | **Glutes** |
| `body_back_hamstrings_overlay.png` | **Hamstrings** |
| `body_back_calves_overlay.png` | **Calves** (back view) |
| `body_back_cardio_overlay.png` | Optional; prefer unused if front cardio accent is enough |

**Do not create:** biceps on back, chest on back, quads on back, glutes/hamstrings on front.

---

## 6. Anatomical region guide (front)

Use the base body landmarks. Paint **only** inside these regions:

### Chest (highest priority — currently worst)
- **Include:** pectoralis major, both sides, meeting near sternum
- **Exclude:** delts, biceps, neck, abs
- Inner edges should sit close to the sternum (small center gap only)
- Outer edge should tuck toward the armpit / pec–delt junction — **not** cover the outer shoulder cap
- Bottom edge follows the natural pec fold above the upper abs

### Delts
- Rounded shoulder caps only
- Do not merge into chest or upper traps excessively

### Biceps
- Front upper-arm belly only
- Keep clear of chest and forearm

### Triceps (front)
- Outer / posterior arm visible from front
- Thin, precise — easy to overpaint

### Core
- Abs + obliques
- Stay inside torso; do not spill onto hips/quads

### Quads
- Front thigh muscle mass
- Stop above the knee; do not cover hips/glutes

### Calves
- Lower leg only
- Must sit on the actual calf anatomy near the bottom of the figure (current asset sits too high)

---

## 7. Cardio treatment

**Do not** draw a thick ECG line across the chest/back anatomy.

Preferred:
- Very subtle cyan energy accent near upper torso **or**
- Small waveform used only as a **between-figures** UI accent (engineering already supports a center accent)

If exporting `body_front_cardio_overlay.png`:
- Keep opacity inherently low in the asset
- Thin luminous mark, not a filled muscle region
- Must not cut through pecs as a dominant stripe

---

## 8. Technical export specs

| Property | Requirement |
|---|---|
| Format | **PNG-24 + alpha** |
| Color space | sRGB or Display P3 (be consistent with bases) |
| Background | Fully transparent outside muscle |
| Canvas | Exact match to base (see §2) |
| Alignment | Pixel-identical body position to base |
| Feather | Soft edge ≤ 12 px; no hard cut |
| Border | None |
| Compression | Lossless; optimize with ImageOptim/pngcrush after approval |
| Scales | Deliver at least one master at full canvas size; `@2x`/`@3x` optional if engineering requests |

### Photoshop / Affinity / Figma workflow

1. New document = exact base pixel size  
2. Place `body_front_base` (or back) as locked background  
3. Create one layer group per muscle  
4. Mask tightly to anatomy (pen tool / select from body)  
5. Paint color + internal gradient + light fiber detail **inside the mask**  
6. Soften mask edge slightly  
7. Hide base → export each group as PNG with transparency  
8. Re-enable base → toggle each overlay at 60% opacity for QA  

---

## 9. QA checklist (designer sign-off)

For **every** overlay:

- [ ] Canvas size matches its base exactly  
- [ ] Body does not shift when overlay is toggled on/off  
- [ ] Muscle paint sits inside the correct anatomy  
- [ ] No spill into neighboring muscles  
- [ ] No paint outside the body silhouette  
- [ ] No hard white/grey outline  
- [ ] Looks good at full size **and** at ~160 px wide (phone)  
- [ ] Left/right symmetry is intentional and clean  
- [ ] Sternum / spine midline alignment looks natural  
- [ ] Composite of all active muscles still readable (not a neon mess)

### Priority visual QA pair
1. Base + **chest** only  
2. Base + **chest + delts**  
3. Base + **full upper body**  
4. Base + **lower body**  
5. Front + back side-by-side in the Fitness card mock  

---

## 10. Known failures in current overlays (fix these)

From engineering pixel analysis:

| Overlay | Problem |
|---|---|
| `body_front_chest_overlay` | ~2× too wide; lobes too far from sternum; bleeds into delts/arms |
| `body_front_delts_overlay` | Floats outward; not locked to shoulder caps |
| `body_front_calves_overlay` | Content too high on canvas (reads as mid-leg) |
| Several overlays | Hard light borders + oversized baked glow → “sticker” look |
| Cardio overlays | Waveform cuts across anatomy awkwardly |

**Do not “fix” by asking engineering to keep large placement hacks.**  
Correct paint on the correct canvas is the real fix. Engineering will then reset `MuscleOverlayPlacement` toward identity.

---

## 11. Delivery package

Please deliver:

1. All overlay PNGs named exactly as in §5  
2. A single contact-sheet PNG/PDF showing:
   - Base alone  
   - Each overlay alone on black  
   - Each overlay composited on base at 60%  
3. Optional: layered PSD/Affinity source with base + one layer per muscle (highly preferred for future edits)  
4. Note confirming front/back canvas sizes used  

Drop files into (or hand off for engineering to drop into):

```text
Pulsar/Assets.xcassets/MuscleFocusMap/
  body_front_chest_overlay.imageset/
  body_front_delts_overlay.imageset/
  ...
```

---

## 12. Engineering handoff after delivery

Once assets land, engineering will:

1. Replace imageset PNGs  
2. Reset `MuscleOverlayPlacement` scales/offsets/`bilateralInward` toward `1 / 0 / 0`  
3. Keep body silhouette mask + restrained opacity  
4. Keep cardio as a subtle accent (not a body-cutting waveform)  
5. Run focused tests + Fitness previews (empty / upper / lower / full / cardio)

---

## 13. One-sentence summary for the designer

**Trace each muscle tightly on the existing 822×1913 front / 821×1915 back body PNGs, export transparent baked-color overlays with soft internal glow and no borders, and make sure chest sits inside the pecs — not floating on the shoulders.**
