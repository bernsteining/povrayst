background { color rgbt <0, 0, 0, 1> }
global_settings { assumed_gamma 1.0 max_trace_level 2 }

camera
  {
  location <0, 0, -25>
  right <1,0,0> up <0,1,0>
  look_at  <0, 0, 0>
  angle 3.5
  }

light_source { <0, 20, -50> color rgb 1.6 }

#declare r_tube = 0.04;
#declare num_steps = 17;
#declare step_size = 1/num_steps;

sphere_sweep
  {
  b_spline num_steps+3,
  #declare N = -1;
  #while(N <= num_steps + 1)
    #declare theta = 2 * pi * N * step_size;
    < 0.75*cos(3*theta + 0.1),
      0.75*cos(4*theta + 0.7),
      0.75*cos(7*theta) >, r_tube
    #declare N = N + 1;
  #end
  pigment { color rgb <0, 0.25, 1> }
  finish
    {
    ambient 0.18
    diffuse 0.75
    specular 0.95
    roughness 0.012
    }
  no_shadow
  }
