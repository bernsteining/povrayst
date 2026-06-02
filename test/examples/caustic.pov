global_settings {
  assumed_gamma 1.0
  max_trace_level 3
  photons { spacing 0.10 gather 3, 8 }
}
background { color rgbt <0, 0, 0, 1> }
camera { location <0, 5.5, -3.5> look_at <0, -1.6, 1.2> angle 38 }

light_source {
  <-2, 15, -4> color rgb <1.0, 0.88, 0.55> * 2.4
  photons { refraction on reflection off }
}

plane {
  y, -2
  pigment {
    checker
    color rgb <0.05, 0.05, 0.05>,
    color rgb <0.29, 0.29, 0.29>
    scale 0.6
  }
  finish { ambient 0.04 diffuse 0.85 }
}

disc {
  <0, 0, 0>, y, 4
  pigment { rgbt <0.85, 0.92, 1.0, 0.94> }
  finish {
    ambient 0
    diffuse 0.02
    specular 0.3
    roughness 0.012
    reflection 0.04
  }
  normal {
    ripples 0.6
    frequency 2.5
    turbulence 0.15
    scale 1.2
  }
  interior { ior 1.33 }
  photons { target refraction on collect off }
}
