#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("../examples/basic.pov"), width: 480, height: 300,
  quality: 9, antialias: false)
