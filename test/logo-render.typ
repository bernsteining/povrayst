// Standalone renderer for the cover logo — produces a PNG we keep
// on disk and reference from documentation.typ and README.md.
//
//   typst compile --root .. test/logo-render.typ test/examples/logo.png
//
// Re-run only when examples/logo.pov changes.

#import "../pkg/povray.typ": render

#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("examples/logo.pov"), width: 1024, height: 1024,
  antialias: true, aa-threshold: 0.3, aa-depth: 2)
