
functor ExecutionBarry(BuildCompileBarry : BUILD_COMPILE_BARRY) : EXECUTION =
  struct
    open BuildCompileBarry
    open ExecutionArgs

    structure Basics = Elaboration.Basics
    structure TopdecGrammar = Elaboration.PostElabTopdecGrammar
    structure Tools = Basics.Tools
    structure PP = Tools.PrettyPrint
    structure Crash = Tools.Crash

    structure TyName = Basics.ModuleEnvironments.TyName
    structure DecGrammar = TopdecGrammar.DecGrammar
    structure TyVar = DecGrammar.TyVar
    structure Ident = DecGrammar.Ident
    structure StrId = DecGrammar.StrId
    structure TyCon = DecGrammar.TyCon

    structure CompileBasis = CompileBasisBarry (structure CompBasisBarry = CompBasis
						structure PP = PP
						structure Flags = Tools.Flags)

    val backend_name = "Barry"
    val backend_longname = "Barry - the Standard ML barifier"

    type CompileBasis = CompileBasis.CompileBasis
    type CEnv = CompilerEnv.CEnv
    type Env = CompilerEnv.ElabEnv
    type strdec = TopdecGrammar.strdec
    type strexp = TopdecGrammar.strexp
    type funid = TopdecGrammar.funid
    type strid = TopdecGrammar.strid
    type label = Labels.label
    type linkinfo = {unsafe:bool}
    type target = Compile.LambdaPgm

    val dummy_label = Labels.new()
    val code_label_of_linkinfo : linkinfo -> label = fn _ => dummy_label
    val imports_of_linkinfo : linkinfo -> (label list * label list) = fn _ => (nil,nil)
    val exports_of_linkinfo : linkinfo -> (label list * label list) = fn _ => (nil,nil)
    fun unsafe_linkinfo (li: linkinfo) : bool =  #unsafe li

    datatype res = CodeRes of CEnv * CompileBasis * target * linkinfo
                 | CEnvOnlyRes of CEnv
    fun compile fe (ce,CB,strdecs,vcg_file) =
      let val (cb,()) = CompileBasis.de_CompileBasis CB
      in
	case Compile.compile fe (ce, cb, strdecs)
	  of Compile.CEnvOnlyRes ce => CEnvOnlyRes ce
	   | Compile.CodeRes(ce,cb,target,safe) => 
	    let 
		(* to use not(safe) below, we should compile lvars, etc., to labels and 
		 * use imports and exports appropriately *)
		val linkinfo : linkinfo = {unsafe=true(*not(safe)*)}   
		val CB = CompileBasis.mk_CompileBasis(cb,())
	    in CodeRes(ce,CB,target,linkinfo)
	    end
      end
    val generate_link_code = NONE
    fun emit a = Compile.emit a
    fun link_files_with_runtime_system _ files run =
	let val pm_file = run ^ ".pm"
	    val os = TextIO.openOut pm_file
	in 
	    (TextIO.output(os, "(* Generated by " ^ backend_longname ^ " *)\n\n");
	     app (fn f => TextIO.output(os, f ^ "\n")) files;
	     TextIO.closeOut os;
	     print("[Created file " ^ pm_file ^ "]\n"))
	    handle X => (TextIO.closeOut os; raise X)
	end

    val pu_linkinfo =
	let open Pickle
	in convert (fn b => {unsafe=b},
		    fn {unsafe=b} => b)
	    bool
	end
  end

