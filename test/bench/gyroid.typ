#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("../examples/gyroid.pov"), width: 520, height: 390,
  antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true)
