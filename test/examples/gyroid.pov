global_settings { assumed_gamma 1.0 max_trace_level 2 }
background { color rgbt <0, 0, 0, 1> }

camera { location <8, 6, -11> look_at <0, -0.3, 0> angle 44 }

light_source { <6, 10, -8> color rgb 1.2 }
light_source { <-5, 1, -2> color rgb <0.22, 0.28, 0.50> shadowless }

#declare K = 2.0;
#declare R = 4;
#declare Slab     = function(x,y,z) {
  abs(sin(K*x)*cos(K*y) + sin(K*y)*cos(K*z) + sin(K*z)*cos(K*x))
  - (0.15 + 0.32 * (x*x + y*y + z*z) / (R*R))
}
#declare SphereSD = function(x,y,z) { sqrt(x*x + y*y + z*z) - R }
#declare SmoothMax = function(a, b, k) {
  (a + b + sqrt((a - b)*(a - b) + k*k)) / 2
}

isosurface {
  function { SmoothMax(Slab(x, y, z), SphereSD(x, y, z), 0.25) }
  contained_by { sphere { 0, R + 0.15 } }
  threshold 0
  accuracy 0.018
  max_gradient 2
  open
  pigment {
    spherical
    color_map {
      [0.00 rgb <0.85, 0.90, 0.95>]
      [0.20 rgb <0.55, 0.80, 0.95>]
      [0.50 rgb <0.20, 0.50, 0.92>]
      [0.80 rgb <0.10, 0.25, 0.72>]
      [1.00 rgb <0.15, 0.08, 0.40>]
    }
    scale R
  }
  finish { ambient 0.06 diffuse 0.88 specular 0.3 roughness 0.04 }
  no_shadow
}
