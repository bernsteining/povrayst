#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("../examples/hopf.pov"), width: 600, height: 400,
  antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true)
