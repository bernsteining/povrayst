#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("../examples/showcase.pov"), width: 480, height: 320,
  antialias: true, aa-threshold: 0.7, aa-depth: 2, output-alpha: true)
