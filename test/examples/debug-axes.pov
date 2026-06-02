global_settings { assumed_gamma 1.0 max_trace_level 2 }
background { color rgbt <0, 0, 0, 1> }

camera {
  location <25, 25, 25>
  look_at  <0, 0.7, 0>
  angle 8
}

light_source { <4, 6, -4> rgb 1.4 }

sphere {
  <0, 1, 2>, 0.35
  finish { specular 0.1 diffuse 0.1 }
}

#macro Axis(dir, col, len)
  cylinder { 0, len*dir, 0.035
    pigment { rgb col } finish { ambient 0.2 diffuse 0.7 } no_shadow }
  cone { len*dir, 0.10, (len+0.25)*dir, 0
    pigment { rgb col } finish { ambient 0.2 diffuse 0.7 } no_shadow }
  #local i = 1;
  #while (i <= len)
    sphere { i*dir, 0.06
      pigment { rgb col*0.6 } finish { ambient 0.2 diffuse 0.7 } no_shadow }
    #local i = i + 1;
  #end
#end

Axis(x, <1.0, 0.0, 0.0>, 3)
Axis(y, <0.0, 1.0, 0.0>, 3)
Axis(z, <0.0, 0.0, 1.0>, 3)
