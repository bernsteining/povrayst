global_settings { assumed_gamma 1.0 }

background { color rgbt <0, 0, 0, 1> }

camera {
  location <0, 1, -6>
  look_at <0, 0.1, 0>
  angle 42
  right x*image_width/image_height
}
light_source { <4, 6, -5> color rgb 1.4 }

sphere {
  0, 1
  pigment { rgb <0.20, 0.55, 0.90> }
  finish { specular 0.7 roughness 0.01 }
  no_shadow
}
