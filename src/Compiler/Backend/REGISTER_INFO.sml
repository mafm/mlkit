signature REGISTER_INFO =
  sig
    eqtype reg 
    type lvar 
    type lvarset

    val is_reg     : lvar -> bool
    val lv_to_reg  : lvar -> reg  (* Die if lvar is not a precolored register *)
    val args_phreg : lvar list (* Machine registers containing arguments *)
    val res_phreg  : lvar list (* Machine registers containing results *)

    val all_regs : lvar list

    val args_phreg_ccall : lvar list  (* Machine registers containing arguments in CCALLs *)
    val res_phreg_ccall  : lvar list  (* Machine registers containing results in CCALLs *)

    val caller_save_phregs   : lvar list
    val caller_save_phregset : lvarset
    val is_caller_save       : lvar -> bool      

    val callee_save_ccall_phregs   : lvar list
    val callee_save_ccall_phregset : lvarset
    val is_callee_save_ccall       : lvar -> bool      

    val caller_save_ccall_phregs   : lvar list
    val caller_save_ccall_phregset : lvarset
    val is_caller_save_ccall       : lvar -> bool

    val pr_reg : reg -> string
    val reg_eq : reg * reg -> bool

  end