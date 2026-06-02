#version 3.7;
global_settings { assumed_gamma 1.0 }

#include "materials.inc"
#include "stage.inc"

sphere { <-1.8,  0.0, 0>, 0.8 pigment { M_Red }   finish { specular 0.5 } }
sphere { < 0.0, -0.2, 0>, 0.7 pigment { M_Green } finish { specular 0.5 } }
sphere { < 1.8,  0.1, 0>, 0.9 pigment { M_Blue }  finish { specular 0.5 } }

torus {
  0.7, 0.22
  pigment { M_Gold }
  finish { specular 0.7 }
  rotate <70, 10, 0>
  translate <0, 1.4, 0>
}
