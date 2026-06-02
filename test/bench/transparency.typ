#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("../examples/transparency.pov"), width: 160, height: 160,
  output-alpha: true)
