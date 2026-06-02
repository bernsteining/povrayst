camera {
  location <0, 3, -7>
  look_at <0, 0.5, 0>
  angle 35
}

light_source { < 5,  8, -6> color rgb 1.2 }
light_source { <-4,  3, -2> color rgb 0.4 }

background { color rgb <0.62, 0.78, 0.92> }

plane {
  y, -1
  pigment { checker rgb <0.92, 0.92, 0.90>, rgb <0.25, 0.28, 0.32> scale 0.7 }
  finish { diffuse 0.7 }
}
