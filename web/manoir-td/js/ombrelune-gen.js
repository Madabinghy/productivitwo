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
  // Génération LOGIQUE vérifiée : chaque indice est un FILTRE sur les suspects. Cinq
  // formes de raisonnement — trait positif, trait négatif, disjonction (« X ou Y »),
  // comparaison de taille (« plus grand que N »), alibi nominatif — dont certaines ne
  // se résolvent qu'en les COMBINANT. On vérifie par force brute (enqueteSurvivors) que
  // l'intersection des filtres désigne EXACTEMENT un coupable. Crimes doux, ton Soft Pop.
  var POOL=[
    { key:'gouvernante', face:'👩‍🦳', name:'La Gouvernante',       c1:'#4a2f3e', c2:'#301e28' },
    { key:'maitre',      face:'🎩', name:'Le Maître',              c1:'#3a2c52', c2:'#241a33' },
    { key:'invite',      face:'🧐', name:'L’Invité',               c1:'#2e3a52', c2:'#1b2233' },
    { key:'cuisiniere',  face:'👩‍🍳', name:'La Cuisinière',         c1:'#5a3a2a', c2:'#38241a' },
    { key:'apprenti',    face:'🌱', name:'L’Apprenti jardinier',   c1:'#2f4636', c2:'#1c2a22' },
    { key:'precepteur',  face:'📖', name:'Le Précepteur',          c1:'#33395a', c2:'#1f2338' },
    { key:'modiste',     face:'🎀', name:'La Modiste',             c1:'#5a2f4e', c2:'#381e30' },
    { key:'retameur',    face:'🔧', name:'Le Rétameur',            c1:'#4a3a2a', c2:'#2e241a' }
  ];
  // Axes CATÉGORIELS (3 valeurs) : chaque valeur a deux formulations — `clue` (explicite,
  // donne la conclusion, diff 1) et `obs` (observation brute à interpréter, diff 2+).
  var TRAITS={
    mains:{ icon:'🖐', vals:{
      gants:  { tag:'gants fins',    icon:'🧤', place:'Le boudoir · les bougeoirs', action:'Relever la cire',        clue:'De la cire lissée sans la moindre empreinte : le coupable portait des gants fins.', obs:'De la cire lissée sur le bougeoir, pas la moindre empreinte digitale.' },
      encre:  { tag:'doigts d’encre',icon:'✒️', place:'Le bureau · la poignée',     action:'Examiner la poignée',    clue:'Des traces d’encre fraîche sur la poignée : le coupable a les doigts d’encre.', obs:'Une bavure d’encre fraîche macule la poignée du bureau.' },
      farine: { tag:'mains farinées',icon:'🥖', place:'L’office · le passe-plat',   action:'Suivre la trace blanche',clue:'Une fine poussière de farine mène à la scène : le coupable a les mains farinées.', obs:'Une traînée de farine blanche court jusqu’au passe-plat.' } } },
    parfum:{ icon:'👃', vals:{
      tabac:  { tag:'tabac de pipe', icon:'💨', place:'Le couloir · un sillage',    action:'Humer l’air',            clue:'Une odeur de tabac de pipe flotte encore : le coupable en est imprégné.', obs:'Un relent de tabac de pipe stagne dans le couloir.' },
      lavande:{ tag:'lavande',       icon:'🌸', place:'La scène · un sillage',      action:'Humer l’air',            clue:'Un sillage de lavande s’attarde : le coupable en porte toujours.', obs:'Un sillage de lavande s’attarde au-dessus des lieux.' },
      cirage: { tag:'cirage frais',  icon:'🥾', place:'Le seuil · une empreinte',   action:'Inspecter le seuil',     clue:'Ça sent le cirage frais : le coupable soigne ses bottes.', obs:'Une odeur de cirage frais colle au seuil.' } } },
    pas:{ icon:'👣', vals:{
      lourds: { tag:'pas lourds',    icon:'🪵', place:'L’escalier · le parquet',    action:'Écouter le parquet',     clue:'Le parquet a gémi cette nuit-là : des pas lourds, dit l’écho.', obs:'Le parquet de l’escalier a gémi sous un poids, cette nuit-là.' },
      feutres:{ tag:'pas feutrés',   icon:'🤫', place:'Le palier · le silence',     action:'Interroger le silence',  clue:'Personne n’a rien entendu passer : des pas feutrés, à coup sûr.', obs:'Personne n’a entendu le moindre pas franchir le palier.' },
      traines:{ tag:'pas traînants', icon:'🩴', place:'La galerie · une rayure',    action:'Suivre la rayure',       clue:'Une semelle traînée a rayé le parquet : le coupable traîne les pieds.', obs:'Une semelle a rayé le parquet de la galerie en traînant.' } } }
  };
  // Axe ORDINAL (taille) : alimente les indices de COMPARAISON (« plus grand/petit que N »).
  var TAILLE={ icon:'📏', order:['petite','moyenne','grande'], vals:{
    petite:  { tag:'petite taille', icon:'🐭', rank:0 },
    moyenne: { tag:'taille moyenne',icon:'🧍', rank:1 },
    grande:  { tag:'grande taille', icon:'🦒', rank:2 } } };
  var ALIBIS=[
    { icon:'📓', place:'La loge · le registre',   action:'Consulter le registre',  t:function(n){ return 'Le registre est formel : '+n+' est resté·e à la cave toute la nuit.'; } },
    { icon:'🕯️', place:'Le veilleur · un témoin', action:'Interroger le veilleur', t:function(n){ return 'Le veilleur l’assure : '+n+' veillait au salon jusqu’à l’aube.'; } },
    { icon:'✉️', place:'Le vestibule · un billet',action:'Lire le billet',         t:function(n){ return 'Un billet daté le prouve : '+n+' était hors du manoir ce soir-là.'; } },
    { icon:'🍵', place:'Les cuisines · une tasse',action:'Tâter la théière',       t:function(n){ return 'Une tisane partagée aux cuisines : '+n+' n’a pas quitté la table.'; } },
    { icon:'🎻', place:'Le petit salon · l’écho', action:'Suivre l’air de musique',t:function(n){ return 'On l’a entendu·e jouer sans relâche : '+n+' n’a pas lâché son archet de la nuit.'; } },
    { icon:'🐕', place:'Le chenil · un aboiement',action:'Questionner le chien',   t:function(n){ return 'Le chien n’a pas grogné : '+n+' dormait tout près, comme chaque nuit.'; } }
  ];
  var CRIMES=[
    { q:'Qui a éteint toutes les bougies ?',        deed:'a soufflé les bougies du manoir, une à une', obj:{icon:'🕯️', name:'Le bougeoir du fondateur'} },
    { q:'Qui a emprunté la clé d’argent ?',         deed:'a décroché la clé d’argent de son clou',     obj:{icon:'🗝️', name:'La clé d’argent'} },
    { q:'Qui a retourné le portrait du fondateur ?',deed:'a retourné le portrait face au mur',         obj:{icon:'🖼️', name:'Le portrait redressé'} },
    { q:'Qui a pillé le pot de confiture ?',        deed:'a raflé la confiture de la réserve',         obj:{icon:'🫙', name:'Le pot de confiture'} },
    { q:'Qui a déréglé la grande horloge ?',        deed:'a avancé la grande horloge d’une heure',     obj:{icon:'🕰️', name:'La petite horloge'} },
    { q:'Qui a fané les roses du vestibule ?',      deed:'a renversé le vase et laissé faner les roses',obj:{icon:'🌹', name:'La rose séchée'} },
    { q:'Qui a délacé tous les livres reliés ?',    deed:'a dénoué les rubans de chaque grand livre',  obj:{icon:'📕', name:'Le ruban de reliure'} },
    { q:'Qui a bu le vin de messe ?',               deed:'a vidé la carafe du fondateur en cachette',  obj:{icon:'🍷', name:'La carafe vide'} },
    { q:'Qui a brouillé la boussole du manoir ?',   deed:'a aimanté la vieille boussole de l’entrée',  obj:{icon:'🧭', name:'La boussole affolée'} }
  ];
  function shuffle(arr,rnd){ arr=arr.slice(); for(var i=arr.length-1;i>0;i--){ var j=Math.floor(rnd()*(i+1)); var t=arr[i]; arr[i]=arr[j]; arr[j]=t; } return arr; }

  // —— logique de filtrage (partagée par la génération ET la validation force brute)
  function matchCond(sp,c){ var has=sp.attrs[c.trait]===c.value; return c.neg?!has:has; }
  function taRank(sp){ return TAILLE.vals[sp.attrs.taille].rank; }
  function keepClue(sp,l,SUS){ var e=l.elim; if(!e) return true;
    if(e.type==='trait') return matchCond(sp,e);
    if(e.type==='or') return matchCond(sp,e.a)||matchCond(sp,e.b);
    if(e.type==='cmp'){ var ref=null; for(var i=0;i<SUS.length;i++){ if(SUS[i].key===e.ref){ ref=SUS[i]; break; } } if(!ref) return true;
      return e.op==='>' ? taRank(sp)>taRank(ref) : taRank(sp)<taRank(ref); }
    if(e.type==='alibi') return sp.key!==e.suspect;
    // témoignage : « le coupable ment, les honnêtes disent vrai ». Si le témoin EST le
    // candidat coupable, sa parole est un mensonge (négation) ; sinon elle est vraie.
    if(e.type==='testi'){ var ct=matchCond(sp,e.claim); return sp.key===e.witness ? !ct : ct; }
    return true; }
  function survOf(list,clues,SUS){ return list.filter(function(sp){ return clues.every(function(l){ return keepClue(sp,l,SUS); }); }); }
  function isCombo(l){ return !!(l.elim && (l.elim.type==='or' || (l.elim.type==='trait'&&l.elim.neg))); }
  // survivants après application des filtres machine (sert aussi aux tests)
  function enqueteSurvivors(spec){ return survOf(spec.SUSPECTS, spec.LOCATIONS, spec.SUSPECTS); }

  // —— fabricants d'indices : chacun porte `exp` (explicite) + `obs` (observation)
  function mkTrait(tk,val,neg){ var t=TRAITS[tk].vals[val];
    return { icon: neg?'🚫':t.icon, place:t.place, action:t.action,
      elim:{type:'trait', trait:tk, value:val, neg:!!neg},
      exp: neg ? ('Aucune trace de « '+t.tag+' » sur les lieux : ce n’est pas la marque du coupable.') : t.clue,
      obs: neg ? ('Rien qui évoque « '+t.tag+' » par ici.') : t.obs }; }
  function mkOr(a,b){ var ta=TRAITS[a.trait].vals[a.value], tb=TRAITS[b.trait].vals[b.value];
    return { icon:'🔀', place:'Un feuillet · deux pistes', action:'Lire le feuillet',
      elim:{type:'or', a:a, b:b},
      exp:'Une chose est sûre : le coupable a « '+ta.tag+' » ou « '+tb.tag+' » — l’un des deux au moins.',
      obs:'Deux pistes se croisent sur ce feuillet : « '+ta.tag+' » ou « '+tb.tag+' ».' }; }
  function mkCmp(op,ref){ var dir=op==='>'?'grand':'petit', dir2=op==='>'?'haut':'bas';
    return { icon:'📏', place:'La toise · au mur', action:'Relever la toise',
      elim:{type:'cmp', axis:'taille', op:op, ref:ref.key},
      exp:'La toise est formelle : le coupable est plus '+dir+' que '+ref.name+'.',
      obs:'Une marque fraîche à la toise, plus '+dir2+' que la stature de '+ref.name+'.' }; }
  function mkAlibi(sp,al){ var s=al.t(sp.name);
    return { icon:al.icon, place:al.place, action:al.action, elim:{type:'alibi', suspect:sp.key}, alibi:true, exp:s, obs:s }; }
  // témoignage entre suspects : W accuse le coupable de porter un trait. Vrai si W est
  // honnête, MENSONGE si W est le coupable (à recouper avec les indices physiques).
  function mkTesti(W,claim){ var t=TRAITS[claim.trait].vals[claim.value];
    var q=W.name+' jure : « le coupable a '+t.tag+'. »';
    return { icon:'🗣️', place:'Un témoin · '+W.name, action:'Recueillir le témoignage',
      elim:{type:'testi', witness:W.key, claim:claim}, exp:q, obs:q }; }

  function genEnquete(seed,diff){
    diff=Math.max(1,Math.min(3,(diff|0)||1));
    var rnd=mulberry32(((seed|0)>>>0)+diff*104729+13);
    var nSus=[3,4,5][diff-1], nClues=[3,3,4][diff-1];
    var useObs=diff>=2;                       // diff 2+ : observations à interpréter
    var maxChosen=diff>=3 ? nClues-1 : nClues; // à diff 3, on garde une place pour le leurre
    var useTesti=diff>=2 && Math.floor(rnd()*3)===0; // ~1 enquête sur 3 (diff 2+) : témoignages entre suspects
    var tks=['mains','parfum','pas'];
    for(var attempt=0; attempt<400; attempt++){
      var crime=CRIMES[Math.floor(rnd()*CRIMES.length)];
      var sus=shuffle(POOL,rnd).slice(0,nSus).map(function(p){
        var attrs={}, tags=[];
        tks.forEach(function(tk){ var vs=Object.keys(TRAITS[tk].vals); var v=vs[Math.floor(rnd()*vs.length)];
          attrs[tk]=v; tags.push({ icon:TRAITS[tk].vals[v].icon, t:TRAITS[tk].vals[v].tag }); });
        var tv=TAILLE.order[Math.floor(rnd()*3)]; attrs.taille=tv;
        tags.push({ icon:TAILLE.vals[tv].icon, t:TAILLE.vals[tv].tag });
        return { key:p.key, face:p.face, name:p.name, c1:p.c1, c2:p.c2, attrs:attrs, tags:tags };
      });
      var culprit=sus[Math.floor(rnd()*sus.length)];

      // —— candidats : indices VRAIS sur le coupable qui éliminent au moins un suspect
      var cand=[];
      tks.forEach(function(tk){ var c=mkTrait(tk,culprit.attrs[tk],false); if(survOf(sus,[c],sus).length<sus.length) cand.push(c); });
      if(diff>=2){ tks.forEach(function(tk){ Object.keys(TRAITS[tk].vals).forEach(function(v){ if(v===culprit.attrs[tk]) return;
        var c=mkTrait(tk,v,true); if(survOf(sus,[c],sus).length<sus.length) cand.push(c); }); }); }
      if(diff>=2){ for(var i1=0;i1<tks.length;i1++){ for(var j1=i1+1;j1<tks.length;j1++){
        var c=mkOr({trait:tks[i1],value:culprit.attrs[tks[i1]]},{trait:tks[j1],value:culprit.attrs[tks[j1]]});
        if(survOf(sus,[c],sus).length<sus.length) cand.push(c); } } }
      if(diff>=3){ sus.forEach(function(ref){ if(ref.key===culprit.key) return;
        if(taRank(ref)<taRank(culprit)){ var c=mkCmp('>',ref); if(survOf(sus,[c],sus).length<sus.length) cand.push(c); }
        else if(taRank(ref)>taRank(culprit)){ var c2=mkCmp('<',ref); if(survOf(sus,[c2],sus).length<sus.length) cand.push(c2); } }); }
      // témoignages (~1 enquête sur 3) : un innocent dit vrai sur le coupable ; le coupable
      // se dénonce en mentant (claim FAUSSE sur lui-même) — à recouper avec les indices.
      if(useTesti){ sus.forEach(function(W){
        if(W.key!==culprit.key){ tks.forEach(function(tk){ var c=mkTesti(W,{trait:tk, value:culprit.attrs[tk]});
          if(survOf(sus,[c],sus).length<sus.length) cand.push(c); }); }
        else { tks.forEach(function(tk){ Object.keys(TRAITS[tk].vals).forEach(function(v){ if(v===culprit.attrs[tk]) return;
          var c=mkTesti(W,{trait:tk, value:v}); if(survOf(sus,[c],sus).length<sus.length) cand.push(c); }); }); }
      }); }
      var alibiPool=shuffle(ALIBIS,rnd), aIdx=0, alibiCand=[];
      sus.forEach(function(sp){ if(sp.key===culprit.key) return; alibiCand.push(mkAlibi(sp, alibiPool[(aIdx++)%alibiPool.length])); });

      // ordre : mettre les types requis par la difficulté en tête (biais du greedy)
      var rankOf=function(l){ var t=l.elim.type;
        if(useTesti && t==='testi') return 3;
        if(diff>=3 && t==='cmp') return 2;
        if(diff>=2 && isCombo(l)) return 1;
        return 0; };
      var priority=shuffle(cand,rnd).sort(function(x,y){ return rankOf(y)-rankOf(x); });
      var pool=priority.concat(shuffle(alibiCand,rnd));

      // —— sélection greedy : réduit à {coupable} ; à diff 2+, aucun indice n'est décisif seul ;
      // on privilégie la DIVERSITÉ de types (pass 1 = type inédit) pour éviter d'empiler 3 « toise »
      var sigOf=function(l){ return l.elim.type+(l.elim.neg?'!':''); };
      var chosen=[], surv=sus.slice(), guard=0;
      while(surv.length>1 && chosen.length<maxChosen && guard++<40){
        var used={}; chosen.forEach(function(c){ used[sigOf(c)]=1; });
        var pick=null;
        for(var pass=0; pass<2 && !pick; pass++){
          for(var pi=0; pi<pool.length; pi++){ var l=pool[pi]; if(chosen.indexOf(l)>=0) continue;
            if(pass===0 && used[sigOf(l)]) continue;                                              // pass 1 : type inédit d'abord
            var next=survOf(surv,[l],sus); if(next.length===surv.length) continue;               // n'élimine personne maintenant
            var keepsC=false; for(var k=0;k<next.length;k++){ if(next[k].key===culprit.key){ keepsC=true; break; } }
            if(!keepsC) continue;                                                                 // écarterait le coupable
            if(diff>=2 && survOf(sus,[l],sus).length<=1) continue;                                // décisif seul → interdit à diff 2+
            pick=l; break; }
        }
        if(!pick) break;
        chosen.push(pick); surv=survOf(surv,[pick],sus);
      }
      if(surv.length!==1 || surv[0].key!==culprit.key) continue;
      if(chosen.length<1) continue;
      // le témoignage tient lieu de « raisonnement spécial » quand il est présent
      if(diff===2 && !useTesti && !chosen.some(isCombo)) continue;
      if(diff===3 && !useTesti && !chosen.some(function(l){ return l.elim.type==='cmp'; })) continue;
      if(useTesti && !chosen.some(function(l){ return l.elim.type==='testi'; })) continue;

      // leurre (diff 3) : un indice VRAI sur le coupable, non retenu, qui ne change rien
      var herring=null;
      if(diff>=3){ var usedH={}; chosen.forEach(function(c){ usedH[sigOf(c)]=1; });
        for(var hpass=0; hpass<2 && !herring; hpass++){
          for(var hi=0; hi<pool.length; hi++){ var lh=pool[hi]; if(chosen.indexOf(lh)>=0) continue;
            if(lh.elim.type==='alibi') continue; if(!keepClue(culprit,lh,sus)) continue;
            if(hpass===0 && usedH[sigOf(lh)]) continue;    // pass 1 : un leurre d'un type inédit d'abord
            if(survOf(sus,[lh],sus).length<=1) continue;   // le leurre ne doit pas non plus résoudre seul
            herring=lh; break; } }
        if(!herring) continue; herring.redHerring=true; }

      // —— assemblage
      var clues=chosen.slice(); if(herring) clues.push(herring);
      var minClues=Math.min(nClues,3), ap=0;
      while(clues.length<minClues && ap<alibiCand.length){ var al=alibiCand[ap++];
        if(clues.some(function(c){ return c.elim.type==='alibi'&&c.elim.suspect===al.elim.suspect; })) continue;
        clues.push(al); }
      var cap=nClues+(herring?1:0); if(clues.length>cap) clues=clues.slice(0,cap);
      clues=shuffle(clues,rnd).map(function(c,i){ return { key:'c'+i, icon:c.icon, place:c.place, action:c.action,
        clue: useObs ? (c.obs||c.exp) : (c.exp||c.obs), elim:c.elim, alibi:c.alibi, redHerring:c.redHerring }; });
      // difficulté 2+ : une partie des indices se CACHE (la Fouille) ; à 3, la loupe. Présentation.
      var nHide=[0,1,2][diff-1], hid=0;
      for(var h2=0; h2<clues.length && hid<nHide; h2++){ clues[h2].hidden=true; hid++; }
      if(diff>=3){ var fh=clues.filter(function(c){ return c.hidden; })[0]; if(fh) fh.needsLoupe=true; }

      var spec={ question:crime.q, deed:crime.deed, OBJ:crime.obj, SUSPECTS:sus, LOCATIONS:clues, CULPRIT:culprit.key };
      var final=enqueteSurvivors(spec);
      if(final.length!==1 || final[0].key!==culprit.key) continue; // vérif force brute

      // réfutations : pour chaque innocent, citer un indice qui l'exclut
      spec.WRONG={}; var ok=true;
      sus.forEach(function(sp){ if(sp.key===culprit.key) return;
        var ex=null; for(var ci=0; ci<clues.length; ci++){ if(clues[ci].elim && !keepClue(sp,clues[ci],sus)){ ex=clues[ci]; break; } }
        if(!ex){ ok=false; return; }
        spec.WRONG[sp.key]='« '+ex.clue+' » — '+sp.name+' ne colle pas.'; });
      if(!ok) continue;

      // verdict : traînée de raisonnement
      var traces=[];
      clues.forEach(function(l){ if(l.redHerring||!l.elim) return; var e=l.elim;
        if(e.type==='trait'&&!e.neg){ var tg=TRAITS[e.trait].vals[e.value].tag; if(traces.indexOf(tg)<0) traces.push(tg); }
        else if(e.type==='cmp'){ if(traces.indexOf('la toise')<0) traces.push('la toise'); }
        else if(e.type==='or'){ if(traces.indexOf('un recoupement')<0) traces.push('un recoupement'); }
        else if(e.type==='testi'){ if(traces.indexOf('un témoignage')<0) traces.push('un témoignage'); } });
      var tr=traces.length?traces.join(', '):'les indices';
      spec.VERDICT={ face:culprit.face, name:culprit.name,
        text:'Tout convergeait — '+tr+' : '+culprit.name+', qui '+crime.deed+' avant de se fondre dans l’ombre. Le manoir respire.' };

      // narration
      var INTROS=[
        [ 'Cette nuit, quelqu’un '+crime.deed+'. Le manoir l’a senti — les bougies ont frémi.',
          sus.length+' suspects n’ont pas quitté les lieux, et chacun jure n’y être pour rien.',
          'Fouille, recoupe, puis accuse — le manoir se souvient de tout.' ],
        [ 'Au petit matin, le constat : on '+crime.deed+'. Personne n’a rien vu, bien sûr.',
          'Ils sont '+sus.length+' à avoir dormi sous ce toit cette nuit-là. Un seul ment.',
          'Les indices, eux, ne se contredisent jamais. À toi de les faire parler — et de les croiser.' ],
        [ 'Le manoir a une plaie de plus : quelqu’un '+crime.deed+'.',
          sus.length+' visages, autant d’alibis trop lisses. La vérité tient dans les détails.',
          'Rassemble les traces, recoupe-les, puis démasque.' ] ];
      spec.INTRO=INTROS[Math.floor(rnd()*INTROS.length)];
      if(useTesti) spec.INTRO=spec.INTRO.concat(['Cette nuit-là, certains se sont mis à parler. Souviens-toi : le coupable ment, les honnêtes disent vrai. Un témoignage qui contredit les indices trahit son menteur…']);
      var QUOTES=['« Moi ? J’ai bien mieux à faire, crois-moi. »','« Je dormais. Profondément. Trop, peut-être. »','« Demande à qui tu veux — on me connaît ici. »','« Cette nuit-là ? Je comptais les étoiles. Seul·e, hélas. »','« Quelle idée. Je n’ai rien touché… presque rien. »','« Le manoir me fait confiance. Toi, visiblement, moins. »','« Cherche ailleurs. Mais cherche bien. »','« Si j’avais fait ça, tu ne le saurais jamais. »'];
      sus.forEach(function(sp){ sp.quote=QUOTES[Math.floor(rnd()*QUOTES.length)]; });
      var NOTES=['Ça réduit le cercle…','Intéressant. Quelqu’un ici correspond.','Le manoir chuchote — on approche.','Note-le : les détails trahissent toujours.','Un suspect vient de perdre son masque.','Garde ça en tête pour la confrontation.','Deux indices valent mieux qu’un — recoupe-les.','Ce détail seul ne suffit pas ; croise-le.','Un nom s’efface doucement de la liste.','La toise, l’odeur, la trace… tout finit par parler.'];
      clues.forEach(function(c){ c.note=NOTES[Math.floor(rnd()*NOTES.length)]; });
      spec.diff=diff; spec.seed=seed>>>0;
      return spec;
    }
    return null; // jamais atteint en pratique (400 tirages) ; la page retombe sur le cas historique
  }

  // ============ Salle des Ombres ============
  // Génération de MAP par assemblage de segments dessinés à la main (mélangés,
  // miroir gauche/droite aléatoire) + placement caméras/gardes/socles sous budget
  // + puzzle de faisceau généré (avec son dilemme : capteur OU caméra du coffre)
  // + VALIDATION avant de servir (couverture par caméra, glu sur ronde, faisceau
  // résoluble, points clés dégagés). Échec après 80 tirages → null (plan fixe).
  var OW=560, MB=200, VB=280, EB=170;
  // Segments (coordonnées locales 560×200) : meubles = couverture, cam murale
  // optionnelle (side L/R + y local), ronde de garde optionnelle (y local), socle.
  var SEGS=[
    { furn:[[60,80,96,46],[300,40,70,90],[380,140,84,46]], cam:{side:'L',y:110,range:240}, sock:[210,150] },
    { furn:[[230,60,90,46],[110,140,84,46],[420,120,70,84]], guard:{y:100,patrol:150}, sock:[400,100] },
    { furn:[[80,40,60,80],[440,60,60,80],[240,150,96,46]], cam:{side:'R',y:70,range:230}, sock:[160,70] },
    { furn:[[180,90,200,40]], cam:{side:'L',y:40,range:250}, guard:{y:160,patrol:120}, sock:[280,160] },
    { furn:[[60,140,96,46],[404,20,96,46]], cam:{side:'R',y:150,range:240}, sock:[120,60] },
    { furn:[[140,60,70,46],[330,110,70,46],[240,20,60,46]], sock:[280,170] }
  ];
  function segRectHit(x1,y1,x2,y2,r,m){ // segment axial vs rect gonflé
    var lo={x:Math.min(x1,x2)-m, y:Math.min(y1,y2)-m}, hi={x:Math.max(x1,x2)+m, y:Math.max(y1,y2)+m};
    return !(r.x+r.w<lo.x || r.x>hi.x || r.y+r.h<lo.y || r.y>hi.y);
  }
  function genOmbres(seed,diff){
    diff=Math.max(1,Math.min(3,(diff|0)||1));
    var rnd=mulberry32(((seed|0)>>>0)+diff*31337+7);
    var nMid=[3,4,5][diff-1], camBudget=[3,4,6][diff-1], guardBudget=[1,1,2][diff-1];
    var H=VB+nMid*MB+EB;
    for(var attempt=0; attempt<80; attempt++){
      var FURN=[], CAMS=[], GUARDS=[], SOCKETS=[], cn=1, sn=1;
      // —— chambre forte + faisceau (bande du haut, sans meubles) ——
      var flip=rnd()<0.5;
      var y1=210+Math.floor(rnd()*3)*14, y2=120;
      var mx=240+Math.floor(rnd()*7)*20, sx=110+Math.floor(rnd()*4)*14;
      var X=function(x){ return flip? OW-x : x; };
      var SOURCE={ x:X(40), y:y1, dir:flip?'W':'E' };
      var sol1=flip?'\\':'/', sol2=flip?'/':'\\';
      var o1=rnd()<0.5?'/':'\\', o2=rnd()<0.5?'/':'\\';
      if(o1===sol1 && o2===sol2) o2 = o2==='/'?'\\':'/';
      var MIRRORS=[ { id:'m1', x:X(mx), y:y1, o:o1 }, { id:'m2', x:X(mx), y:y2, o:o2 } ];
      var SENSOR={ x:X(sx), y:y2 };
      var VAULT={ x:280, y:90 };
      CAMS.push({ id:'c'+(cn++), x:flip?60:500, y:y2, dir:flip?0:Math.PI, sweep:0.45, phase:rnd()*6.28, range:260, half:0.40 });
      SOCKETS.push({ id:'s'+(sn++), x:flip?130:430, y:170 });
      FURN.push({ x:flip?30:470, y:140, w:60, h:46 }); // abri sous la caméra du coffre (entre les rangées du faisceau)
      // —— bandes du milieu : segments mélangés, miroir aléatoire ——
      var camSlots=[], guardSlots=[];
      for(var b=0;b<nMid;b++){ var y0=VB+b*MB;
        var t=SEGS[Math.floor(rnd()*SEGS.length)], mir=rnd()<0.5;
        var TX=function(x,w){ return mir? OW-x-(w||0) : x; };
        t.furn.forEach(function(f){ FURN.push({ x:TX(f[0],f[2]), y:y0+f[1], w:f[2], h:f[3] }); });
        if(t.sock) SOCKETS.push({ id:'s'+(sn++), x:TX(t.sock[0]), y:y0+t.sock[1] });
        if(t.cam){ var side=mir?(t.cam.side==='L'?'R':'L'):t.cam.side;
          camSlots.push({ x:side==='L'?60:500, y:y0+t.cam.y, dir:side==='L'?0:Math.PI, range:t.cam.range }); }
        if(t.guard) guardSlots.push({ y:y0+t.guard.y, patrol:t.guard.patrol });
      }
      // budgets : compléter ou élaguer (mélange déterministe)
      for(var i2=camSlots.length-1;i2>0;i2--){ var j2=Math.floor(rnd()*(i2+1)); var tt=camSlots[i2]; camSlots[i2]=camSlots[j2]; camSlots[j2]=tt; }
      while(camSlots.length<camBudget-1){ var b2=Math.floor(rnd()*nMid), sd=rnd()<0.5;
        camSlots.push({ x:sd?60:500, y:VB+b2*MB+60+Math.floor(rnd()*80), dir:sd?0:Math.PI, range:230 }); }
      camSlots.slice(0,camBudget-1).forEach(function(c){
        CAMS.push({ id:'c'+(cn++), x:c.x, y:c.y, dir:c.dir, sweep:0.45+rnd()*0.2, phase:rnd()*6.28, range:c.range, half:0.36+rnd()*0.05 }); });
      for(var i3=guardSlots.length-1;i3>0;i3--){ var j3=Math.floor(rnd()*(i3+1)); var t3=guardSlots[i3]; guardSlots[i3]=guardSlots[j3]; guardSlots[j3]=t3; }
      while(guardSlots.length<guardBudget){ var b3=Math.floor(rnd()*nMid);
        guardSlots.push({ y:VB+b3*MB+100, patrol:120+Math.floor(rnd()*3)*20 }); }
      guardSlots.slice(0,guardBudget).forEach(function(g){
        GUARDS.push({ x:280, y:g.y, dir:rnd()<0.5?0:Math.PI/2, sweep:0.7+rnd()*0.15, phase:rnd()*6.28, range:180+Math.floor(rnd()*3)*10, half:0.42, patrol:g.patrol });
        // la glu doit pouvoir prendre : un socle SUR la ronde
        var has=SOCKETS.some(function(s){ return Math.abs(s.y-g.y)<=22 && Math.abs(s.x-280)<=g.patrol+10; });
        if(!has) SOCKETS.push({ id:'s'+(sn++), x:280-40+Math.floor(rnd()*5)*20, y:g.y }); });
      // —— bande d'entrée ——
      var START={ x:280, y:H-60 }, CONSOLE={ x:flip?90:470, y:H-160 };
      FURN.push({ x:150+Math.floor(rnd()*8)*20, y:H-EB+30, w:96, h:46 });
      // —— VALIDATION ——
      var ok=true;
      // faisceau : solution dégagée, dilemme (aveugler la cam du coffre) dégagé
      var beam=[ [SOURCE.x,y1,MIRRORS[0].x,y1], [MIRRORS[0].x,y1,MIRRORS[0].x,y2], [MIRRORS[1].x,y2,SENSOR.x,y2],
                 [MIRRORS[1].x,y2,flip?60:500,y2] ];
      beam.forEach(function(sg){ if(FURN.some(function(r){ return segRectHit(sg[0],sg[1],sg[2],sg[3],r,6); })) ok=false; });
      // couverture : chaque caméra a un meuble-abri à portée
      CAMS.forEach(function(c){ if(!FURN.some(function(r){ var fx=r.x+r.w/2, fy=r.y+r.h/2;
        return Math.hypot(fx-c.x,fy-c.y)<c.range*0.9 && Math.abs(fy-c.y)<140; })) ok=false; });
      // points clés dégagés (personne ne spawn/interagit dans un meuble)
      [[START.x,START.y],[CONSOLE.x,CONSOLE.y],[VAULT.x,VAULT.y],[SENSOR.x,SENSOR.y],[MIRRORS[0].x,y1],[MIRRORS[1].x,y2]].forEach(function(pt){
        if(FURN.some(function(r){ return pt[0]>=r.x-24 && pt[0]<=r.x+r.w+24 && pt[1]>=r.y-24 && pt[1]<=r.y+r.h+24; })) ok=false; });
      // socles : jamais dans un meuble
      SOCKETS.forEach(function(s){ if(FURN.some(function(r){ return s.x>=r.x-14 && s.x<=r.x+r.w+14 && s.y>=r.y-14 && s.y<=r.y+r.h+14; })) ok=false; });
      if(!ok) continue;
      return { WORLD_W:OW, WORLD_H:H, START:START, VAULT:VAULT, CONSOLE:CONSOLE,
        CAMS:CAMS, GUARDS:GUARDS, FURN:FURN, SOCKETS:SOCKETS,
        SOURCE:SOURCE, MIRRORS:MIRRORS, SENSOR:SENSOR,
        SOLUTION:{ m1:sol1, m2:sol2 }, diff:diff, seed:seed>>>0 };
    }
    return null; // repli : la page garde son plan historique
  }

  window.OmbreluneGen={ mulberry32:mulberry32, hashStr:hashStr, genMirror:genMirror, solvesMirror:solves,
    genEnquete:genEnquete, enqueteSurvivors:enqueteSurvivors, genOmbres:genOmbres };
})();
