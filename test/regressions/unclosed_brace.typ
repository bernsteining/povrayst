// Regression: an unclosed brace used to hang the parser (our -fno-exceptions
// build no-ops the throws POV-Ray uses to recover, so without our Get_Token
// short-circuit the parser would spin forever). Now it must fail fast with a
// clean compiler-style error.
// expect: input.pov:2:13: No matching }, End of File found instead

#import "../../pkg/povray.typ": pov

#pov("camera { location <0, 2, -5> look_at 0 angle 35 }
sphere { 0, 1 ",
  width: 200, height: 150)
