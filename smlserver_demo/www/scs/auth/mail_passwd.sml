val email = ScsFormVar.wrapFail ScsFormVar.getLoginErr ("email","Email")

val email = email^"@it-c.dk"

val emsg = [(ScsLang.en,`You typed an email that is either not in our database or your account has not been activated - 
			 please click your browsers back button and try again or contact the %0  if you believe
                            your account is not as it should be.<p>`),
            (ScsLang.da,`Du har enten indtastet en email, som ikke er i vores database eller din konto er ikke 
                         aktiveret. Du kan g� tilbage til forrige side og pr�ve igen eller sende en mail til
                         %0 hvis du mener der er tale om en fejl. <p>`)]

val (passwd,first_names,last_name) =
  ScsDb.oneRowErrPg' (fn g => (g "password", g "first_names", g "last_name"),
		      `select password,first_names,last_name
                         from scs_persons, scs_users, scs_parties
		        where scs_parties.email = ^(Db.qqq email)
                          and scs_parties.party_id = scs_persons.person_id
                          and scs_persons.person_id = scs_users.user_id
                          and scs_parties.deleted_p = 'f'
                          and scs_persons.deleted_p = 'f'
                          and scs_users.deleted_p = 'f'
                          and password is not null`,
                        ScsDict.sl' emsg [Quot.toString (Html.aemail (ScsConfig.scs_site_name()) "Site administrator")])

val mail_msg = [(ScsLang.da,`Hej %0 %1

Du har adgang til %4 fra

     %5

  Login: %2
  Password: %3

Med venlig hilsen

%4 

-------------------

Dear %0 %1

You can access %4 from

    %5

  Login: %2
  Password: %3

Best Regards,

%4`)]

val html_msg = `Du vil om kort tid modtage en email med dit password.<br>
  <a href="/scs/auth/auth_form.sml">Tilbage til login siden</a><p>
  (eng. In a short time, you'll receive an email with your password.<br>
   <a href="/scs/auth/auth_form.sml">Go to the login page</a>`

val html_title = "Password er tilsendt pr. mail (eng. Password has been mailed)"

val _ = 
  (Ns.Mail.send {to=email, from=ScsConfig.scs_site_adm_email(),subject="Obtain Password",
		 body=ScsDict.sl mail_msg [first_names,last_name,email,passwd,
                                           ScsConfig.scs_site_name(),ScsConfig.scs_site_url()]};
   ScsPage.returnPg html_title html_msg  )
