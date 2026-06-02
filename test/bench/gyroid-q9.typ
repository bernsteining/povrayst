#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("../examples/gyroid.pov"), width: 520, height: 390,
  quality: 9, antialias: false, output-alpha: true)
