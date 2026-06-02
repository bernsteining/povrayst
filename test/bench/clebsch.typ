#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("../examples/clebsch.pov"), width: 480, height: 360,
  output-alpha: true)
