#import "../../pkg/povray.typ": render
#set page(width: auto, height: auto, margin: 0pt, fill: none)

#let orbit(theta) = (
  "#version 3.7;\n"
  + "global_settings { assumed_gamma 1.0 max_trace_level 2 }\n"
  + "background { color rgbt <0, 0, 0, 1> }\n"
  + "camera { location <" + str(4 * calc.cos(theta))
  + ", 2, " + str(4 * calc.sin(theta)) + "> look_at 0 angle 35 }\n"
  + "light_source { <4, 6, -4> rgb 1.3 }\n"
  + "torus { 1, 0.32 pigment { rgb <0.95, 0.40, 0.15> } "
  + "finish { specular 0.8 roughness 0.02 } rotate x*25 }"
)

#grid(
  columns: 4, column-gutter: 6pt,
  ..(-90deg, -60deg, -30deg, 0deg).map(a => render(
    orbit(a), width: 140, height: 140, quality: 1,
    antialias: false, output-alpha: true,
  )),
)
