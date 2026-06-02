global_settings { assumed_gamma 1.0 max_trace_level 2 }
background { color rgbt <0, 0, 0, 1> }

camera { location <1.7, 1.5, -5.4> look_at <0, 0, 0> angle 42 }

light_source { <-6, 10, -10> color rgb 1.6 }
light_source { < 8,  2,  -2> color rgb <0.20, 0.30, 0.60> shadowless }

cubic {
  <  81, -189, -189, -9, -189, 54, 126, -189, 126, -9,
     81, -189, -9, -189, 126, -9, 81, -9, -9, 1 >
  bounded_by { sphere { 0, 2 } }
  clipped_by { sphere { 0, 1.6 } }
  pigment {
    gradient y
    color_map {
      [0.00 rgb <0.05, 0.10, 0.45>]
      [0.40 rgb <0.10, 0.40, 0.92>]
      [0.75 rgb <0.45, 0.80, 0.98>]
      [1.00 rgb <0.85, 0.95, 1.00>]
    }
    scale 3 translate <0, -1.5, 0>
  }
  finish { ambient 0.07 diffuse 0.85 specular 0.5 roughness 0.025 }
  no_shadow
}

