#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("../examples/basic.pov"), width: 400, height: 300,
  quality: 2, antialias: false)
