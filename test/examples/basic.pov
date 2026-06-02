global_settings { assumed_gamma 1.0 }

camera {
  location <0, 2, -6>
  look_at  <0, 0, 0>
  right    -1.333*x
  up        0.833*y
  angle 35
}
light_source { <4, 6, -6> color rgb 1.2 }
background { color rgb <0.55, 0.75, 0.95> }

sphere {
  0, 1
  pigment { rgb <0.90, 0.40, 0.15> }
  finish { specular 0.5 diffuse 0.7 }
}

plane {
  y, -1
  pigment { rgb <0.92, 0.92, 0.88> }
  finish { diffuse 0.6 }
}
