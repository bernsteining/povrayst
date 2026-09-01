#import "../pkg/povray.typ": render, pov
#import "@preview/zebraw:0.6.1": zebraw

#set document(title: "Povrayst", author: "povrayst")
#set page(
  paper: "a4",
  margin: (x: 2cm, y: 2.2cm),
  footer: context align(center, text(size: 9pt, [#counter(page).display()])),
)
#set text(font: "Libertinus Serif", size: 11pt)
#set par(justify: true)
#set heading(numbering: "1.")
#show heading.where(level: 1): it => { v(1.4em); it; v(0.6em) }
#set raw(syntaxes: "../pkg/povray.sublime-syntax")
#show raw.where(block: true): set text(size: 9pt)
#show raw: set text(font: "DejaVu Sans Mono")
#show link: set text(fill: blue.darken(20%))
#show: zebraw.with(numbering: false)

#let pov-example(
  source-path,
  title: none,
  typst-snippet: none,
  caption: none,
  image-width: 65%,
  code-size: 8pt,
  split-at: none,
  ..render-args,
) = {
  let src = read(source-path).trim("\n", at: end)
  let lines = src.split("\n")
  let half = if split-at != none { split-at } else { calc.ceil(lines.len() / 2) }
  let left-raw = raw(lines.slice(0, half).join("\n"), lang: "povray", block: true)
  let right-raw = raw(lines.slice(half).join("\n"), lang: "povray", block: true)
  [
    #if title != none [
      #text(size: 9.5pt, style: "italic", raw(title))
      #v(-0.3em)
    ]
    #show raw.where(block: true): set text(size: code-size)
    #grid(
      columns: (1fr, 1fr),
      column-gutter: 8pt,
      zebraw(numbering: true, left-raw),
      zebraw(numbering: true, numbering-offset: half, right-raw),
    )
    #if typst-snippet != none [
      #v(0.5em)
      #raw(typst-snippet, lang: "typst", block: true)
    ]
    #v(0.6em)
    #align(center, box(width: image-width, render(read(source-path), ..render-args)))
    #if caption != none [
      #v(-0.3em)
      #align(center, text(size: 9.5pt, style: "italic", caption))
    ]
  ]
}

#set page(numbering: none)
#counter(page).update(0)

#align(center + horizon)[
  #box(width: 70%, image("examples/logo.png"))
  #v(2em)
  #text(size: 28pt, weight: "bold")[Povrayst]
  #v(0.4em)
  #text(size: 14pt, style: "italic")[Declarative raytracing in Typst.]
  #v(1.2em)
  #text(size: 10pt)[version 0.1.1  ·  August 2026]
  #v(0.6em)
 #link("https://github.com/bernsteining/povrayst")[#text(size: 10pt, fill: blue)[github.com/bernsteining/povrayst]] · #link("https://typst.app/universe/package/povrayst")[#text(size: 10pt, fill: blue)[typst.app/universe/package/povrayst]]
  #v(3em)
]

#pagebreak()
#set page(numbering: "1")
#counter(page).update(1)

#outline(title: [Contents], depth: 2, indent: 1em)

#pagebreak(weak: true)

= Introduction

#link("https://www.povray.org/")[POV-Ray] (_Persistence of Vision Raytracer_)
is a free, declarative ray tracer first released in 1991. There is no interactive editor: a scene
is a plain text file describing camera, lights, geometry, and surfaces,
and the renderer turns it into a pixel-perfect image. The same `.pov`
source produces the same output on any platform and any version —
scenes diff cleanly, parameterise easily, and stay reproducible.

What makes POV-Ray useful for mathematical and scientific figures is
the breadth of primitives: implicit algebraic surfaces (`cubic`,
`quartic`, `poly` up to degree 15), quaternion fractals
(`julia_fractal`), swept tubes (`sphere_sweep`), photon caustics, and
`function { ... }` expressions for arbitrary procedural patterns and
isosurfaces. The gallery at the end of this document — Clebsch cubic,
Hopf fibration, Lissajous knot, gyroid, caustics — is a few dozen
lines of SDL each, no external assets. Povrayst wraps POV-Ray 3.8 as
a Typst WebAssembly plugin so all of that renders inline when you
compile.

= Caching and iteration

Typst memoises `render()` by its arguments. Identical calls across
compiles return the cached image without re-running the plugin — change
the scene string or any kwarg and it re-renders; otherwise it's free.
This makes incremental documentation editing very fast.

Run `typst watch doc.typ` to pick up changes on save. A cold first
compile runs every scene once (typically a few seconds to a couple
minutes each, depending on complexity); subsequent edits to prose,
layout, or unrelated sections complete in milliseconds.

For expensive renders you iterate on rarely (a high-resolution cover,
say), compile once to a separate `.typ` that writes a PNG to disk,
then reference that PNG via `image()` in your main document — the
logo at the top of this PDF is produced that way, since I needed the PNG for the `README.md`.

= Scene Description Language 

A minimal POV-Ray scene has a `camera`, at least one `light_source`,
and one or more objects:

```povray
camera { location <0, 2, -5> look_at 0 angle 40 }
light_source { <4, 6, -4> color rgb 1.2 }
sphere { 0, 1 pigment { rgb <1, 0.4, 0.15> } }
```

Objects carry a `pigment` (colour) and optionally a `finish`
(specular/diffuse/reflection), an `interior` (index of refraction,
dispersion), and a `normal` (surface bump).

Pigments and normals can be procedural patterns — `checker`,
`gradient`, `spherical`, `marble`, `wood`, `granite`, `crackle`, or
arbitrary `function { x*x + y*y + sin(z) }` expressions — so most
textures need no image files at all.

`#declare`, `#while`, `#macro`, and arithmetic on every numeric
parameter let you parameterise scenes programmatically; the gallery's
Hopf and gyroid examples use this to generate fibres and isosurface
functions.

Have a look at the #link("https://www.povray.org/documentation/3.7.0/r3_0.html#r3_3")[Scene Description Language's documentation] for more information.

#pagebreak()

= Getting started

The package exports two functions, `pov` and `render`. Both accept a
POV-Ray scene plus the same keyword arguments (full reference in @config-reference).
They differ only in how the scene is supplied:

- `pov(scene, ..kwargs)` accepts the scene as a *string* or as a
  fenced `povray` *raw block*. Use it for inline scenes.
- `render(scene, ..kwargs)` accepts the scene as a *string only*.
  Use it for scenes loaded from `.pov` files via `read()`.

Internally `pov` extracts the text from a raw block (or passes a
string straight through) and forwards to `render`.

#let scene = `camera { location <0, 2, -6> look_at 0 angle 35 }
light_source { <4, 6, -4> rgb 1.2 }
sphere { 0, 1 pigment { rgb <0.90, 0.40, 0.15> } }`

```typst
#import "../pkg/povray.typ": pov, render

// Inline scene with `pov`:
#pov("camera { location <0, 2, -6> look_at 0 angle 35 }
      light_source { <4, 6, -4> rgb 1.2 }
      sphere { 0, 1 pigment { rgb <0.90, 0.40, 0.15> } }",
  width: 480, height: 360)

// Scene from a file with `render`:
#render(read("scene.pov"), width: 480, height: 360)
```

#figure(
  box(width: 65%, render(read("examples/basic.pov"), width: 480, height: 300)),
  caption: [The scene above rendered.],
)

For really terse one-shots, install a show rule so that every fenced
`povray` block becomes a render in place:

#v(0.5cm)

```typst
#show raw.where(lang: "povray"): pov
```

After this, any fenced `povray` block in your document renders
directly, with no `#pov(...)` wrapper. Useful to keep syntax highlighting and avoid writing code in a raw string.

#v(0.5cm)

#[
  // Scoped: the global `raw.where(block: true)` rule forces 9pt, which
  // would override a plain `#text(size:)`; set it here so this
  // illustrative block stays small and fits on the page.
  #show raw.where(block: true): set text(size: 8pt)
  #raw(block: true, lang: "povray", "```povray\n" + scene.text + "\n```")
]

= Config reference <config-reference>

Every keyword argument to `render()`, its default, and the POV-Ray
option it maps to. The option names in the right column come verbatim
from POV-Ray's `.ini` / command-line reference — see the
#link("https://www.povray.org/documentation/view/3.7.1/219/")[official
command-line options]
for the full semantics of each flag. Also check #link("https://www.povray.org/documentation/3.7.0/r3_0.html")[POV-Ray's documentation].

#set text(size: 8.75pt)

#let api-row(name, default, pov, effect) = (
  raw(name, lang: "typ"),
  raw(default, lang: "typ"),
  raw(pov),
  effect,
)

#table(
  columns: (auto, auto, auto, 1fr),
  stroke: 0.4pt,
  align: (left, left, left, left),
  inset: 3.75pt,
  table.header([*kwarg*], [*default*], [*POV-Ray option*], [*effect*]),

  table.cell(colspan: 4, fill: luma(240))[*Includes*],
  ..api-row("includes", "(:)", "Typst-side #include expansion",
            [dictionary `{name: content}` spliced before parsing]),

  table.cell(colspan: 4, fill: luma(240))[*Output resolution*],
  ..api-row("width",   "800", "Width",  [image width in pixels]),
  ..api-row("height",  "600", "Height", [image height in pixels]),

  table.cell(colspan: 4, fill: luma(240))[*Quality*],
  ..api-row("quality", "9", "Quality (0–11)",
            [`0` ambient only, `2` +shadows, `5` +reflection, `9` full radiosity]),

  table.cell(colspan: 4, fill: luma(240))[*Antialiasing*],
  ..api-row("antialias",        "true", "Antialias=on/off",
            [master switch for adaptive supersampling]),
  ..api-row("aa-threshold",     "0.3",  "Antialias_Threshold",
            [colour delta that triggers extra samples; lower = smoother]),
  ..api-row("aa-method",        "2",    "Sampling_Method (1/2/3)",
            [`1` fixed grid, `2` adaptive recursive, `3` generic oversampling (3.8+)]),
  ..api-row("aa-depth",         "3",    "Antialias_Depth (1–9)",
            [recursion depth; up to depth² samples/pixel]),
  ..api-row("aa-jitter",        "true", "Jitter=on/off",
            [randomise sub-pixel positions to break up aliasing]),
  ..api-row("aa-jitter-amount", "none", "Jitter_Amount",
            [jitter magnitude 0.0–1.0]),
  ..api-row("aa-gamma",         "none", "Antialias_Gamma",
            [gamma used when comparing sub-sample colours]),

  table.cell(colspan: 4, fill: luma(240))[*Gamma*],
  ..api-row("display-gamma", "none", "Display_Gamma",
            [gamma the final image is rendered _for_]),
  ..api-row("file-gamma",    "none", "File_Gamma",
            [gamma assumed for `rgb <...>` colour literals in the scene]),

  table.cell(colspan: 4, fill: luma(240))[*Tracing*],
  ..api-row("max-trace-level",    "none", "Max_Trace_Level",
            [cap on reflection / refraction ray depth]),
  ..api-row("bounding",           "none", "Bounding=on/off",
            [toggle automatic bounding-slab acceleration]),
  ..api-row("bounding-threshold", "none", "Bounding_Threshold",
            [minimum children before an auto-bound is built]),
  ..api-row("remove-bounds",      "none", "Remove_Bounds=on/off",
            [discard user `bounded_by` when POV-Ray's own bound is tighter]),
  ..api-row("split-unions",       "none", "Split_Unions=on/off",
            [split non-overlapping `union` children into separate bounds]),

  table.cell(colspan: 4, fill: luma(240))[*Partial render*],
  ..api-row("start-row",    "none", "Start_Row",    [render only this pixel-row range]),
  ..api-row("end-row",      "none", "End_Row",      [(integers ≥ 1 or fractions 0..1)]),
  ..api-row("start-column", "none", "Start_Column", [pixel-column range]),
  ..api-row("end-column",   "none", "End_Column",   []),

  table.cell(colspan: 4, fill: luma(240))[*Output encoding*],
  ..api-row("output-alpha", "false", "Output_Alpha=on/off",
            [emit an alpha channel; use with `background { color rgbt <...,1> }`]),
  ..api-row("compression",  "none",  "Compression (0–9)",
            [ignored — output is raw RGBA, not PNG]),

  table.cell(colspan: 4, fill: luma(240))[*Escape hatch*],
  ..api-row("extra", "()", "raw command strings appended verbatim",
            [any flag from POV-Ray's `.ini` / CLI reference]),
)

#set text(size: 11pt)

Passing `none` suppresses the flag so POV-Ray's own default stays in
force. The plugin runs single-threaded (`Work_Threads=1`), with no
display (`-D`), and returns raw RGBA pixels — so `compression` is moot.

= Resolution & quality

== `width` / `height`

Control the output image size in pixels. Default is 800×600.

```typst
#render("...", width: 1200, height: 900)
#render("...", width: 320, height: 240)
```

The scene's `camera { right (image_width/image_height)*x }` uses
these automatically.

== `quality`

Integer 0–11 controlling which rendering features are enabled:

#set text(size: 9.5pt)
#table(
  columns: (auto, 1fr),
  stroke: 0.4pt,
  inset: 5pt,
  [*Level*], [*Features enabled*],
  [`0`],  [Ambient light only],
  [`1`],  [\+ diffuse, pigment patterns],
  [`2`],  [\+ point lights, shadows],
  [`5`],  [\+ reflections (no refraction)],
  [`8`],  [\+ refractions, shadow transparency],
  [`9`],  [\+ full radiosity / media sampling *(default)*],
)
#set text(size: 11pt)

Lower quality renders faster — useful for draft iterations. Side-by-side
on the same scene at 480×300 (no AA), median of 3 samples on the
hardware listed in @render-times:

#grid(
  columns: (1fr, 1fr), column-gutter: 8pt, align: center,
  figure(
    render(read("examples/basic.pov"),
      width: 480, height: 300, quality: 0, antialias: false),
    caption: [`quality: 0` — ambient only, *0.81 s*. \
              Useful while iterating on layout / framing.],
  ),
  figure(
    render(read("examples/basic.pov"),
      width: 480, height: 300, quality: 9, antialias: false),
    caption: [`quality: 9`, full lighting + shadows: *1.60 s*],
  ),
)

Lighting-bound scenes benefit most; geometry-bound ones barely move.

= Antialiasing

Enabled by default. Five kwargs control the behaviour:

#set text(size: 8pt)
#table(
  columns: (auto, auto, 1fr),
  stroke: 0.4pt,
  inset: 2.5pt,
  [*kwarg*], [*default*], [*effect*],
  [`antialias`], [`true`], [master switch; `false` skips AA entirely],
  [`aa-threshold`], [`0.3`], [colour delta that triggers extra samples; lower = smoother/slower],
  [`aa-method`], [`2`], [
    `1` fixed grid, `2` adaptive recursive, `3` generic oversampling
    (POV-Ray 3.8+) — not just edge AA, also suppresses moiré, image
    noise from jittered area lights, subsurface light transport, and
    micronormals. Parameterisation mirrors adaptive focal blur.
  ],
  [`aa-depth`], [`3`], [recursion depth; up to depth² samples per pixel],
  [`aa-jitter`], [`true`], [randomise sub-pixel positions],
)
#set text(size: 11pt)

= Recipes

*Layout scaffolding.* When iterating on document layout you don't
need photorealism. Drop quality, skip AA, and shrink resolution so
each `typst watch` save lands in under a second — restore defaults
once layout settles:
```typst
#render("...", quality: 2, antialias: false, width: 320, height: 240)
```

*Publication quality.* For the camera-ready render, tighten the AA
threshold and deepen recursion:
```typst
#render("...", antialias: true, aa-threshold: 0.1, aa-depth: 4,
  width: 1200, height: 900)
```

= Transparent background

Set `output-alpha: true` and use `background { color rgbt <0,0,0,1> }`
in the scene (`t = 1` means fully transparent). The result is an RGBA
PNG that composites over the Typst page background.

```typst
#pov("background { color rgbt <0, 0, 0, 1> }
      camera { location <0, 1, -4> look_at 0 }
      light_source { <4, 6, -5> rgb 1.3 }
      sphere { 0, 1 pigment { rgb <0.2, 0.55, 0.9> } }",
  output-alpha: true)
```

#let transparent-render = render(read("examples/transparency.pov"),
  width: 130, height: 130, output-alpha: true)

#grid(
  columns: (1fr, 1fr), column-gutter: 1em,
  figure(box(width: 50%, transparent-render), caption: [On white page]),
  figure(
    block(fill: luma(210), inset: 5pt, radius: 4pt,
      box(width: 50%, transparent-render)),
    caption: [On grey — alpha at work]),
)

Without `output-alpha: true`, the background is opaque black regardless of `rgbt`.

= Multi-file scenes (`includes`)

Split a POV-Ray project across `.inc` files by passing the `includes`
dict — `render()` textually expands every `#include "name"` before
handing the scene to the plugin. Nested includes work; a cycle guard
prevents `a.inc → b.inc → a.inc` from looping.

```typst
#render(read("scene.pov"),
  includes: ("materials.inc": read("materials.inc")))
```

= Typst-driven scene parameterisation

The first argument to `render()` is just a string — build it from any
Typst values (loop index, palette entry, computed angle) to drive
geometry, colour, or camera. The grid below is produced by a single
`map` over three angles:

#let orbit-demo = ```typst
#let palette = (rgb("#f26924"), rgb("#3ab573"), rgb("#4c6ef5"))
#let pov-rgb(c) = {
  let (r, g, b, ..) = c.components()
  "<" + str(r/100%) + ", " + str(g/100%) + ", " + str(b/100%) + ">"
}

#let orbit(theta, col) = (
  "global_settings { assumed_gamma 1.0 max_trace_level 2 }\n"
  + "background { color rgbt <0, 0, 0, 1> }\n"
  + "camera { location <" + str(5 * calc.cos(theta))
  + ", 2, " + str(5 * calc.sin(theta)) + "> look_at 0 angle 35 }\n"
  + "light_source { <4, 6, -4> rgb 1.3 }\n"
  + "torus { 1, 0.32 pigment { rgb " + pov-rgb(col) + " } "
  + "finish { specular 0.8 roughness 0.02 } rotate x*25 no_shadow }"
)

#grid(
  columns: (1fr, 1fr, 1fr), column-gutter: 12pt,
  ..((-90deg, 0), (-45deg, 1), (0deg, 2)).map(((a, i)) => render(
    orbit(a, palette.at(i)),
    width: 180, height: 180, quality: 2,
    antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true,
  )),
)
```

#[
  #show raw.where(block: true): set text(size: 7.5pt)
  #orbit-demo
]

#eval(orbit-demo.text, mode: "markup", scope: (render: render))

= Tracing depth & advanced options

== `max-trace-level`

Caps reflection / refraction ray bounces (POV-Ray default `5`,
overrides any in-scene `global_settings`). Drop to `2` for diffuse
scenes; raise for glass-on-glass or hall-of-mirrors.

```typst
#render("...", max-trace-level: 10)
```

#block(breakable: false)[
  == `extra` (escape hatch)

  Array of raw POV-Ray command strings appended verbatim — any flag
  from POV-Ray's `.ini` / CLI reference without a typed kwarg.

  ```typst
  #render("...", extra: ("+WV3.8", "+HI"))
  ```
]

= Examples

== Constructive solid geometry

POV-Ray's signature feature: combine primitives via the boolean
operators `union`, `intersection`, `difference`, and `merge`. Each
takes any number of objects (including other CSG objects) and
produces a new object that participates in further CSG. This is what
lets a few dozen lines of SDL describe shapes that would take a
mesh modeller hours.

The example below is built in three nested operations:
`intersection { box ∩ sphere }` rounds the cube's corners,
`union { 3 cylinders }` collects three orthogonal rods, and
`difference { rounded-cube − rods }` carves the rods out, exposing
the rounded interior surfaces.

#pov-example("examples/csg.pov",
  title: "csg.pov",
  typst-snippet: "#render(read(\"csg.pov\"), output-alpha: true)",
  caption: [Rounded cube with three orthogonal cylindrical bores — `intersection`, `union`, and `difference` in one object.],
  width: 480, height: 360,
  split-at: 11,
  // Kept compact so the code and rendered image stay on the same page
  // as it flows after the short "extra" subsection (no forced pagebreak,
  // which would leave that page half-empty).
  code-size: 7pt,
  image-width: 52%,
  output-alpha: true)

#pagebreak(weak: true)
== Quaternion Julia fractal

Iterate the map

$ z_(n+1) = z_n^2 + c, quad z in bb(H), quad c = -0.083 - 0.83 j - 0.025 k $

over the quaternions $bb(H)$. The rendered set is the boundary
between starting points $z_0$ whose orbit stays bounded and those
that escape to infinity (bailout at $n = 8$). A 3D slice of the
4-dimensional Julia set.
See #link("https://en.wikipedia.org/wiki/Julia_set#Quaternion_and_hypercomplex")[Wikipedia on quaternion Julia sets].

#pov-example("examples/julia.pov",
  title: "julia.pov",
  typst-snippet: "#render(read(\"julia.pov\"), antialias: true, aa-threshold: 0.4, aa-depth: 2, output-alpha: true)",
  caption: [Quaternion Julia set for $c = -0.083 - 0.83 j - 0.025 k$, 3D slice at $q_w = 0.15$, coloured radially from origin.],
  width: 420, height: 315,
  split-at: 16,
  antialias: true, aa-threshold: 0.4, aa-depth: 2, output-alpha: true)

#pagebreak(weak: true)
== Clebsch diagonal cubic

In Cartesian coordinates $(x, y, z) in bb(R)^3$, the Clebsch surface
is the zero set of the symmetric cubic polynomial

$ & 81 (x^3 + y^3 + z^3) - 189 (x^2 y + x^2 z + x y^2 + y^2 z + x z^2 + y z^2) \
  & + 54 x y z + 126 (x y + y z + z x) - 9 (x^2 + y^2 + z^2) - 9 (x + y + z) + 1 = 0 $

A smooth cubic surface with full tetrahedral symmetry containing
exactly 27 real straight lines (Cayley–Salmon, 1849; Clebsch's
explicit coordinates, 1869). POV-Ray's `cubic { ... }` takes the 20
polynomial coefficients directly and ray-marches the zero set via
Sturm sequences — no mesh, no approximation. See
#link("https://en.wikipedia.org/wiki/Clebsch_surface")[Wikipedia on
the Clebsch surface].

#pov-example("examples/clebsch.pov",
  title: "clebsch.pov",
  typst-snippet: "#render(read(\"clebsch.pov\"), output-alpha: true)",
  caption: [Clebsch diagonal cubic, clipped to a sphere; stepped vertical gradient pigment, the contour bands tracing the surface's height curvature.],
  width: 480, height: 360,
  split-at: 11,
  output-alpha: true)

#pagebreak(weak: true)
== Schoen gyroid

In Cartesian coordinates $(x, y, z) in bb(R)^3$, Schoen's gyroid is
a *triply periodic minimal surface* — the zero set of the
transcendental function

$ f(x, y, z) = sin x cos y + sin y cos z + sin z cos x = 0 $

It locally minimises area (mean curvature zero everywhere) and tiles
$bb(R)^3$ with cubic periodicity. Discovered by Alan Schoen at NASA
in 1970. POV-Ray
renders it via an `isosurface`.

#pov-example("examples/gyroid.pov",
  title: "gyroid.pov",
  typst-snippet: "#render(read(\"gyroid.pov\"), antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true)",
  caption: [Schoen gyroid as a thin shell around the zero set; clipped to a sphere.],
  width: 520, height: 390,
  split-at: 19,
  code-size: 7pt,
  image-width: 72%,
  antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true)

#pagebreak(weak: true)
== Lissajous knot $8_(21)$

Parametric space curve

$ bold(r)(t) = 0.75 mat(cos(3 t + 0.1); cos(4 t + 0.7); cos(7 t)), quad t in [0, 2 pi] $

with frequencies $(3, 4, 7)$ (pairwise coprime, phases
$(0.1, 0.7, 0)$) — a prime knot with 8 crossings, classified as
$8_(21)$ in the #link("https://en.wikipedia.org/wiki/List_of_prime_knots")[Rolfsen table]. See
#link("https://en.wikipedia.org/wiki/Lissajous_knot")[Wikipedia on Lissajous knots].

#pov-example("examples/knot.pov",
  title: "knot.pov",
  typst-snippet: "#render(read(\"knot.pov\"), antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true)",
  caption: [Lissajous knot $8_(21)$],
  width: 480, height: 320,
  split-at: 19,
  image-width: 80%,
  antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true)

#pagebreak(weak: true)
== Hopf fibration

In geometry, the Hopf fibration gives a partition of the
$3$-dimensional sphere $S^3$ by great circles. More precisely, it
defines a fibred structure on $S^3$: the base space is the
$2$-dimensional sphere $S^2$, and the model fibre is a circle $S^1$.
In particular, this means there exists a projection map
$p : S^3 arrow.r S^2$ whose preimages of each point of $S^2$ are
circles. This structure was discovered by Heinz Hopf in 1931. See #link("https://en.wikipedia.org/wiki/Hopf_fibration")[Wikipedia
on the Hopf fibration].

#pov-example("examples/hopf.pov",
  title: "hopf.pov",
  typst-snippet: "#render(read(\"hopf.pov\"), antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true)",
  caption: [20 Hopf fibres over two parallels of $S^2$, coloured by hue of base point.],
  width: 600, height: 400,
  split-at: 21,
  code-size: 7pt,
  image-width: 80%,
  antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true)

#pagebreak(weak: true)
== Advanced lighting

POV-Ray ships advanced light-transport features — refraction with
chromatic dispersion, photon-mapped caustics, radiosity for indirect
illumination, area lights with soft shadows, and volumetric media.
This example exercises one of them: a wavy water surface (index of
refraction $n = 1.33$) refracts incident sunlight by Snell's law,
and the bent rays concentrate onto the pool floor as the iconic
shimmering caustic mesh. POV-Ray computes this by Jensen's photon
mapping (1996): a pre-pass shoots photons from the light, tracks
each through the wave-perturbed water normals, and stores landing
positions in a kd-tree; the render then gathers nearby photons at
each surface point. See
#link("https://en.wikipedia.org/wiki/Caustic_(optics)")[Wikipedia on caustics]
and #link("https://en.wikipedia.org/wiki/Photon_mapping")[photon mapping].

#pov-example("examples/caustic.pov",
  title: "caustic.pov",
  typst-snippet: "#render(read(\"caustic.pov\"))",
  caption: [Refractive caustics under a wavy water surface ($n = 1.33$); photon mapping concentrates the sunlight onto the pool floor.],
  width: 360, height: 270,
  split-at: 21,
  code-size: 7pt)

= Debugging 

POV-Ray parse-time errors surface as typst compile errors with a
gcc-style location and source-line preview, courtesy of a parser hook
in our build. `#error "msg"` is the supported authoring-time abort —
test it from your scene to verify the diagnostic plumbing.

For visual orientation, draw a coordinate frame alongside the scene:

#pov-example("examples/debug-axes.pov",
  title: "debug-axes.pov",
  typst-snippet: "#render(read(\"debug-axes.pov\"), antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true)",
  caption: [Origin-centred RGB axes (red = x, green = y, blue = z)],
  width: 320, height: 220,
  split-at: 17,
  code-size: 7pt,
  antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true)

#pagebreak()

= Further reading and other examples

#set list(indent: 1em, body-indent: 0.5em, spacing: 0.8em)

- *POV-Ray official documentation* \
  #link("https://www.povray.org/documentation/") \

- *Paul Bourke — Geometry* \
  #link("https://paulbourke.net/geometry/") \
  Marching cubes, minimal surfaces, Platonic solids, aperiodic
  tilings, most with POV-Ray source.

- *POV-Ray official — Object and Scene Files* \
  #link("https://www.povray.org/resources/links/POV-Ray_Include_Macro_and_Object_Files/Object_and_Scene_Files/")
  \
  Community scene files and reusable macro libraries.

- *Friedrich Lohmüller — POV-Ray tutorial on shapes* \
  #link("https://www.f-lohmueller.de/pov_tut/all_shapes/shapes000e.htm") \
  Visual walkthrough of every primitive and CSG idiom, from spheres
  and cylinders through text, isosurfaces, and height fields — each
  with its SDL snippet and rendered output.

- *Michael Scharrer — POV-Ray scenes* \
  #link("https://mscharrer.net/povray/scenes/") \
  ~22 algorithmic and fractal scenes, strong on CSG composition and
  mathematical visualisation; source available per scene.

- #link("http://dataduppedings.no/subcube/POV-Ray/index.html"), #link("http://bugman123.com/"), ...

= Render times <render-times>

Render times for each gallery scene, measured with an
AMD Ryzen 9 9950X (Zen 5, 5.7 GHz). 

#align(center)[
  #set text(size: 9.5pt)
  #table(
    columns: (auto, auto, auto, auto),
    align: (left, center, center, right),
    stroke: 0.4pt,
    inset: 5pt,
    table.header(
      [*Scene*], [*Resolution*],
      [*AA (threshold / depth)*], [*Median time*],
    ),
    [`basic.pov`],   [480×300], [—],         [2.3 s],
    [`csg.pov`],     [480×360], [—],         [3.4 s],
    [`julia.pov`],   [420×315], [0.4 / 2],   [4.3 s],
    [`clebsch.pov`], [480×360], [—],         [4.1 s],
    [`gyroid.pov`],  [520×390], [0.7 / 2],   [19.3 s],
    [`knot.pov`],    [480×320], [0.7 / 2],   [15.1 s],
    [`hopf.pov`],    [600×400], [0.7 / 2],   [7.7 s],
    [`caustic.pov`], [360×270], [—],         [13.5 s],
  )
]

The Gyroid takes longer because I tweaked it to look stylized/beautiful (clipped smoothly with a bounding sphere), and unfortunately raymarching isn't free. Refraction neither, same for caustic.pov. 

= Conclusion

POV-Ray has a lot of features, too many to show all of them here. Feel free to read its documentation to learn about its possibilities and look for examples online. Many wikipedia pages (in algebraic geometry, topology, and so on) use POV-Ray to visualize all sorts of things: https://commons.wikimedia.org/wiki/Category:POV-Ray

#pagebreak(weak: true)

// ---- Appendix: switch to letter-numbered headings --------------------
#counter(heading).update(0)
#set heading(numbering: "A.1")

= Appendix

== Changelog <changelog>

Release dates are the date the version's git tag was published on
#link("https://github.com/bernsteining/povrayst")[GitHub].

#let release(version, date, body) = {
  block(above: 1em, below: 0.6em)[
    #text(weight: "bold", size: 12pt)[#version]
    #h(0.6em)
    #text(fill: luma(110), style: "italic")[#date]
  ]
  body
}

#release("0.1.1", "2026-08-31")[
  - *Raw RGBA output.* The plugin now returns raw RGBA8 pixels instead of
    encoding a PNG; Typst embeds them directly, skipping a PNG encode in
    the plugin and a PNG decode on the Typst side. Same pixels, less work.
  - *Smaller WebAssembly.* With PNG output gone, `libpng` and `zlib` are
    no longer compiled into the binary.
]

#release("0.1.0", "2026-06-02")[
  - First public release: POV-Ray 3.8 wrapped as a Typst WebAssembly
    plugin, with the `render()` / `pov()` API, Typst-side `#include`
    expansion, POV-Ray syntax highlighting, and this documentation.
]
