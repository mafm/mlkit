
functor RegionStatEnv(structure Name : NAME
                      structure R: RTYPE
		      structure E: EFFECT
                        sharing type R.cone = E.cone
			sharing type R.effect = E.effect
			sharing type R.runType = E.runType
                      structure TyName: TYNAME
                        sharing type TyName.TyName = R.tyname
                        sharing type TyName.name = Name.name
		      structure Con: CON
			sharing type Con.name = Name.name
		      structure Excon: EXCON
			sharing type Excon.name = Name.name
		      structure Lvar: LVARS
			sharing type Lvar.name = Name.name
		      structure Crash: CRASH
		      structure L: LAMBDA_EXP
			sharing type L.tyvar = R.tyvar
			sharing type L.Type = R.LambdaType
                      structure Flags: FLAGS
		      structure PP: PRETTYPRINT
			sharing type PP.StringTree = R.StringTree = 
			  E.StringTree = Con.Map.StringTree = Excon.Map.StringTree =
			  TyName.Map.StringTree = Lvar.Map.StringTree
		        sharing type L.TyName = TyName.TyName)

  : REGION_STAT_ENV =

  struct

    structure ConMap = Con.Map
    structure TyNameMap = TyName.Map
    structure ExconMap = Excon.Map
    structure LvarMap = Lvar.Map

    fun die s = Crash.impossible ("RegionStatEnv." ^ s)
    fun log s = TextIO.output(TextIO.stdOut,s ^ "\n")
    fun log_st st = PP.outputTree(fn s => TextIO.output(TextIO.stdOut,s), st, 70)
    fun layout_effects effects = PP.NODE{start="[",finish="]",indent=1,childsep=PP.RIGHT ",",
					 children=map E.layout_effect effects}
    fun dump(t: PP.StringTree):unit = 
        PP.outputTree(fn s => TextIO.output(!Flags.log,s), t, !Flags.colwidth)

      (* arity: number of quantified type variables, 
		list of runtime types,
		number of effect  variables *)
    type runType = E.runType
    type arity = int * E.runType list * int 
    fun mk_arity x = x
    fun un_arity x = x

    type il = R.il 
    type cone = R.cone

    type instance_list = (il * (il * cone -> il * cone)) ref list

    type lvar_env_range = bool * bool * R.sigma * R.place 
			* instance_list ref option * (il ->unit)option

    type regionStatEnv = {tyname_env:  arity TyNameMap.map,
			  con_env: R.sigma ConMap.map,
			  excon_env: (R.Type * R.place) ExconMap.map,
			  lvar_env: lvar_env_range LvarMap.map
			 }
    type con = Con.con                           (* Unqualified value constructors. *)
    type excon = Excon.excon			(* Unqualified exception constructors.*)
    type TyName = TyName.TyName
    type lvar = Lvar.lvar			(* Unique lambda identifiers. *)
    type TypeAndPlaceScheme = R.sigma
     and TypeAndPlace = (R.Type * R.place)
     and Type = R.Type
     and place = R.place

    val empty: regionStatEnv = {tyname_env = TyNameMap.empty,
				con_env = ConMap.empty,
				excon_env = ExconMap.empty,
				lvar_env = LvarMap.empty}
    val tyname_env0= TyNameMap.add(TyName.tyName_STRING, (0,[],0),
		     TyNameMap.add(TyName.tyName_REAL, (0,[],0),
		     TyNameMap.add(TyName.tyName_EXN, (0,[],0),
		     TyNameMap.add(TyName.tyName_REF, (1,[],0),
		     TyNameMap.add(TyName.tyName_BOOL, (0,[],0),
		     TyNameMap.add(TyName.tyName_INT31, (0,[],0), 
		     TyNameMap.add(TyName.tyName_INT32, (0,[],0), 
		     TyNameMap.add(TyName.tyName_CHAR, (0,[],0), 
		     TyNameMap.add(TyName.tyName_WORD8, (0,[],0),
		     TyNameMap.add(TyName.tyName_WORD31, (0,[],0),
		     TyNameMap.add(TyName.tyName_WORD32, (0,[],0),
		     TyNameMap.add(TyName.tyName_LIST, (1,[E.PAIR_RT],0),
				   (* the auxiliary region is for a pair; hence PAIR_RT *)
		     TyNameMap.add(TyName.tyName_FRAG, (1,[E.STRING_RT],0),
				   (* the auxiliary region is for a string; hence STRING_RT *)
		     TyNameMap.add(TyName.tyName_CHARARRAY, (0,[],0),
		     TyNameMap.add(TyName.tyName_FOREIGNPTR, (0,[],0),
		     TyNameMap.add(TyName.tyName_ARRAY, (1,[],0),
		     TyNameMap.add(TyName.tyName_VECTOR, (1,[],0),
		     TyNameMap.empty)))))))))))))))))

    local

      fun mkListType(mu,rho) = R.CONSTYPE(TyName.tyName_LIST, [mu], [rho], [])

      fun mk_nil_sigma c lev0 =
	let val alpha = L.fresh_tyvar()
	    val alpha_ty = R.TYVAR alpha
	    val (rho,c) = E.freshRho c                     (* bot-region for tyvar *)
	    val (rho',c) = E.freshRhoWithTy(E.PAIR_RT, c)  (* aux region for pairs *)
	    val (c,nil_sigma,_) = R.generalize_all (c, lev0, [alpha], mkListType((alpha_ty,rho), rho'))
	in (c, nil_sigma)
	end

      fun mk_cons_sigma c lev0 rt_list =
	let val alpha = L.fresh_tyvar()
	    val alpha_ty = R.TYVAR alpha
	    val (rho,c) = E.freshRho c                     (* bot-region for tyvar *)
	    val (rho',c) = E.freshRhoWithTy(E.PAIR_RT, c)  (* aux region for pairs *)
	    val (rho'',c) = E.freshRhoWithTy(rt_list, c)   (* region for result list *)
	    val alpha_rho_list = (mkListType((alpha_ty,rho), rho'), rho'')
	    val (arreff, c) = E.freshEps c
	    val _ = E.edge(arreff, E.mkPut rho'')

	    val cons_mu = R.FUN([(R.RECORD[(alpha_ty,rho),alpha_rho_list], rho')],
				arreff, 
				[alpha_rho_list])
	    val (c,cons_sigma,_) = R.generalize_all (c, lev0, [alpha], cons_mu)
	in (c, cons_sigma)
	end

      fun mkFragConsTy mu1 ae (mu,rho,rho0) =
	R.FUN([mu1],ae,[(R.CONSTYPE(TyName.tyName_FRAG, [mu], [rho], []), rho0)])

      fun mk_quote_sigma c lev0 =
	let val alpha = L.fresh_tyvar()
	    val alpha_ty = R.TYVAR alpha
	    val (rho1,c) = E.freshRhoWithTy(E.STRING_RT, c)  (* region for auxiliary strings *)
	    val (rho2,c) = E.freshRhoWithTy(E.TOP_RT, c)     (* region for result frag *)
	    val (rho3,c) = E.freshRho c                      (* bot-region for tyvar *)
	    val (arreff, c) = E.freshEps c
	    val _ = E.edge(arreff, E.mkPut rho2)
	    val quote_ty = mkFragConsTy (R.CONSTYPE(TyName.tyName_STRING,[],[],[]),rho1)
	      arreff ((alpha_ty,rho3),rho1,rho2)
	    val (c,quote_sigma,_) = R.generalize_all (c, lev0, [alpha], quote_ty)
	in (c, quote_sigma)
	end

      fun mk_antiquote_sigma c lev0 =
	let val alpha = L.fresh_tyvar()
	    val alpha_ty = R.TYVAR alpha
	    val (rho1,c) = E.freshRhoWithTy(E.STRING_RT, c)  (* region for auxiliary strings *)
	    val (rho2,c) = E.freshRhoWithTy(E.TOP_RT, c)     (* region for result frag *)
	    val (rho3,c) = E.freshRho c                      (* bot-region for tyvar *)
	    val (arreff, c) = E.freshEps c
	    val _ = E.edge(arreff, E.mkPut rho2)
	    val antiquote_ty = mkFragConsTy (alpha_ty,rho3)
	      arreff ((alpha_ty,rho3),rho1,rho2)
	    val (c,antiquote_sigma,_) = R.generalize_all (c, lev0, [alpha], antiquote_ty)
	in (c, antiquote_sigma)
	end

      fun mk_bool_sigma c lev0 =
	let val (c,bool_sigma,_) =  
	       R.generalize_all (c, lev0, [], (R.CONSTYPE(TyName.tyName_BOOL,[],[],[])))
	in (c, bool_sigma)
	end

      val c = E.initCone
      val lev0 = E.level c
      val c = E.push c

      val (c, nil_sigma) = mk_nil_sigma c lev0
      val (c, cons_sigma) = mk_cons_sigma c lev0 E.TOP_RT            (* boxed version *)
      val (c, cons_sigma_unboxed) = mk_cons_sigma c lev0 E.WORD_RT   (* unboxed version *)
      val (c, bool_sigma) = mk_bool_sigma c lev0
      val (c, quote_sigma) = mk_quote_sigma c lev0
      val (c, antiquote_sigma) = mk_antiquote_sigma c lev0
    in
      val cons_sigma_unboxed = cons_sigma_unboxed
      val conenv0 = ConMap.fromList [(Con.con_TRUE, bool_sigma),
				     (Con.con_FALSE, bool_sigma),
				     (Con.con_NIL, nil_sigma),
				     (Con.con_CONS, cons_sigma),
				     (Con.con_QUOTE, quote_sigma),
				     (Con.con_ANTIQUOTE, antiquote_sigma)]
    end

    val excon_env0 = ExconMap.fromList 
      (map (fn excon => (excon, (R.exnType,E.toplevel_region_withtype_top)))
       [Excon.ex_DIV, Excon.ex_MATCH,
	Excon.ex_BIND, Excon.ex_OVERFLOW, Excon.ex_INTERRUPT])

    val initial: regionStatEnv ={tyname_env = tyname_env0,
				 con_env = conenv0,
				 excon_env = excon_env0,
				 lvar_env = LvarMap.empty (*lvar_env0*) }

    fun declareTyName(tyname,arity,rse as {tyname_env, con_env, excon_env,lvar_env})=
	{tyname_env = TyNameMap.add(tyname,arity,tyname_env), 
	 con_env= con_env,
	 excon_env = excon_env,
	 lvar_env =lvar_env}

    fun declareCon(con,sigma,rse as {tyname_env, con_env, excon_env,lvar_env})=
	{tyname_env = tyname_env,
	 con_env= ConMap.add (con,sigma,con_env),
	 excon_env = excon_env,
	 lvar_env =lvar_env}

    fun declareExcon(excon,mu,rse as {tyname_env, con_env, excon_env,lvar_env})=
	{tyname_env = tyname_env,
	 con_env= con_env,
	 excon_env = ExconMap.add (excon,mu,excon_env),
	 lvar_env =lvar_env}

    fun declareLvar(lvar,range,rse as {tyname_env, con_env, excon_env,lvar_env})=
	{tyname_env = tyname_env,
	 con_env= con_env,
	 excon_env = excon_env,
	 lvar_env = LvarMap.add(lvar,range,lvar_env)}

    fun plus(rse as {tyname_env, con_env, excon_env,lvar_env},
	     rse' as {tyname_env = tyname_env', con_env=con_env', excon_env=excon_env',lvar_env=lvar_env'})=
	{tyname_env = TyNameMap.plus(tyname_env, tyname_env'),
	 con_env = ConMap.plus(con_env, con_env'),
	 excon_env = ExconMap.plus(excon_env, excon_env'),
	 lvar_env = LvarMap.plus(lvar_env, lvar_env')}

    fun lookupTyName(rse : regionStatEnv as {tyname_env,...}) = TyNameMap.lookup tyname_env

      (* To deal with togling of representation of lists we check here in the
       * lookupCon function if unboxing of datatypes is enabled:
       *)

    fun lookupCon(rse : regionStatEnv as {con_env,...}) con =
      if Con.eq(con,Con.con_CONS) then SOME cons_sigma_unboxed
      else ConMap.lookup con_env con

    fun lookupExcon(rse : regionStatEnv as {excon_env,...}) = ExconMap.lookup excon_env
    fun lookupLvar(rse  : regionStatEnv as {lvar_env,...}) = LvarMap.lookup lvar_env
    fun FoldLvar  f b (rse: regionStatEnv as {lvar_env, ...}) = LvarMap.Fold f b lvar_env
    fun FoldExcon f b (rse: regionStatEnv as {excon_env, ...}) = ExconMap.Fold f b excon_env

    val mapLvar : (lvar_env_range -> lvar_env_range) -> regionStatEnv -> regionStatEnv  =
	  fn f => fn (env as {tyname_env,con_env,excon_env,lvar_env}) =>
	     {tyname_env = tyname_env,
	      con_env= con_env,
	      excon_env=excon_env,
	      lvar_env = LvarMap.composemap f lvar_env}

    type cone = E.cone
    fun rhos_epss_free_rse (rse: regionStatEnv) =
      let val rhos_epss = FoldLvar (fn ((_,(_,_,sigma,rho,_,_)),acc) => 
				    R.ann_sigma sigma (rho::acc)) [] rse
	  val rhos_epss = FoldExcon (fn ((_,mu),acc) =>
				     R.ann_mus [mu] acc) rhos_epss rse
	  val toplevel : int = E.level E.initCone
	  val rhos_epss_free = 
	    foldl (fn (node, acc) => 
			case E.level_of node
			  of SOME level => if level = toplevel then node :: acc
					   else acc
			   | NONE => die "mkConeToplevel.rhos_epss_free.node not rho or eps.") 
	    [] rhos_epss
	  val rhos_epss_free = E.remove_duplicates rhos_epss_free
	  fun closure ([],acc) = acc
	    | closure (rho_eps::rest,acc) =
	    closure(rest, let val rho_eps= E.find rho_eps in
                           if E.is_arrow_effect rho_eps then
			    foldl (fn (node, acc) =>
                                        let val node = E.find node in
  					  if E.is_arrow_effect node then node::acc
					  else if E.is_put node orelse E.is_get node then
					    E.rho_of node :: acc
					  else 
                                            (TextIO.output(!Flags.log, "arrow effect:\n");
                                             dump(E.layout_effect_deep(rho_eps));
                                             TextIO.output(!Flags.log, "atomic effect:\n");
                                             dump(E.layout_effect_deep(node));
                                             die "mkConeToplevel.closure.node not arrow effect or get/put effect")
                                        end)
			    acc (E.represents rho_eps) (* very nasty bug fixed; the two arguments to foldL were the wrong way around;  mads *)
			  else if E.is_rho rho_eps then rho_eps :: acc
			       else acc
                         end)
	  val rhos_epss_free = E.sort(E.remove_duplicates(closure(rhos_epss_free,[])))
      in rhos_epss_free
      end

    fun mkConeToplevel (rse: regionStatEnv) : cone =
      (E.reset_cone E.emptyCone;
       E.pushLayer(rhos_epss_free_rse rse,E.emptyCone))

    fun equal_sigma(sigma1,sigma2) = R.alpha_equal (sigma1,sigma2) E.initCone

    fun equal_lvar_res((b1,b1',sigma1,place1,_,_),(b2,b2',sigma2,place2,_,_)) =
      b1=b2 andalso b1' =b2' andalso E.eq_effect(place1,place2) andalso
      equal_sigma(sigma1,sigma2)

    fun equal_con_res(sigma1,sigma2) = equal_sigma (sigma1,sigma2)

    fun equal_excon_res((tau1,place1),(tau2,place2)) = 
      E.eq_effect(place1,place2) andalso 
      equal_sigma(R.type_to_scheme tau1,R.type_to_scheme tau2)

    local
      fun tyname_env_restrict(tyname_env,tynames) =
	TyNameMap.restrict(TyName.pr_TyName,tyname_env,tynames)
	handle TyNameMap.Restrict s => die ("restrict; I cannot find tyname " ^ s ^ " in the environment")
      fun con_env_restrict(con_env,cons) =
	ConMap.restrict(Con.pr_con,con_env,cons)
	handle ConMap.Restrict s => die ("restrict; I cannot find con " ^ s ^ " in the environment")
      fun excon_env_restrict(excon_env,excons) =
	ExconMap.restrict(Excon.pr_excon,excon_env,excons)
	handle ExconMap.Restrict s => die ("restrict; I cannot find excon " ^ s ^ " in the environment")
      fun lvar_env_restrict(lvar_env,lvars) =
	LvarMap.restrict(Lvar.pr_lvar,lvar_env,lvars)
	handle LvarMap.Restrict s => die ("restrict; I cannot find lvar " ^ s ^ " in the environment")
    in
      fun restrict({tyname_env, con_env, excon_env,lvar_env}, {tynames,cons,excons,lvars}) =
	{tyname_env=tyname_env_restrict(tyname_env,tynames),
	 con_env=con_env_restrict(con_env,cons),
	 excon_env=excon_env_restrict(excon_env,excons),
	 lvar_env=lvar_env_restrict(lvar_env,lvars)}
    end

    type effectvar = E.effect
    fun places_effectvarsRSE rse = 
      let val rhos_epss = rhos_epss_free_rse rse
	  val rhos = List.filter E.is_rho rhos_epss
	  val epss = List.filter E.is_arrow_effect rhos_epss
      in (rhos,epss)
      end

    type StringTree = PP.StringTree
    val layout_scheme  = R.mk_lay_sigma false (* do not omit region info *) 
    val (_,layout_mu) = R.mk_layout     false (* do not omit region info *) 

    fun layout_pair (_,_,sigma,p,_,_) = PP.NODE{start= "(", finish = ")", indent = 1, childsep = PP.RIGHT ",",
					children = [layout_scheme sigma, E.layout_effect p]}
    fun layout_arity(a,b,c) = 
	  PP.NODE{start = "(", finish  = ")",
		  indent = 1, childsep = PP.RIGHT ", ",
		  children = PP.LEAF (Int.toString a) ::
			     (map (PP.LEAF o E.show_runType) b) @ [PP.LEAF (Int.toString c)]}

    fun layout_tyname_env e = TyNameMap.layoutMap {start = "{", eq = " -> ", finish = "}", sep = ","}
      (PP.LEAF o TyName.pr_TyName) layout_arity e

    fun layout_con_env e = ConMap.layoutMap {start = "{", eq = " -> ", finish = "}", sep = ","}
      (PP.LEAF o Con.pr_con) layout_scheme e

    fun layout_excon_env e = ExconMap.layoutMap {start = "{", eq = " -> ", finish = "}", sep = ","}
      (PP.LEAF o Excon.pr_excon) layout_mu e

    fun layout_lvar_env e = LvarMap.layoutMap {start = "{", eq = " -> ", finish = "}", sep = ","}
      (PP.LEAF o Lvar.pr_lvar) layout_pair e

    fun layout(rse as {tyname_env, con_env, excon_env,lvar_env}) =
	PP.NODE{start = "RegionStaticEnvironment:", finish = "(end of RegionStatEnvironment)",
		indent = 1, childsep = PP.RIGHT",",
		children = [layout_tyname_env tyname_env,
			    layout_con_env con_env,
			    layout_excon_env excon_env,
			    layout_lvar_env lvar_env]}

    val debug_man_enrich = Flags.is_on0 "debug_man_enrich"
    fun debug(s, b) = if debug_man_enrich() then
                         (if b then log("\nRSE." ^ s ^ ": enrich succeeded.")
			  else log("\nRSE." ^ s ^ ": enrich failed."); b)
		      else b
    fun debug1(s, b,lvenv,lvenv1) = 
	if debug_man_enrich() then
	    (if b then log("\nRSE." ^ s ^ ": enrich succeeded.")
	     else (log("\nRSE." ^ s ^ ": enrich failed."); 
		   print ("*** RSE.LVEnv =\n");
		   PP.printTree (layout_lvar_env lvenv);
		   print ("\n*** RSE.LVEnv1 =\n");
		   PP.printTree (layout_lvar_env lvenv1));
		 b)
	else b


    fun enrich ({tyname_env, con_env, excon_env,lvar_env},
		{tyname_env=tyname_env1, con_env=con_env1, excon_env=excon_env1,lvar_env=lvar_env1}) =
	debug("TyNameMap", TyNameMap.enrich (op =) (tyname_env,tyname_env1)) andalso
	debug("ConMap", ConMap.enrich equal_con_res (con_env,con_env1)) andalso
	debug("ExconMap", ExconMap.enrich equal_excon_res (excon_env,excon_env1)) andalso
	debug1("LvarMap", LvarMap.enrich equal_lvar_res (lvar_env,lvar_env1),lvar_env,lvar_env1)

    val pu_arity = Pickle.tup3Gen(Pickle.int,E.pu_runTypes,Pickle.int)

    val pu_lvar_env_range : lvar_env_range Pickle.pu =
	let open Pickle
	in convert (fn (b1,b2,s,p) => (b1,b2,s,p,NONE,NONE),
		    fn (b1,b2,s,p,NONE,NONE) => (b1,b2,s,p)
		     | _ => die "pu_lvar_env_range")
	    (tup4Gen0(bool,bool,R.pu_sigma,E.pu_effect))
	end

    val pu : regionStatEnv Pickle.pu =
	let open Pickle
	in convert (fn (te:arity TyNameMap.map,ce: R.sigma ConMap.map,
			ee:(R.Type*R.place) ExconMap.map,le) => {tyname_env=te,con_env=ce,excon_env=ee,lvar_env=le},
		    fn {tyname_env=te,con_env=ce,excon_env=ee,lvar_env=le} => (te,ce,ee,le))
	    (tup4Gen0(TyNameMap.pu TyName.pu pu_arity,
		      ConMap.pu Con.pu R.pu_sigma,
		      ExconMap.pu Excon.pu R.pu_mu,
		      LvarMap.pu Lvar.pu pu_lvar_env_range))
	end

  end
