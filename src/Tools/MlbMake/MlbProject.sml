functor MlbProject (Env : ENVIRONMENT) : MLB_PROJECT = 
    struct
	structure Bid :>
	    sig eqtype bid and longbid
		val bid : string -> bid
		val longbid : bid list -> longbid
		val longopen : longbid -> bid * longbid option
		val pp_bid : bid -> string
		val pp_longbid : longbid -> string
		val explode : longbid -> bid list
	    end =
	struct
	    type bid = string 
	    type longbid = bid list
	    fun bid s = s
	    fun pp_bid s = s
	    fun longbid (bids:bid list) : longbid = bids
	    fun longopen nil = raise Fail "empty longbid"
	      | longopen [bid] = (bid,NONE)
	      | longopen (bid::longbid) = (bid, SOME longbid)
	    fun pp_longbid nil = raise Fail "empty longbid"
	      | pp_longbid [b] = pp_bid b
	      | pp_longbid (b::bs) = pp_bid b ^ "." ^ pp_longbid bs
	    fun explode ss = ss
	end

	fun supported_annotation s =
	    case s of
		"safeLinkTimeElimination" => true
	      | _ => false

	type atbdec = string (* path.{sml,sig} *)
	datatype bexp = BASbexp of bdec
                      | LETbexp of bdec * bexp
                      | LONGBIDbexp of Bid.longbid

             and bdec = SEQbdec of bdec * bdec
	              | EMPTYbdec 
                      | LOCALbdec of bdec * bdec
                      | BASISbdec of Bid.bid * bexp
                      | OPENbdec of Bid.longbid list
	              | ATBDECbdec of atbdec
		      | MLBFILEbdec of string * string option  (* path.mlb <scriptpath p> *)
	              | SCRIPTSbdec of atbdec list
	              | ANNbdec of string * bdec

	val depDir : string ref = ref "PM"

	fun error (s : string) = 
	    (print ("\nError: " ^ s ^ ".\n\n"); raise Fail "MlbProject.error")

	fun warn (s : string) = print ("\nWarning: " ^ s ^ ".\n\n")

	fun quot s = "'" ^ s ^ "'"

	fun has_ext(s: string,ext) = 
	    case OS.Path.ext s of 
		SOME ext' => ext = ext'
	      | NONE => false
		    
	fun member s l = let fun m [] = false
			       | m (x::xs) = x = s orelse m xs
			 in m l
			 end
		     
	fun drop_comments (file:string) (l: char list) : char list =
	  let fun loop(n, #"(" :: #"*" :: rest ) = loop(n+1, rest)
		| loop(n, #"*" :: #")" :: rest ) = loop(n-1, if n=1 then #" "::rest else rest)
		| loop(0, ch ::rest) = ch :: loop (0,rest)
		| loop(0, []) = []
		| loop(n, ch ::rest) = loop(n,rest)
		| loop(n, []) = error ("Unclosed comment in project " ^ quot(file))
	  in loop(0,l)
	  end

	fun is_symbol #"=" = true
	  | is_symbol _ = false

	fun lex chs : string list =
	    let 
		fun lex_symbol (c::chs) =
		    if is_symbol c then SOME (c,chs) else NONE
		  | lex_symbol nil = NONE

		fun lex_whitesp (all as c::rest) = 
		    if Char.isSpace c then lex_whitesp rest else all 
		  | lex_whitesp [] = []

		fun lex_string (c::rest, acc) = 
		    if is_symbol c then (implode(rev acc), c::rest)
		    else if Char.isSpace c then (implode(rev acc), rest)
			 else lex_string (rest, c::acc)
		  | lex_string ([], acc) = (implode(rev acc), [])

		fun lex0 (chs : char list, acc) : string list =
		    case lex_whitesp chs of 
			[] => rev acc
		      | chs => lex0 (case lex_symbol chs of 
					 SOME (c,chs) => (chs, Char.toString c :: acc)
				       | NONE => let val (s, chs) = lex_string(chs,[])
						 in (chs, s::acc) 
						 end)
	    in lex0(chs,[])
	    end

	fun is_symb s =
	    case explode s of
		[c] => is_symbol c
	      | _ => false

	fun is_mlbfile s =
	    has_ext (s,"mlb")

	fun is_smlfile s = 
	    has_ext(s,"sml") orelse has_ext(s,"sig") orelse has_ext(s,"fun")

	fun is_id s = 
	    case explode s of
		c::cs => Char.isAlpha c 
		    andalso List.all (fn c => Char.isAlphaNum c 
				      orelse c = #"_"
				      orelse c = #"'") cs
	      | _ => false

	fun is_valid_path p =
	    case String.fields (fn x => x = #"/") p of
		f :: rest => (List.all (fn x => is_id x andalso not (is_mlbfile x orelse is_smlfile x)) rest
			      andalso (is_id f andalso not (is_mlbfile f orelse is_smlfile f) 
				       orelse f = ""))
	      | _ => false

	local
	    fun is_keyword s = 
		case s of
		    "open" => true
		  | "let" => true
		  | "local" => true
		  | "in" => true
		  | "end" => true
		  | "bas" => true
		  | "basis" => true
		  | "scriptpath" => true
		  | "ann" => true
		  | _ => false
			
	    fun is_fileext s =
		case s of
		    "mlb" => true
		  | "sml" => true
		  | "sig" => true
		  | _ => false
			
	in
	    fun is_bid s =
		is_id s andalso not (is_keyword s) andalso not (is_fileext s)

	    fun is_longbid s = 
		let val fs = String.fields (fn c => c = #".") s
		in if List.all is_bid fs then SOME (Bid.longbid (map Bid.bid fs))
		   else NONE
		end
	end

	fun print_ss ss = (print "Tokens: "; app (fn s => print (s ^ " ")) ss; print "\n")
			
        fun parse_error mlbfile msg = error ("while parsing basis file " ^ quot mlbfile ^ " : " ^ msg)
        fun parse_error1 mlbfile (msg, rest: string list) = 
          case rest of 
            [] => error ("while parsing basis file " ^ quot mlbfile ^ " : " ^ msg ^ "(reached end of file)")
          | s::_ => error ("while parsing basis file " ^ quot mlbfile ^ " : " ^ msg ^ "(reached " ^ quot s ^ ")")


	fun expand mlbfile s = 
	    let 
		fun readUntil c0 nil acc = parse_error mlbfile "malformed path-var"
		  | readUntil c0 (c::cc) acc =
		    if c = c0 then
			let val pathVar = implode (rev acc)
			    val cc = 
				case cc of 
				    #"/"::cc => cc
				  | _ => cc
			in case (Env.getEnvVal (pathVar)) of
			    SOME path => OS.Path.concat(path, implode cc)
			  | NONE => parse_error mlbfile ("path variable $(" ^ pathVar ^") not in env")
			end
		    else readUntil c0 cc (c::acc)
	    in		
		case explode s of
		    #"$" :: #"(" :: cc => readUntil #")" cc nil
		  | #"$" :: cc => readUntil #"/" cc nil
		  | _ => s
	    end

	fun parse_bdec_more mlbfile (bdec,ss) =
	    case parse_bdec_opt mlbfile ss of
		SOME(bdec',ss) => SOME(SEQbdec(bdec,bdec'),ss)
	      | NONE => SOME(bdec,ss)

	and parse_bexp mlbfile (ss:string list) : bexp * string list =	    
	    case ss of
		nil => parse_error1 mlbfile ("missing basis expression", ss)
	      | "let" :: ss => 
		    let 
			fun parse_rest(bdec,ss) =
			    case ss of 
				"in" :: ss => 
				    let val (bexp,ss) = parse_bexp mlbfile ss
				    in 
					case ss of 
					    "end" :: ss => (LETbexp(bdec,bexp),ss)
					  | _ => parse_error1 mlbfile ("missing 'end'", ss)
				    end
			      | _ => parse_error1 mlbfile ("missing 'in'", ss)
		    in case parse_bdec_opt mlbfile ss of 
			NONE => parse_rest(EMPTYbdec,ss)
		      | SOME(bdec,ss) => parse_rest(bdec,ss)
		    end
	      | "bas" :: ss => 
		    let 
			fun parse_rest(bdec,ss) =
			    case ss of
				"end" :: ss => (BASbexp bdec, ss)
			      | _ => parse_error1 mlbfile ("missing 'end'", ss)
		    in
			case parse_bdec_opt mlbfile ss of 
			    NONE => parse_rest(EMPTYbdec,ss)
			  | SOME(bdec,ss) => parse_rest(bdec,ss)
		    end
	      | s :: ss' => 
		    (case is_longbid s of
			 SOME longbid => (LONGBIDbexp longbid,ss')
		       | NONE => parse_error1 mlbfile ("invalid basis expression", ss))

	and parse_ann mlbfile ss =
	    case ss of
		s::ss => 
		    if supported_annotation s then (s,ss)
		    else parse_error1 mlbfile ("non-supported annotation after 'ann'", ss)
	      | _ => parse_error1 mlbfile ("missing annotation after 'ann'", ss)
			
	and parse_bdec_opt mlbfile ss =
	    case ss of
		"local" :: ss => 
		    let 
			fun parse_rest'(bdec,bdec',ss) =
			    case ss of 
				"end" :: ss => parse_bdec_more mlbfile (LOCALbdec(bdec,bdec'),ss)
			      | _ => parse_error1 mlbfile ("I expect an 'end'", ss)
			fun parse_rest(bdec,ss) =
			    case ss of 
				"in" :: ss => 
				    (case parse_bdec_opt mlbfile ss of 
					 NONE => parse_rest'(bdec,EMPTYbdec,ss)
				       | SOME(bdec',ss) => parse_rest'(bdec,bdec',ss))
			      | _ => parse_error1 mlbfile ("I expect an 'in'", ss)
		    in case parse_bdec_opt mlbfile ss of 
			NONE => parse_rest(EMPTYbdec,ss)
		      | SOME(bdec,ss) => parse_rest(bdec,ss)
		    end
	      | "basis" :: ss =>
		    (case ss of
			 nil => parse_error1 mlbfile ("I expect a basis identifier", ss)
		       | bid :: ss =>
			     if not (is_bid bid) then
				 parse_error1 mlbfile ("I expect a basis identifier", ss)
			     else
			     (case ss of
				  "=" :: ss => 
				      let val (bexp,ss) = parse_bexp mlbfile ss
				      in parse_bdec_more mlbfile (BASISbdec(Bid.bid bid,bexp),ss)
				      end
				| _ => parse_error1 mlbfile ("missing '='", ss)))
	      | "open" :: ss => 	
			 let 
			     fun readBids (nil,acc) = (rev acc, nil)
			       | readBids (ss_all as (s::ss),acc) = 
				 (case is_longbid s of
				      SOME longbid => readBids(ss,longbid::acc)
				    | NONE => (rev acc, ss_all))
			     val (longbids,ss) = readBids (ss,nil)
			 in parse_bdec_more mlbfile (OPENbdec longbids,ss)
			 end
	      | "scripts" :: ss => 
			 let 
			     fun readSrcs (nil,_) = 
				 parse_error1 mlbfile ("Missing 'end' in 'scripts ... end' at end of file",nil)
			       | readSrcs ("end"::ss,acc) = (rev acc,ss)
			       | readSrcs (ss_all as (s::ss),acc) =				 
				 if is_smlfile s then readSrcs(ss,s::acc)
				 else parse_error1 mlbfile ("Expecting src-file or 'end' in 'scripts ... end' construct",ss)
			     val (srcs,ss) = readSrcs (ss,nil)
			 in parse_bdec_more mlbfile (SCRIPTSbdec srcs,ss)
			 end
	      | "ann" :: ss =>
		    let 
			fun parse_rest'(ann,bdec,ss) =
			    case ss of 
				"end" :: ss => parse_bdec_more mlbfile (ANNbdec(ann,bdec),ss)
			      | _ => parse_error1 mlbfile ("I expect an 'end'", ss)
			fun parse_rest(ann,ss) =
			    case ss of 
				"in" :: ss => 
				    (case parse_bdec_opt mlbfile ss of 
					 NONE => parse_rest'(ann,EMPTYbdec,ss)
				       | SOME(bdec,ss) => parse_rest'(ann,bdec,ss))
			      | _ => parse_error1 mlbfile ("I expect an 'in'", ss)
		    in case parse_ann mlbfile ss of 
		         (ann,ss) => parse_rest(ann,ss)
		    end
 	      | s :: ss =>
			 if is_smlfile s then parse_bdec_more mlbfile (ATBDECbdec (expand mlbfile s),ss)
			 else 
			     if is_mlbfile s then 
				 let val (opt,ss) =
				       (case ss of
					    "scriptpath" :: ss =>
						(case ss of
						     p :: ss' => 
							 if is_valid_path p then (SOME p,ss')
							 else parse_error1 mlbfile ("invalid path following SCRIPTPATH keyword",ss)
						   | _ => parse_error1 mlbfile ("missing path to follow SCRIPTPATH keyword",ss))
					  | _ => (NONE,ss))
				 in parse_bdec_more mlbfile (MLBFILEbdec (expand mlbfile s,opt),ss)
				 end
			     else NONE
	      | nil => NONE

	fun fromFile' (filename:string) : string option =
	    SOME(MlbFileSys.fromFile filename) handle _ => NONE

	fun parse (mlbfile: string) : bdec =
	    if not (has_ext(mlbfile, "mlb")) then 
		error ("The basis file " ^ quot mlbfile ^ " does not have extension 'mlb'")	    
	    else
		let (* val _ = print ("currently at " ^ OS.FileSys.getDir() ^ "\n") *)
		    val ss = (lex o (drop_comments mlbfile) o explode o MlbFileSys.fromFile) mlbfile
		    (* val _ = print_ss ss *)
		in  case parse_bdec_opt mlbfile ss of
		    SOME (bdec,nil) => bdec
		  | SOME (bdec,ss) => parse_error1 mlbfile ("misformed basis declaration", ss)
		  | NONE => parse_error1 mlbfile ("missing basis declaration", ss)
		end
	    handle IO.Io {name=io_s,cause,...} => error ("The basis file " ^ quot mlbfile ^ " cannot be opened")


	(* Support for writing dependency information to disk in .d-files. *)

	fun dirMod dir file = if OS.Path.isAbsolute file then file
			      else OS.Path.concat(dir,file)
			
	structure DepEnv = 
	    struct
		type L = string list	    
		datatype D = D of L * (Bid.bid * D) list
		fun lookup d longbid : D option =
		    let fun look nil _ = NONE
			  | look ((x,d)::xs) y = if x = y then SOME d else look xs y
			fun lookD _ nil = raise Fail "empty longbid"
			  | lookD (D(_,xs)) [y] = look xs y
			  | lookD (D(_,xs)) (y::ys) =
			    case look xs y of
				SOME d => lookD d ys
			      | NONE => NONE
		    in lookD d (Bid.explode longbid)
		    end
		fun plus (D(L1,M1),D(L2,M2)) = D(L1 @ L2, M1 @ M2)

		fun getL (D(L,_)) : L = L
		fun singleBidEntry e = D(nil,[e])
		fun singleFile f = D([f],nil)
		val empty = D(nil,nil)
		fun dirModify ("", dep) = dep
		  | dirModify (dir, dep : D) : D =
		    let fun depMap f (D(L,bds)) = D(map f L,map (fn (b,d) => (b,depMap f d)) bds)
		    in depMap (dirMod dir) dep
		    end
	    end

	fun timeMax(t1,t2) = if Time.<(t1,t2) then t2 else t1

	fun maybe_create_dir d : unit = 
	    if OS.FileSys.access (d, []) handle _ => error ("I cannot access directory " ^ quot d) then
		if OS.FileSys.isDir d then ()
		else error ("The file " ^ quot d ^ " is not a directory")
	    else ((OS.FileSys.mkDir d;()) handle _ => 
		  error ("I cannot create directory " ^ quot d ^ " --- the current directory is " ^ 
			 OS.FileSys.getDir()))
		
	fun maybe_create_dirs path dirs =
	    let val dirs = String.tokens (fn c => c = #"/") dirs
		fun append_path "" d = d
		  | append_path p d = p ^ "/" ^ d
		fun loop (p, nil) = ()
		  | loop (p, d::ds) = let val p = append_path p d
				      in maybe_create_dir p; loop(p, ds)
				      end
	    in loop(path, dirs)
	    end

	fun maybe_create_depdir path = 
	    maybe_create_dirs path (!depDir)

	fun writeDep pathfile s =
	    (let val os = TextIO.openOut pathfile
	     in (  TextIO.output(os,s)
		 ; TextIO.closeOut os
		 (* ; print ("File " ^ pathfile ^ " updated\n") *)
                ) handle ? => (TextIO.closeOut os; raise ?)
	     end handle _ => error("Failed to write dependencies to file " ^ quot pathfile))		 

	fun fileNewer t file : bool =
	    Time.>(OS.FileSys.modTime file,t) handle _ => false

	fun mkAbs file = OS.Path.mkAbsolute{path=file,relativeTo=OS.FileSys.getDir()}

	fun subtractDir _ "" = (fn p => p)
	  | subtractDir hasLink dir =
      if hasLink
      then fn p => if OS.Path.isAbsolute p
                   then p
                   else OS.Path.concat (MlbFileSys.getCurrentDir (),p)
      else
	    let val dir_abs = mkAbs dir
	    in fn p =>
		let val p_abs = mkAbs p
        val _ = if OS.Path.isAbsolute dir then print ("mkAbs: " ^ p ^ " " ^ p_abs ^ " " ^ dir ^ "\n") else ()
		in OS.Path.mkRelative{path=p_abs,relativeTo=dir_abs}
		end
	    end

  local
    fun hasLinks d = 
          let 
            val islink = fn x => (OS.FileSys.isLink x handle OS.SysErr (s,e) => 
                                 error ("Couldn't get status on " ^ x ^" : " ^ (Option.getOpt (Option.map OS.errorMsg e, ""))))
            val {arcs,vol,isAbs} = OS.Path.fromString d
          in
            case arcs 
            of [] => false
             | (x::xr) => #2(List.foldl (fn (x,(y,b)) =>
                                             let val y' = OS.Path.concat (y,x)
                                             in (y',b orelse islink y')
                                             end)
                            (let val a = OS.Path.toString {vol = vol, isAbs = isAbs, arcs = [x]}
                                 in (a, islink a)
                                 end)
                            xr)
          end
  in
	fun maybeWriteDep smlfile (modTimeMlbFileMax:Time.time) D : unit =
	    let val {dir,file} = OS.Path.splitDirFile smlfile
		infix ## 
		val op ## = OS.Path.concat
		val file = dir ## (!depDir) ## (file ^ ".d")
	    in if fileNewer modTimeMlbFileMax file then ()         (* Don't write .d-file if the current .d-file *)
	       else                                                  (*  is newer than the mlb-file or any imported mlb-file. *)
		   let val L = DepEnv.getL D
		       val L = map (subtractDir (hasLinks dir) dir) L
		       val s = concat (map (fn s => s ^ " ") L)
		       fun write() =
			   ((if dir = "" then ()
			     else maybe_create_depdir dir);
			    writeDep file s)
		   in case fromFile' file of
		       SOME s' => if s = s' then ()                  (* Don't write .d-file if its content already *)
				  else write()                       (*  specifies the correct dependencies. *)
		     | NONE => write()
		   end
	    end
  end

	val op + = DepEnv.plus
	type D = DepEnv.D
	type A = {modTimeMlbFileMax: Time.time, mlbfiles: (string * D) list}   (* max-modtime of mlb-files met so far *)
	val emptyA = {modTimeMlbFileMax=Time.zeroTime,mlbfiles=nil}
	fun lookupA {modTimeMlbFileMax, mlbfiles} mlbfile : D option =
	    let fun look nil = NONE
		  | look ((x,D)::xs) = if mlbfile = x then SOME D
				       else look xs
	    in look mlbfiles
	    end

	fun dep_bexp (D:D) (A:A) bexp : D * A =
	    case bexp of
	        BASbexp bdec => dep_bdec D A bdec
	      | LETbexp (bdec,bexp) =>
		    let val (D1,A) = dep_bdec D A bdec
			val (D2,A) = dep_bexp (D+D1) A bexp
		    in (D2,A)
		    end
	      | LONGBIDbexp longbid =>
		    (case DepEnv.lookup D longbid of
			 SOME D => (D,A)
		       | NONE => error ("The long basis identifier " 
					^ Bid.pp_longbid longbid 
					^ " is undefined"))

	and dep_bdec (D:D) (A:A) bdec : D * A =
	    case bdec of
		SEQbdec (bdec1,bdec2) =>
		    let val (D1,A) = dep_bdec D A bdec1
			val (D2,A) = dep_bdec (D + D1) A bdec2
		    in (D1 + D2, A)
		    end
	      | EMPTYbdec => (DepEnv.empty,A)
	      | LOCALbdec (bdec1,bdec2) =>
		    let val (D1,A) = dep_bdec D A bdec1
			val (D2,A) = dep_bdec (D + D1) A bdec2
		    in (D2,A)
		    end
	      | BASISbdec (bid, bexp) =>
		    let val (D',A) = dep_bexp D A bexp
		    in (DepEnv.singleBidEntry (bid,D'), A)
		    end
	      | OPENbdec longbids =>
		    let val D' = 
			foldl (fn (longbid,Dacc) => 
			       case DepEnv.lookup D longbid of
				   SOME D => Dacc + D
				 | NONE => error ("The long basis identifier " 
						  ^ Bid.pp_longbid longbid 
						  ^ " is undefined")) DepEnv.empty longbids
		    in (D',A)
		    end
	      | ATBDECbdec smlfile =>
		    let val _ = maybeWriteDep smlfile (#modTimeMlbFileMax A) D
		    in (DepEnv.singleFile smlfile, A)
		    end
	      | MLBFILEbdec (mlbfile,_) => 
	            let val (D,A) = dep_bdec_file A mlbfile
		    in (DepEnv.dirModify (OS.Path.dir mlbfile, D), A)
		    end
	      | SCRIPTSbdec smlfiles => 
		    let val t = #modTimeMlbFileMax A
			val _ = app (fn f => maybeWriteDep f t D) smlfiles
		    in (DepEnv.empty, A)
		    end
	      | ANNbdec (s,bdec) => dep_bdec D A bdec

	and dep_bdec_file (A:A) mlbfile_rel : D * A =
	    let val mlbfile_abs = mkAbs mlbfile_rel
	    in
		case lookupA A mlbfile_abs of
		    SOME D => (D,A)
		  | NONE =>
			let val {cd_old,file=mlbfile} = MlbFileSys.change_dir mlbfile_rel
			in let val _ = maybe_create_depdir ""
			       val bdec = parse mlbfile
			       val modTimeMlbFileMaxOld = #modTimeMlbFileMax A
			       val modTimeMlbFileMaxNew = OS.FileSys.modTime mlbfile
				   handle _ => error ("Failed to read the modification time of the basis file " ^
						      mlbfile)
			       val A = {modTimeMlbFileMax=modTimeMlbFileMaxNew,
					mlbfiles= #mlbfiles A}
			       val (D,A) = dep_bdec DepEnv.empty A bdec
			   in  cd_old() ; 
			       (D, {modTimeMlbFileMax=timeMax(modTimeMlbFileMaxOld,modTimeMlbFileMaxNew),
				    mlbfiles=(mlbfile_abs,D) :: #mlbfiles A})
			   end handle X => (cd_old(); raise X)
			end
	    end

	fun dep (mlbfile : string) : unit =
	    (dep_bdec_file emptyA mlbfile; ())

	fun map2 f ss = map (fn (x,y,a) => (f x, f y,a)) ss

	(* Support for finding the source files of a basis file *)

	datatype srctype = SRCTYPE_ALL | SRCTYPE_SCRIPTSONLY | SRCTYPE_ALLBUTSCRIPTS

	val emptyA = nil

	fun srcs_bdec_file T mlbs mlbfile_rel =
	    let val mlbfile_abs = mkAbs mlbfile_rel
	    in if member mlbfile_abs mlbs then (nil,mlbs)
	       else let val {cd_old,file=mlbfile} = MlbFileSys.change_dir mlbfile_rel
		    in 
			let val bdec = parse mlbfile
			    val (ss, mlbs) = srcs_bdec T emptyA mlbfile mlbs bdec
			    val ss = map2 (dirMod (OS.Path.dir mlbfile_rel)) ss
			in cd_old()
			    ; (ss,mlbfile_abs::mlbs)
			end handle X => (cd_old(); raise X)
		    end 
	    end

	and srcs_bdec T A mlbfile mlbs bdec =
	    case bdec of 
		SEQbdec (bdec1,bdec2) =>
		    let val (ss1,mlbs) = srcs_bdec T A mlbfile mlbs bdec1
			val (ss2,mlbs) = srcs_bdec T A mlbfile mlbs bdec2
		    in (ss1@ss2,mlbs)
		    end
	      | EMPTYbdec => (nil,mlbs)
	      | LOCALbdec (bdec1,bdec2) =>
		    let val (ss1,mlbs) = srcs_bdec T A mlbfile mlbs bdec1
			val (ss2,mlbs) = srcs_bdec T A mlbfile mlbs bdec2
		    in (ss1@ss2,mlbs)
		    end
	      | BASISbdec (bid,bexp) => srcs_bexp T A mlbfile mlbs bexp
	      | OPENbdec _ => (nil,mlbs)
	      | ATBDECbdec smlfile => 
		    let val L = case T of SRCTYPE_SCRIPTSONLY => nil
		                        | _ => [(smlfile,mlbfile,A)]
		    in (L,mlbs)
		    end
	      | MLBFILEbdec (mlbfile,_) => srcs_bdec_file T mlbs mlbfile
	      | SCRIPTSbdec smlfiles => 
		    let val L = case T of SRCTYPE_ALLBUTSCRIPTS => nil
		                        | _ => map (fn f => (f,mlbfile,A)) smlfiles
		    in (L,mlbs)
		    end
	      | ANNbdec (ann,bdec) => srcs_bdec T (ann::A) mlbfile mlbs bdec

	and srcs_bexp T A mlbfile mlbs bexp =
	    case bexp of
		BASbexp bdec => srcs_bdec T A mlbfile mlbs bdec
	      | LETbexp (bdec,bexp) =>
		    let val (ss1,mlbs) = srcs_bdec T A mlbfile mlbs bdec
			val (ss2,mlbs) = srcs_bexp T A mlbfile mlbs bexp
		    in (ss1@ss2,mlbs)
		    end
	      | LONGBIDbexp _ => (nil,mlbs)
	
	fun sources (T:srctype) (mlbfile : string) : (string * string * string list) list =
	    #1 (srcs_bdec_file T nil mlbfile)
    
    end
	
