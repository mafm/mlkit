
signature CLOS_CONV_ENV =
  sig
    type env
    type lvar
    type place
    type con
    type excon
    type offset = int
    type phsize
    type label

    datatype con_kind =
        ENUM of int
      | UNBOXED of int
      | BOXED of int

    datatype access_type =
        LVAR of lvar                            (* Variable                                  *)
      | RVAR of place                           (* Region variable                           *)
      | DROPPED_RVAR of place                   (* Dropped region variable                   *)
      | SELECT of lvar * int                    (* Select from closure or region vector      *)
      | LABEL of label                          (* Global declared variable                  *)
      | FIX of label * access_type option * int (* Label is code pointer, access_type is the *)

    datatype rho_kind =
        FF (* Rho is formal and finite *)
      | FI (* Rho is formal and infinite *)
      | LF (* Rho is letregion bound and finite *)
      | LI (* Rho is letregion bound and infinite *)

    val empty : env
    val plus  : env * env -> env
    val initialEnv : env

    val declareCon     : con * con_kind * env -> env
    val declareLvar    : lvar * access_type * env -> env
    val declareExcon   : excon * access_type * env -> env
    val declareRho     : place * access_type * env -> env
    val declareRhoKind : place * rho_kind * env -> env

    val lookupCon      : env -> con -> con_kind
    val lookupVar      : env -> lvar -> access_type
    val lookupVarOpt   : env -> lvar -> access_type option
    val lookupExcon    : env -> excon -> access_type
    val lookupExconOpt : env -> excon -> access_type option
    val lookupRho      : env -> place -> access_type
    val lookupRhoOpt   : env -> place -> access_type option
    val lookupRhoKind  : env -> place -> rho_kind

    val enrich : env * env -> bool
    val match : env * env -> unit
    val restrict : env * {lvars:lvar list,
			  cons:con list,
			  excons:excon list} -> env

    type StringTree
    val layoutEnv : env -> StringTree
  end;