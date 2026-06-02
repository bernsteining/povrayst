global_settings { assumed_gamma 1.0 max_trace_level 2 }
background { color rgbt <0, 0, 0, 1> }
camera { location <0, 4.6, -10.5> look_at <0, -0.35, 0> angle 32 }
light_source { < 8, 12, -10> color rgb 1.4 }
light_source { <-6,  2,  -3> color rgb <0.35, 0.45, 0.95> shadowless }

#declare r_tube = 0.06;

#macro HopfFiber(theta, phi, hue)
  #local st = sin(theta/2);
  #local ct = cos(theta/2);
  #macro F(psi)
    <ct*cos(psi), st*cos(psi+phi), ct*sin(psi)> / (1 - st*sin(psi+phi))
  #end
  #local P0 = F(0); #local P1 = F(2*pi/3); #local P2 = F(4*pi/3);
  #local n  = vcross(P1-P0, P2-P0);
  #local a2 = vdot(P2-P1, P2-P1);
  #local b2 = vdot(P0-P2, P0-P2);
  #local c2 = vdot(P1-P0, P1-P0);
  #local Cn = (a2*(b2+c2-a2)*P0 + b2*(c2+a2-b2)*P1 + c2*(a2+b2-c2)*P2) / (4*vdot(n,n));
  #local N  = vnormalize(n);
  #local T  = (abs(N.y) < 0.9 ? <0,1,0> : <1,0,0>);
  #local E1 = vnormalize(vcross(T, N));
  #local E3 = vcross(N, E1);
  torus {
    vlength(P0-Cn), r_tube
    pigment { rgb <0.55+0.4*cos(2*pi*hue), 0.55+0.4*cos(2*pi*hue+2*pi/3), 0.55+0.4*cos(2*pi*hue+4*pi/3)> }
    finish { ambient 0.1 diffuse 0.55 specular 0.8 roughness 0.02 }
    matrix <E1.x,E1.y,E1.z, N.x,N.y,N.z, E3.x,E3.y,E3.z, Cn.x,Cn.y,Cn.z>
    no_shadow
  }
#end

#declare T = array[2] { 2*pi/5, 3*pi/5 };
#local i = 0;
#while (i < 2)
  #local j = 0;
  #while (j < 10)
    HopfFiber(T[i], 2*pi*j/10, j/10 + i/2)
    #local j = j + 1;
  #end
  #local i = i + 1;
#end
