  (* Assume either (1) form variable wid is present 
   * or (2) form variables name and year are present *)

  val (wid, name, year) =
    case FormVar.wrapOpt FormVar.getNatErr "wid" of 
      SOME wid =>   (* get name and year *)
	let val wid = Int.toString wid
	    val query = 
	      `select name, year from wine 
	       where wid = ^wid`
	in case Db.oneRow query of
	  [name,year] => (wid, name, year)
	| _ => raise Fail "add.sml"       
	end
    | NONE => 
	let val name = FormVar.wrapFail FormVar.getStringErr ("name","name of wine")
	    val year = 
	      FormVar.wrapFail (FormVar.getIntRangeErr 0 3000) ("year", "year of wine")
	    val year = Int.toString year
	    val query = 
	      `select wid from wine 
	       where name = ^(Db.qq' name)
		 and year = ^(Db.qq' year)`
	in 
	  case Db.zeroOrOneRow query of
	    SOME [wid] => (wid, name, year)
	  | _ => (* get fresh wid from RDBMS *)
	      let val wid = Int.toString 
		    (Db.seqNextval "wid_sequence")
		  val _ = Db.dml
		    `insert into wine (wid, name, year)
		     values (^wid, 
			     ^(Db.qq' name), 
			     ^(Db.qq' year))`
	      in (wid, name, year)
	      end
	end

  (* return forms to the user... *)
  val _ = 
    RatingUtil.returnPageWithTitle 
    ("Your comments to ``" ^ name ^ " - year " ^ year ^ "''")
    `<form action=add0.sml>
      <input type=hidden name=wid value=^wid>
      <textarea rows=5 cols=40 name=comment></textarea><br>
      <b>Email:</b>&nbsp; 
      <input type=text name=email size=30><br>
      <b>Name:</b>&nbsp; 
      <input type=text name=fullname size=30><br>
      <b>Rate (between 0 and 6):</b>&nbsp; 
      <input type=text name=rating size=2>&nbsp; 
      <input type=submit value="Rate it"> 
      <p>Back to <a href=index.sml>Best Wines</a>
     </form>`
