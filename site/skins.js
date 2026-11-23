/* Skin drawings shared by the site. Canvas 2D, no dependencies. */
(function(){
  var RM = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  function css(n){return getComputedStyle(document.documentElement).getPropertyValue(n).trim()}
  function jelly(ctx,w,h,t,L,opt){
    opt=opt||{};
    ctx.clearRect(0,0,w,h);
    var s=Math.min(w,h), cx=w/2, cy=h*0.56;
    var r=s*(0.14+0.026*L)*(opt.k||1), bob=RM?0:Math.sin(t*2)*s*0.012, sq=RM?0:Math.sin(t*2+1)*0.03;
    var violet=css('--violet'),pink=css('--pink'),aqua=css('--aqua'),ink=css('--ink');
    var bodyY=cy+bob;
    // halo
    var ha=0.10+0.045*L;
    var g=ctx.createRadialGradient(cx,bodyY,r*0.4,cx,bodyY,r*(2.1+L*0.08));
    g.addColorStop(0,hexA(violet,ha*1.6));g.addColorStop(1,hexA(violet,0));
    ctx.fillStyle=g;ctx.beginPath();ctx.arc(cx,bodyY,r*(2.2+L*0.08),0,7);ctx.fill();
    // rings behind
    var rings=Math.min(4,Math.floor((L-1)/2));
    for(var i=0;i<rings;i++) ring(ctx,cx,bodyY,r*(1.35+i*0.28),t,i,s,[violet,pink,aqua,violet][i],false);
    // crown of light
    if(L>=7){ for(var k=-3;k<=3;k++){var a=-Math.PI/2+k*0.28,len=r*(0.55+0.18*Math.cos(k*0.8)+ (RM?0:0.08*Math.sin(t*3+k)));
      var x1=cx+Math.cos(a)*r*1.12,y1=bodyY+Math.sin(a)*r*1.12*(1-sq),x2=cx+Math.cos(a)*(r*1.12+len),y2=bodyY+Math.sin(a)*(r*1.12+len);
      var lg=ctx.createLinearGradient(x1,y1,x2,y2);lg.addColorStop(0,hexA(aqua,.9));lg.addColorStop(1,hexA(pink,0));
      ctx.strokeStyle=lg;ctx.lineWidth=s*0.012;ctx.lineCap='round';ctx.beginPath();ctx.moveTo(x1,y1);ctx.lineTo(x2,y2);ctx.stroke();}}
    // body
    ctx.save();ctx.translate(cx,bodyY);ctx.scale(1+sq,1-sq);
    ctx.beginPath();
    for(var j=0;j<=48;j++){var th=j/48*Math.PI*2,wob=RM?0:Math.sin(th*3+t*1.6)*0.018+Math.sin(th*5-t*1.1)*0.01;
      var rr=r*(1+wob);var px=Math.cos(th)*rr,py=Math.sin(th)*rr*0.96;j?ctx.lineTo(px,py):ctx.moveTo(px,py);}
    ctx.closePath();
    var bg=ctx.createLinearGradient(-r,-r,r,r);bg.addColorStop(0,aqua);bg.addColorStop(.45,violet);bg.addColorStop(1,pink);
    ctx.fillStyle=bg;ctx.fill();
    var sh=ctx.createRadialGradient(-r*.35,-r*.45,r*.05,-r*.2,-r*.3,r*.9);sh.addColorStop(0,'rgba(255,255,255,.55)');sh.addColorStop(.5,'rgba(255,255,255,.08)');sh.addColorStop(1,'rgba(255,255,255,0)');
    ctx.fillStyle=sh;ctx.fill();
    // face
    var blink=(!RM&&(t%4.2)<0.12)?0.15:1, ey=-r*0.04, ex=r*0.3, er=r*0.1;
    ctx.fillStyle='#1b1033';
    ctx.beginPath();ctx.ellipse(-ex,ey,er*0.8,er*1.15*blink,0,0,7);ctx.fill();
    ctx.beginPath();ctx.ellipse(ex,ey,er*0.8,er*1.15*blink,0,0,7);ctx.fill();
    ctx.fillStyle='rgba(255,255,255,.9)';ctx.beginPath();ctx.arc(-ex+er*.25,ey-er*.4,er*.28,0,7);ctx.fill();ctx.beginPath();ctx.arc(ex+er*.25,ey-er*.4,er*.28,0,7);ctx.fill();
    ctx.strokeStyle='#1b1033';ctx.lineWidth=r*0.05;ctx.lineCap='round';ctx.beginPath();ctx.arc(0,r*0.2,r*0.2,0.15*Math.PI,0.85*Math.PI);ctx.stroke();
    ctx.fillStyle='rgba(255,92,174,.35)';ctx.beginPath();ctx.ellipse(-ex*1.25,r*0.2,er*.9,er*.55,0,0,7);ctx.fill();ctx.beginPath();ctx.ellipse(ex*1.25,r*0.2,er*.9,er*.55,0,0,7);ctx.fill();
    ctx.restore();
    // front halves of rings, sparkles, orbiters
    for(var q=0;q<rings;q++) ring(ctx,cx,bodyY,r*(1.35+q*0.28),t,q,s,[violet,pink,aqua,violet][q],true);
    var sp=Math.max(0,(L-4))*2;
    for(var z=0;z<sp;z++){var ang=z*2.4+(RM?0:t*0.5),rad=r*(1.6+0.9*((z*37)%10)/10),tw=RM?1:0.5+0.5*Math.sin(t*3+z);
      star(ctx,cx+Math.cos(ang)*rad,bodyY+Math.sin(ang)*rad*0.8,s*(0.012+0.008*((z*13)%5)/5)*(0.6+tw),[aqua,pink,violet][z%3]);}
    if(L>=9){for(var o=0;o<3;o++){var oa=o*2.094+(RM?0.4:t*0.7),orr=r*2.05;mini(ctx,cx+Math.cos(oa)*orr,bodyY+Math.sin(oa)*orr*0.55,r*0.2,[aqua,pink,violet][o]);}}
  }
  function ring(ctx,cx,cy,rr,t,i,s,col,front){
    var tilt=0.32+i*0.06,rot=(RM?0:t*(0.4+i*0.12))*(i%2?-1:1)+i;
    ctx.save();ctx.translate(cx,cy);ctx.rotate(-0.35+i*0.5);
    ctx.strokeStyle=hexA(col,front?0.9:0.35);ctx.lineWidth=s*0.008;
    ctx.beginPath();
    if(front)ctx.ellipse(0,0,rr,rr*tilt,0,0,Math.PI);else ctx.ellipse(0,0,rr,rr*tilt,0,Math.PI,Math.PI*2);
    ctx.stroke();
    if(front){var bx=Math.cos(rot)*rr,by=Math.sin(rot)*rr*tilt;if(by>=0){ctx.fillStyle=col;ctx.beginPath();ctx.arc(bx,by,s*0.012,0,7);ctx.fill();}}
    ctx.restore();
  }
  function star(ctx,x,y,r,col){ctx.fillStyle=col;ctx.beginPath();for(var i=0;i<8;i++){var a=i*Math.PI/4,rr=i%2?r*0.35:r;ctx.lineTo(x+Math.cos(a)*rr,y+Math.sin(a)*rr);}ctx.closePath();ctx.fill();}
  function mini(ctx,x,y,r,col){var g=ctx.createRadialGradient(x-r*.3,y-r*.3,r*.1,x,y,r);g.addColorStop(0,'#fff');g.addColorStop(.3,col);g.addColorStop(1,hexA(col,.6));ctx.fillStyle=g;ctx.beginPath();ctx.arc(x,y,r,0,7);ctx.fill();ctx.fillStyle='#1b1033';ctx.beginPath();ctx.arc(x-r*.3,y,r*.12,0,7);ctx.fill();ctx.beginPath();ctx.arc(x+r*.3,y,r*.12,0,7);ctx.fill();}
  function hexA(c,a){c=c.trim();if(c[0]!=='#')return c;var n=parseInt(c.slice(1),16);return 'rgba('+((n>>16)&255)+','+((n>>8)&255)+','+(n&255)+','+Math.max(0,Math.min(1,a))+')';}

  function pixel(ctx,w,h,L,t){ctx.clearRect(0,0,w,h);var u=Math.floor(Math.min(w,h)/16),ox=Math.floor((w-u*16)/2),oy=Math.floor((h-u*16)/2)+u;
    function px(x,y,wd,ht,c){ctx.fillStyle=c;ctx.fillRect(ox+x*u,oy+y*u,(wd||1)*u,(ht||1)*u)}
    var body='#33d6c4',dark='#2b2066',lt='#8af1e6',violet=css('--violet'),pink=css('--pink'),amber='#ffcf5c';
    px(5,2,6,1,dark);px(4,3,8,1,dark);px(3,4,10,6,dark);px(4,10,8,1,dark);px(5,11,6,1,dark);
    px(4,4,8,1,body);px(4,5,8,5,body);px(5,10,6,1,body);px(5,4,3,1,lt);
    px(5,6,2,2,dark);px(9,6,2,2,dark);px(5,6,1,1,'#fff');px(9,6,1,1,'#fff');px(6,9,4,1,dark);
    px(4,12,2,2,dark);px(10,12,2,2,dark);
    px(7,0,2,2,L>=8?amber:'#3aff9a');px(7,1,2,1,dark);
    if(L>=8){px(2,8,1,1,pink);px(13,8,1,1,pink);px(4,10,8,1,pink);px(1,3,1,1,amber);px(14,2,1,1,'#fff');px(13,4,1,1,amber);px(3,0,1,1,'#fff');px(12,0,1,1,pink);
      px(5,2,6,1,violet);px(6,1,4,1,violet)}}
  function pocket(ctx,w,h,L){ctx.clearRect(0,0,w,h);var s=Math.min(w,h),x=w/2-s*.3,y=h/2-s*.4,bw=s*.6,bh=s*.8;
    function rr(a,b,c,d,r,f){ctx.fillStyle=f;ctx.beginPath();ctx.roundRect(a,b,c,d,r);ctx.fill()}
    rr(x,y,bw,bh,s*.08,'#e9e5d6');rr(x+bw*.1,y+bh*.08,bw*.8,bh*.46,s*.04,'#3a3550');
    var sc=L>=8?'#bff3c9':'#c9e6a0';rr(x+bw*.14,y+bh*.11,bw*.72,bh*.4,s*.03,sc);
    ctx.fillStyle='#2a3318';var cx=x+bw/2,cy=y+bh*.3;ctx.fillRect(cx-bw*.2,cy-bh*.06,bw*.07,bh*.1);ctx.fillRect(cx+bw*.13,cy-bh*.06,bw*.07,bh*.1);ctx.fillRect(cx-bw*.1,cy+bh*.07,bw*.2,bh*.03);
    ctx.fillStyle='#4b4770';ctx.fillRect(x+bw*.16,y+bh*.68,bw*.2,bh*.04);ctx.fillRect(x+bw*.24,y+bh*.62,bw*.04,bh*.16);
    ctx.fillStyle='#e0446a';ctx.beginPath();ctx.arc(x+bw*.72,y+bh*.74,s*.04,0,7);ctx.fill();ctx.fillStyle='#3d6ee0';ctx.beginPath();ctx.arc(x+bw*.58,y+bh*.68,s*.04,0,7);ctx.fill();
    if(L>=8){ctx.fillStyle=css('--aqua');ctx.fillRect(x+bw*.1,y+bh*.88,bw*.8,bh*.025);ctx.fillStyle='#ffcf5c';ctx.beginPath();ctx.arc(x+bw*.18,y+bh*.04,s*.03,0,7);ctx.fill();ctx.fillStyle=css('--pink');ctx.beginPath();ctx.arc(x+bw*.3,y+bh*.04,s*.03,0,7);ctx.fill();
      star(ctx,x+bw*1.05,y+bh*.12,s*.05,'#ffcf5c');star(ctx,x-bw*.05,y+bh*.5,s*.04,css('--pink'))}}

  window.BuddySkins={jelly:jelly,pixel:pixel,pocket:pocket,reducedMotion:RM};
})();
