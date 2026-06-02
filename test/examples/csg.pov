global_settings { assumed_gamma 1.0 max_trace_level 2 }
background { color rgbt <0, 0, 0, 1> }
camera { location <2.6, 2.4, -4.2> look_at <0, 0, 0> angle 38 }
light_source { < 6, 9, -8> color rgb 1.4 }
light_source { <-4, 2, -2> color rgb <0.4, 0.5, 0.95> shadowless }

#declare RoundedCube = intersection {
  box { -<1,1,1>, <1,1,1> }
  sphere { 0, 1.32 }
}

#declare Bores = union {
  cylinder { -1.2*x, 1.2*x, 0.42 }
  cylinder { -1.2*y, 1.2*y, 0.42 }
  cylinder { -1.2*z, 1.2*z, 0.42 }
}

difference {
  object { RoundedCube }
  object { Bores }
  pigment { rgb <0.96, 0.55, 0.18> }
  finish { ambient 0.12 diffuse 0.55 specular 1.0 roughness 0.01 }
  no_shadow
}
