structure Http : HTTP_EXTRA =
    struct
	type html = XHtml.html
	type response = string
	fun returnHtml h =
	    ("HTTP/1.0 200 OK\n\
	     \MIME-Version: 1.0\n\
	     \Content-type: text/html\n\n" ^ 
	     XHtml.Unsafe.toString h)

        fun setCookies cookies =
	    concat (map (fn c => SMLserver.Cookie.setCookie c ^ "\n") cookies)

	fun returnHtml' nil h = returnHtml h
	  | returnHtml' cookies h =
	    ("HTTP/1.0 200 OK\n\
	     \MIME-Version: 1.0\n\
	     \Content-type: text/html\n" ^ setCookies cookies ^ "\n" ^
	     XHtml.Unsafe.toString h)

	structure Unsafe =
	    struct
		fun toString x = x

		fun redirect link cookies =
		    ("HTTP/1.0 302 Found\n\
		     \Location: " ^ link ^ "\n\
		     \MIME-Version: 1.0\n" ^ setCookies cookies ^ "\n\
		     \You should not be seeing this!")
	    end
    end
