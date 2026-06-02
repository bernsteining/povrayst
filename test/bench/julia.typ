#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("../examples/julia.pov"), width: 420, height: 315,
  antialias: true, aa-threshold: 0.4, aa-depth: 2, output-alpha: true)
