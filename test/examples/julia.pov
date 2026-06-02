global_settings { assumed_gamma 1.0 max_trace_level 2 }
background { color rgbt <0, 0, 0, 1> }

camera { location <0, 2, -4.5> look_at <0, 0, 0> angle 38 }
light_source { <4, 6, -6> color rgb 1.6 }
light_source { <-5, 3, -2> color rgb <0.5, 0.3, 0.8> shadowless }

julia_fractal {
  <-0.083, 0.0, -0.83, -0.025>
  quaternion
  sqr
  max_iteration 8
  precision 50
  slice <0, 0, 0, 1>, 0.15

  pigment {
    spherical
    color_map {
      [0.00 rgb <0.95, 0.55, 0.18>]
      [0.30 rgb <0.95, 0.78, 0.40>]
      [0.55 rgb <0.45, 0.80, 0.95>]
      [0.80 rgb <0.10, 0.30, 0.80>]
      [1.00 rgb <0.05, 0.06, 0.25>]
    }
    scale 1.6
  }
  finish {
    ambient 0.08
    diffuse 0.85
    specular 0.4
    roughness 0.020
  }
  rotate <-20, 30, 0>
  no_shadow
}
