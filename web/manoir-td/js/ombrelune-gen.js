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

  // ============ Enquête du manoir ============
  // Génération LOGIQUE vérifiée : chaque indice est un filtre (trait du coupable
  // ou alibi nominatif) ; on vérifie par force brute que l'intersection des
  // filtres désigne EXACTEMENT un coupable. Crimes doux, ton Soft Pop.
  var POOL=[
    { key:'gouvernante', face:'👩‍🦳', name:'La Gouvernante' },
    { key:'maitre',      face:'🎩', name:'Le Maître' },
    { key:'invite',      face:'🧐', name:'L’Invité' },
    { key:'cuisiniere',  face:'👩‍🍳', name:'La Cuisinière' },
    { key:'apprenti',    face:'🌱', name:'L’Apprenti jardinier' },
    { key:'precepteur',  face:'📖', name:'Le Précepteur' },
    { key:'modiste',     face:'🎀', name:'La Modiste' },
    { key:'retameur',    face:'🔧', name:'Le Rétameur' }
  ];
  var TRAITS={
    mains:{ icon:'🖐', vals:{
      gants:  { tag:'gants fins',    icon:'🧤', place:'Le boudoir · les bougeoirs', action:'Relever la cire',        clue:'De la cire lissée sans la moindre empreinte : le coupable portait des gants fins.' },
      encre:  { tag:'doigts d’encre',icon:'✒️', place:'Le bureau · la poignée',     action:'Examiner la poignée',    clue:'Des traces d’encre fraîche sur la poignée : le coupable a les doigts d’encre.' },
      farine: { tag:'mains farinées',icon:'🥖', place:'L’office · le passe-plat',   action:'Suivre la trace blanche',clue:'Une fine poussière de farine mène à la scène : le coupable a les mains farinées.' } } },
    parfum:{ icon:'👃', vals:{
      tabac:  { tag:'tabac de pipe', icon:'💨', place:'Le couloir · un sillage',    action:'Humer l’air',            clue:'Une odeur de tabac de pipe flotte encore : le coupable en est imprégné.' },
      lavande:{ tag:'lavande',       icon:'🌸', place:'La scène · un sillage',      action:'Humer l’air',            clue:'Un sillage de lavande s’attarde : le coupable en porte toujours.' },
      cirage: { tag:'cirage frais',  icon:'🥾', place:'Le seuil · une empreinte',   action:'Inspecter le seuil',     clue:'Ça sent le cirage frais : le coupable soigne ses bottes.' } } },
    pas:{ icon:'👣', vals:{
      lourds: { tag:'pas lourds',    icon:'🪵', place:'L’escalier · le parquet',    action:'Écouter le parquet',     clue:'Le parquet a gémi cette nuit-là : des pas lourds, dit l’écho.' },
      feutres:{ tag:'pas feutrés',   icon:'🤫', place:'Le palier · le silence',     action:'Interroger le silence',  clue:'Personne n’a rien entendu passer : des pas feutrés, à coup sûr.' },
      traines:{ tag:'pas traînants', icon:'🩴', place:'La galerie · une rayure',    action:'Suivre la rayure',       clue:'Une semelle traînée a rayé le parquet : le coupable traîne les pieds.' } } }
  };
  var ALIBIS=[
    { icon:'📓', place:'La loge · le registre',   action:'Consulter le registre',  t:function(n){ return 'Le registre est formel : '+n+' est resté·e à la cave toute la nuit.'; } },
    { icon:'🕯️', place:'Le veilleur · un témoin', action:'Interroger le veilleur', t:function(n){ return 'Le veilleur l’assure : '+n+' veillait au salon jusqu’à l’aube.'; } },
    { icon:'✉️', place:'Le vestibule · un billet',action:'Lire le billet',         t:function(n){ return 'Un billet daté le prouve : '+n+' était hors du manoir ce soir-là.'; } },
    { icon:'🍵', place:'Les cuisines · une tasse',action:'Tâter la théière',       t:function(n){ return 'Une tisane partagée aux cuisines : '+n+' n’a pas quitté la table.'; } }
  ];
  var CRIMES=[
    { q:'Qui a éteint toutes les bougies ?',        deed:'a soufflé les bougies du manoir, une à une' },
    { q:'Qui a emprunté la clé d’argent ?',         deed:'a décroché la clé d’argent de son clou' },
    { q:'Qui a retourné le portrait du fondateur ?',deed:'a retourné le portrait face au mur' },
    { q:'Qui a pillé le pot de confiture ?',        deed:'a raflé la confiture de la réserve' },
    { q:'Qui a déréglé la grande horloge ?',        deed:'a avancé la grande horloge d’une heure' }
  ];
  function shuffle(arr,rnd){ arr=arr.slice(); for(var i=arr.length-1;i>0;i--){ var j=Math.floor(rnd()*(i+1)); var t=arr[i]; arr[i]=arr[j]; arr[j]=t; } return arr; }
  // survivants après application des filtres machine (sert aussi aux tests)
  function enqueteSurvivors(spec){
    return spec.SUSPECTS.filter(function(sp){
      return spec.LOCATIONS.every(function(l){ if(!l.elim) return true;
        if(l.elim.type==='trait') return sp.attrs[l.elim.trait]===l.elim.value;
        return sp.key!==l.elim.suspect; });
    });
  }
  function genEnquete(seed,diff){
    diff=Math.max(1,Math.min(3,(diff|0)||1));
    var rnd=mulberry32(((seed|0)>>>0)+diff*104729+13);
    var nSus=[3,4,5][diff-1], nClues=[3,3,4][diff-1];
    var traitKeys=Object.keys(TRAITS);
    for(var attempt=0; attempt<200; attempt++){
      var crime=CRIMES[Math.floor(rnd()*CRIMES.length)];
      var sus=shuffle(POOL,rnd).slice(0,nSus).map(function(p){
        var attrs={}, tags=[];
        traitKeys.forEach(function(tk){ var vs=Object.keys(TRAITS[tk].vals); var v=vs[Math.floor(rnd()*vs.length)];
          attrs[tk]=v; tags.push({ icon:TRAITS[tk].vals[v].icon, t:TRAITS[tk].vals[v].tag }); });
        return { key:p.key, face:p.face, name:p.name, attrs:attrs, tags:tags };
      });
      var culprit=sus[Math.floor(rnd()*sus.length)];
      // indices de trace (traits du coupable), dans un ordre aléatoire
      var clues=[]; var remaining=sus.slice();
      var order=shuffle(traitKeys,rnd);
      for(var ti=0; ti<order.length && remaining.length>1 && clues.length<nClues; ti++){
        var tk2=order[ti], val=culprit.attrs[tk2];
        var after=remaining.filter(function(sp){ return sp.attrs[tk2]===val; });
        if(after.length===remaining.length) continue; // n'élimine personne → sans intérêt
        var tpl=TRAITS[tk2].vals[val];
        clues.push({ key:'c'+clues.length, icon:tpl.icon, place:tpl.place, action:tpl.action, clue:tpl.clue,
          elim:{type:'trait', trait:tk2, value:val} });
        remaining=after;
      }
      // alibis nominaux pour les égalités restantes (jamais pour le coupable)
      var alibiPool=shuffle(ALIBIS,rnd), ai=0;
      while(remaining.length>1 && clues.length<nClues && ai<alibiPool.length){
        var tie=remaining.filter(function(sp){ return sp.key!==culprit.key; })[0]; if(!tie) break;
        var al=alibiPool[ai++];
        clues.push({ key:'c'+clues.length, icon:al.icon, place:al.place, action:al.action, clue:al.t(tie.name),
          elim:{type:'alibi', suspect:tie.key}, alibi:true });
        remaining=remaining.filter(function(sp){ return sp.key!==tie.key; });
      }
      if(remaining.length!==1 || remaining[0].key!==culprit.key) continue;
      // compléter à nClues avec des alibis d'innocents déjà écartés (texture, jamais trompeur)
      var others=sus.filter(function(sp){ return sp.key!==culprit.key && !clues.some(function(c){ return c.elim.type==='alibi'&&c.elim.suspect===sp.key; }) });
      while(clues.length<nClues && ai<alibiPool.length && others.length){
        var ex=others.shift(), al2=alibiPool[ai++];
        clues.push({ key:'c'+clues.length, icon:al2.icon, place:al2.place, action:al2.action, clue:al2.t(ex.name),
          elim:{type:'alibi', suspect:ex.key}, alibi:true });
      }
      if(clues.length<Math.min(nClues,3)) continue;
      clues=shuffle(clues,rnd).map(function(c,i){ c.key='c'+i; return c; });
      var spec={ question:crime.q, deed:crime.deed, SUSPECTS:sus, LOCATIONS:clues, CULPRIT:culprit.key };
      var surv=enqueteSurvivors(spec);
      if(surv.length!==1 || surv[0].key!==culprit.key) continue; // vérif force brute
      // réfutations pour chaque innocent + verdict
      spec.WRONG={};
      sus.forEach(function(sp){ if(sp.key===culprit.key) return;
        var byAlibi=clues.filter(function(c){ return c.elim.type==='alibi'&&c.elim.suspect===sp.key; })[0];
        if(byAlibi){ spec.WRONG[sp.key]=byAlibi.clue+' Ce n’est pas '+sp.name+'.'; return; }
        var byTrait=clues.filter(function(c){ return c.elim.type==='trait'&&sp.attrs[c.elim.trait]!==c.elim.value; })[0];
        spec.WRONG[sp.key]=sp.name+' n’a pas « '+TRAITS[byTrait.elim.trait].vals[byTrait.elim.value].tag+' » — relis tes indices.'; });
      var traces=clues.filter(function(c){ return c.elim.type==='trait'; })
        .map(function(c){ return TRAITS[c.elim.trait].vals[c.elim.value].tag; }).join(', ');
      spec.VERDICT={ face:culprit.face, name:culprit.name,
        text:'Les indices ne mentaient pas — '+traces+' : tout désignait '+culprit.name+', qui '+crime.deed+' avant de se fondre dans l’ombre. Le manoir respire.' };
      spec.diff=diff; spec.seed=seed>>>0;
      return spec;
    }
    return null; // jamais atteint en pratique (200 tirages) ; la page retombe sur le cas historique
  }

  window.OmbreluneGen={ mulberry32:mulberry32, hashStr:hashStr, genMirror:genMirror, solvesMirror:solves,
    genEnquete:genEnquete, enqueteSurvivors:enqueteSurvivors };
})();
