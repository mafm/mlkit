val _ = Db.dml `insert into cs (id, text) 
                values (^(Db.seqNextvalExp "cs_seq"), 
                        '������ dejligt')`

val _ = Ns.returnRedirect "cs_form.sml"
	
