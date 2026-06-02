// Regression: referencing an undeclared identifier in a numeric context
// must report it cleanly with file:line:col + the offending name.
// expect: undeclared identifier 'R' found

#import "../../pkg/povray.typ": pov

#pov("camera { location <0, 2, -5> look_at 0 angle 35 }
sphere { 0, R pigment { rgb 1 } }",
  width: 200, height: 150)
