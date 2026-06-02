#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)
#render(read("../examples/solenoid.pov"), width: 480, height: 360,
  antialias: false, output-alpha: true)
