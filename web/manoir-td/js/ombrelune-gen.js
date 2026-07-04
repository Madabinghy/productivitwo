/* OMBRELUNE — moteur de génération procédurale (100% vanilla).
   Même graine + même difficulté = même partie, toujours :
   - mission du portail → graine dérivée de l'action Gantt (reproductible, pas de re-tirage)
   - partie libre → graine aléatoire à chaque fois
   PR 1 : générateur d'énigmes de miroirs. (Enquête et Salle des Ombres suivront.) */
(function(){
  'use strict';

  // —— PRNG à graine (mulberry32) : déterministe, rapide, suffisant pour du contenu.
  function mulberry32(a){ a|=0; return function(){ a=a+0x6D2B79F5|0; var t=Math.imul(a^a>>>15,1|a); t=t+Math.imul(t^t>>>7,61|t)^t; return ((t^t>>>14)>>>0)/4294967296; }; }
  function hashStr(s){ var h=0; s=String(s||''); for(var i=0;i<s.length;i++) h=(h*31+s.charCodeAt(i))>>>0; return h; }

  // ============ Énigme des miroirs ============
  // Génération PROUVÉE résoluble : on construit le chemin du rayon d'abord (chaque
  // virage pose un miroir), la fin du chemin devient le sceau. Puis on brouille les
  // orientations et on ajoute leurres + murs HORS du chemin solution.
  var ROWS=9, COLS=7;
  var DIRS={E:[0,1],W:[0,-1],N:[-1,0],S:[1,0]};
  function reflect(dir,o){ return o==='/' ? {E:'N',N:'E',W:'S',S:'W'}[dir] : {E:'S',S:'E',W:'N',N:'W'}[dir]; }
  function orientFor(dir,want){ return reflect(dir,'/')===want ? '/' : '\\'; }
  function key(r,c){ return r+','+c; }
  function inGrid(r,c){ return r>=0&&r<ROWS&&c>=0&&c<COLS; }
  // marge disponible depuis (r,c) en direction d
  function room(r,c,d){ var v=DIRS[d],n=0; while(inGrid(r+v[0],c+v[1])){ r+=v[0]; c+=v[1]; n++; } return n; }

  // trace générique (réplique du moteur de la page, avec murs) — sert à VÉRIFIER
  function solves(spec,orient){
    var wall={}; (spec.WALLS||[]).forEach(function(w){ wall[key(w.r,w.c)]=1; });
    var mAt={}; Object.keys(spec.MPOS).forEach(function(k){ mAt[key(spec.MPOS[k].r,spec.MPOS[k].c)]=k; });
    var r=spec.SOURCE.r, c=spec.SOURCE.c, dir=spec.SOURCE.dir;
    for(var i=0;i<60;i++){
      var v=DIRS[dir], nr=r+v[0], nc=c+v[1];
      if(!inGrid(nr,nc) || wall[key(nr,nc)]) return false;
      r=nr; c=nc;
      if(r===spec.TARGET.r && c===spec.TARGET.c && dir===spec.TARGET.enter) return true;
      var id=mAt[key(r,c)];
      if(id) dir=reflect(dir,orient[id]);
    }
    return false;
  }

  function tryBuild(rnd,nTurn){
    // source sur un bord, rayon vers l'intérieur
    var side=['W','E','N','S'][Math.floor(rnd()*4)];
    var r,c,dir;
    if(side==='W'){ c=0; r=1+Math.floor(rnd()*(ROWS-2)); dir='E'; }
    else if(side==='E'){ c=COLS-1; r=1+Math.floor(rnd()*(ROWS-2)); dir='W'; }
    else if(side==='N'){ r=0; c=1+Math.floor(rnd()*(COLS-2)); dir='S'; }
    else { r=ROWS-1; c=1+Math.floor(rnd()*(COLS-2)); dir='N'; }
    var SOURCE={r:r,c:c,dir:dir};
    var path={}; path[key(r,c)]=1;
    var mirrors=[];
    var advance=function(min){ // avance de min..min+2 cases en marquant le chemin ; null si bloqué
      var k=min+Math.floor(rnd()*3), v=DIRS[dir];
      if(room(r,c,dir)<k) return null;
      for(var i=0;i<k;i++){ r+=v[0]; c+=v[1]; if(path[key(r,c)]) return null; path[key(r,c)]=1; }
      return true;
    };
    for(var m=0;m<nTurn;m++){
      if(!advance(2)) return null;
      // virage perpendiculaire avec au moins 3 cases de marge
      var opts=(dir==='E'||dir==='W')?['N','S']:['E','W'];
      if(rnd()<0.5) opts.reverse();
      var want=null;
      for(var oi=0;oi<2;oi++){ if(room(r,c,opts[oi])>=3){ want=opts[oi]; break; } }
      if(!want) return null;
      mirrors.push({r:r,c:c,o:orientFor(dir,want)});
      dir=want;
    }
    if(!advance(2)) return null;
    var TARGET={r:r,c:c,enter:dir};
    return { SOURCE:SOURCE, TARGET:TARGET, mirrors:mirrors, path:path };
  }

  function genMirror(seed,diff){
    diff=Math.max(1,Math.min(3,(diff|0)||1));
    var rnd=mulberry32(((seed|0)>>>0)+diff*7919);
    var nTurn=[2,3,4][diff-1], nDecoy=[1,2,3][diff-1], nWall=[0,2,4][diff-1];
    var LETTERS='ABCDEFGHI';
    for(var attempt=0; attempt<120; attempt++){
      var b=tryBuild(rnd,nTurn); if(!b) continue;
      var MPOS={}, SOLUTION={}, DEFAULT={};
      for(var i=0;i<b.mirrors.length;i++){ var id=LETTERS[i];
        MPOS[id]={r:b.mirrors[i].r, c:b.mirrors[i].c}; SOLUTION[id]=b.mirrors[i].o; }
      // cases libres = ni chemin, ni source/cible (pour leurres et murs)
      var used={}; Object.keys(b.path).forEach(function(k){ used[k]=1; });
      var free=[];
      for(var fr=0;fr<ROWS;fr++) for(var fc=0;fc<COLS;fc++){ if(!used[key(fr,fc)]) free.push({r:fr,c:fc}); }
      // mélange de Fisher-Yates sur les cases libres
      for(var s=free.length-1;s>0;s--){ var j=Math.floor(rnd()*(s+1)); var tmp=free[s]; free[s]=free[j]; free[j]=tmp; }
      if(free.length<nDecoy+nWall) continue;
      var di;
      for(di=0;di<nDecoy;di++){ var idd=LETTERS[nTurn+di]; var cell=free.pop();
        MPOS[idd]={r:cell.r,c:cell.c}; SOLUTION[idd]=rnd()<0.5?'/':'\\'; }
      var WALLS=[];
      for(di=0;di<nWall;di++){ WALLS.push(free.pop()); }
      var spec={ SOURCE:b.SOURCE, TARGET:b.TARGET, MPOS:MPOS, WALLS:WALLS };
      // brouillage : on part de la solution et on retourne des miroirs (≥1), jamais résolu d'entrée
      var ids=Object.keys(MPOS), flips=0;
      ids.forEach(function(id){ var f=rnd()<0.5; if(f) flips++; DEFAULT[id]= f ? (SOLUTION[id]==='/'?'\\':'/') : SOLUTION[id]; });
      if(!flips){ DEFAULT[ids[0]]=SOLUTION[ids[0]]==='/'?'\\':'/'; }
      if(!solves(spec,SOLUTION)) continue;      // garde-fou (ne devrait jamais arriver)
      if(solves(spec,DEFAULT)){ var f0=ids[0]; DEFAULT[f0]=DEFAULT[f0]==='/'?'\\':'/'; if(solves(spec,DEFAULT)) continue; }
      spec.DEFAULT=DEFAULT; spec.SOLUTION=SOLUTION;
      spec.hint=(b.TARGET.r<ROWS/2?'en haut':'en bas')+' '+(b.TARGET.c<COLS/2?'à gauche':'à droite');
      var NUMS=['Un','Deux','Trois','Quatre'];
      spec.intro=NUMS[nTurn-1]+' miroirs comptent, '+NUMS[nDecoy-1].toLowerCase()+(nDecoy>1?' te distraient':' te distrait')+'.';
      spec.diff=diff; spec.seed=seed>>>0;
      return spec;
    }
    // repli connu-bon (jamais atteint en pratique — 120 tirages)
    return { SOURCE:{r:7,c:0,dir:'E'}, TARGET:{r:2,c:6,enter:'E'},
      MPOS:{A:{r:7,c:3},B:{r:2,c:3},D:{r:5,c:5}}, DEFAULT:{A:'\\',B:'\\',D:'/'},
      SOLUTION:{A:'\\',B:'/',D:'/'}, WALLS:[], hint:'en haut à droite', diff:diff, seed:seed>>>0 };
  }

  window.OmbreluneGen={ mulberry32:mulberry32, hashStr:hashStr, genMirror:genMirror, solvesMirror:solves };
})();
