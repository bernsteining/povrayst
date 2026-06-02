global_settings {
  assumed_gamma 1.0
  max_trace_level 6
  radiosity {
    pretrace_start 0.08
    pretrace_end 0.02
    count 100
    nearest_count 6
    error_bound 0.4
    recursion_limit 2
  }
}
background { color rgbt <0, 0, 0, 1> }

camera { location <0, 1.6, -7> look_at <0, 0.5, 0> angle 32 }

light_source {
  <-4, 8, -6> color rgb <1.0, 0.92, 0.78> * 1.4
}

fog {
  fog_type 1
  distance 35
  color rgb <0.10, 0.13, 0.20>
}

plane {
  y, 0
  pigment {
    checker
    color rgb <0.05, 0.05, 0.05>,
    color rgb <0.65, 0.65, 0.65>
    scale 0.7
  }
  finish { ambient 0 diffuse 0.85 }
}

cylinder {
  <-1.5, 0, 0.2>, <-1.5, 1.6, 0.2>, 0.4
  pigment { rgb <0.92, 0.93, 0.95> }
  finish {
    ambient 0 diffuse 0.0
    reflection { 0.85 metallic } metallic
    specular 1 roughness 0.002
  }
}

sphere {
  <0, 0.7, 0>, 0.7
  pigment { rgbt <0.95, 0.97, 1.0, 0.96> }
  finish {
    ambient 0 diffuse 0.02
    specular 0.5 roughness 0.005
    reflection { 0.06, 0.4 fresnel on }
    conserve_energy
  }
  interior { ior 1.5 }
}

box {
  <1.0, 0, -0.5>, <2.4, 1.2, 0.7>
  pigment { rgb <0.85, 0.20, 0.18> }
  finish { ambient 0 diffuse 0.92 }
}
