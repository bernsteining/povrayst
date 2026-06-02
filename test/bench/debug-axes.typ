#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("../examples/debug-axes.pov"), width: 360, height: 270,
  antialias: true, aa-threshold: 0.7, aa-depth: 2)
