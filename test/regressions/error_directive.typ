// Regression: POV-Ray's #error directive must surface as a typst compile
// error with file:line:col location and the message text.
// expect: input.pov:1:8: Parse halted by #error directive: POVRAY_TEST_FAILURE_OK

#import "../../pkg/povray.typ": pov

#pov("#error \"POVRAY_TEST_FAILURE_OK\"
camera { location <0, 0, -5> look_at 0 }
sphere { 0, 1 pigment { rgb 1 } }",
  width: 200, height: 150)
