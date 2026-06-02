// Regression: an unbalanced #if without a closing #end must report a
// clean error rather than hang the parser.
// expect: End of file reached but #end expected.

#import "../../pkg/povray.typ": pov

#pov("camera { location <0, 2, -5> look_at 0 angle 35 }
#if (1 = 1) sphere { 0, 1 pigment { rgb 1 } }",
  width: 200, height: 150)
