(* auth_verify_user; return user_id if happy, 0 otherwise *)
fun auth_verify_user () =
  let
    val auth_user_id = Ns.Cookie.getCookieValue "auth_user_id"
    val auth_password = Ns.Cookie.getCookieValue "auth_password"
  in
    case (auth_user_id,auth_password) of
      (SOME user_id, SOME psw) =>
	(case Db.zeroOrOneField `select password from auth_user 
                                 where user_id = ^(Db.qq' user_id)` 
	   of NONE => 0
	    | SOME db_psw => 
	     if db_psw = psw then 
	       (case Int.fromString user_id of
		  NONE => 0
		| SOME u_id => u_id )
	     else 0)
    | _ => (Ns.log (Ns.Notice,"auth_verify_user (NONE): No cookies");0)
  end
handle Ns.Cookie.CookieError _ => (Ns.log (Ns.Notice,"auth_verify_user: No cookies");0)

(* auth_verify_user_filter; procedure to filter if a
   user is authenticated to request a page *)
val _ =
  let
    val target = Ns.Conn.location()^Ns.Conn.url()
    fun auth_verify_user_filter () =
      let
	val user_id = auth_verify_user ()
	val _ = Ns.log(Ns.Notice, "auth_verify_user_filter enter with: " ^ target ^ " and user_id = " ^ (Int.toString user_id))
      in
	if user_id = 0 then
	  (Ns.returnRedirect (Ns.Conn.location()^"/auth/auth_form.sml?target=" ^ 
			      Ns.encodeUrl target); Ns.exit())
	else 
	  ()
      end
  in
    (* we tell SMLserver to run our cookie checker procedure before
     serving any request for a URL that starts with "/auth/" *)
    if RegExp.regExpBool (Ns.Conn.location()^"/auth/admin/.*") target then
      auth_verify_user_filter ()
    else ()
  end



