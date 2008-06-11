(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, * CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* $Id$ *)

(* cr�er un Makefile pour un d�veloppement Coq automatiquement *)

type target =
  | ML of string (* ML file : foo.ml -> (ML "foo") *)
  | V of string  (* V file : foo.v -> (V "foo") *)
  | Special of string * string * string (* file, dependencies, command *)
  | Subdir of string
  | Def of string * string (* X=foo -> Def ("X","foo") *)
  | Include of string
  | RInclude of string * string (* -R physicalpath logicalpath *)

let output_channel = ref stdout
let makefile_name = ref "Makefile"
let make_name = ref ""

let some_file = ref false
let some_vfile = ref false
let some_mlfile = ref false

let opt = ref "-opt"
let impredicative_set = ref false

let print x = output_string !output_channel x
let printf x = Printf.fprintf !output_channel x

let rec print_list sep = function
  | [ x ] -> print x
  | x :: l -> print x; print sep; print_list sep l
  | [] -> ()

let section s =
  let l = String.length s in
  let sep = String.make (l+5) '#'
  and sep2 = String.make (l+5) ' ' in
  String.set sep (l+4) '\n';
  String.set sep2 0 '#';
  String.set sep2 (l+3) '#';
  String.set sep2 (l+4) '\n';
  print sep;
  print sep2;
  print "# "; print s; print " #\n";
  print sep2;
  print sep;
  print "\n"

let usage () =
  output_string stderr "Usage summary:

coq_makefile [subdirectory] .... [file.v] ... [file.ml] ... [-custom
  command dependencies file] ... [-I dir] ... [-R physicalpath logicalpath]
  ... [VARIABLE = value] ...  [-opt|-byte] [-f file] [-o file] [-h] [--help]

[file.v]: Coq file to be compiled
[file.ml]: ML file to be compiled
[subdirectory] : subdirectory that should be \"made\"
[-custom command dependencies file]: add target \"file\" with command
  \"command\" and dependencies \"dependencies\"
[-I dir]: look for dependencies in \"dir\"
[-R physicalpath logicalpath]: look for dependencies resursively starting from
 \"physicalpath\". The logical path associated to the physical path is
 \"logicalpath\".
[VARIABLE = value]: Add the variable definition \"VARIABLE=value\"
[-byte]: compile with byte-code version of coq
[-opt]: compile with native-code version of coq
[-impredicative-set]: compile with option -impredicative-set of coq
[-f file]: take the contents of file as arguments
[-o file]: output should go in file file 
[-h]: print this usage summary
[--help]: equivalent to [-h]\n";
  exit 1

let standard sds sps =
  print "byte:\n";
  print "\t$(MAKE) all \"OPT:=-byte\"\n\n";
  print "opt:\n";
  if !opt = "" then print "\t@echo \"WARNING: opt is disabled\"\n";
  print "\t$(MAKE) all \"OPT:="; print !opt; print "\"\n\n";
  print "install:\n";
  print "\tmkdir -p `$(COQC) -where`/user-contrib\n";
  if !some_vfile then print "\tcp -f $(VOFILES) `$(COQC) -where`/user-contrib\n";
  if !some_mlfile then print "\tcp -f *.cmo `$(COQC) -where`/user-contrib\n";
  List.iter
    (fun x -> print "\t(cd "; print x; print " ; $(MAKE) install)\n")
    sds;
  print "\n";
  if !make_name <> "" then begin
    printf "%s: %s\n" !makefile_name !make_name;
    printf "\tmv -f %s %s.bak\n" !makefile_name !makefile_name;
    printf "\t$(COQBIN)coq_makefile -f %s -o %s\n" !make_name !makefile_name;
    print "\n";
    List.iter
      (fun x -> print "\t(cd "; print x; print " ; $(MAKE) Makefile)\n")
      sds;
    print "\n";
  end;
  print "clean:\n";
  print "\trm -f *.cmo *.cmi *.cmx *.o $(VOFILES) $(VIFILES) $(GFILES) *~\n";
  print "\trm -f all.ps all-gal.ps all.glob $(VFILES:.v=.glob) $(HTMLFILES) \
         $(GHTMLFILES) $(VFILES:.v=.tex) $(VFILES:.v=.g.tex) $(VFILES:.v=.v.d)\n";
  if !some_mlfile then
    print "\trm -f $(CMOFILES) $(MLFILES:.ml=.cmi) $(MLFILES:.ml=.ml.d)\n";
  print "\t- rm -rf html\n";
  List.iter
    (fun (file,_,_) -> print "\t- rm -f "; print file; print "\n")
    sps;
  List.iter
    (fun x -> print "\t(cd "; print x; print " ; $(MAKE) clean)\n")
    sds;
  print "\n";
  print "archclean:\n";
  print "\trm -f *.cmx *.o\n";
  List.iter
    (fun x -> print "\t(cd "; print x; print " ; $(MAKE) archclean)\n")
    sds;
  print "\n\n"

let includes () =
  if !some_vfile then print "-include $(VFILES:.v=.v.d)\n.SECONDARY: $(VFILES:.v=.v.d)\n\n";
  if !some_mlfile then print "-include $(MLFILES:.ml=.ml.d)\n.SECONDARY: $(MLFILES:.ml=.ml.d)\n\n"

let implicit () =
  let ml_rules () =
    print "%.cmi: %.mli\n\t$(CAMLC) $(ZDEBUG) $(ZFLAGS) $<\n\n";
    print "%.cmo: %.ml\n\t$(CAMLC) $(ZDEBUG) $(ZFLAGS) $(PP) $<\n\n";
    print "%.cmx: %.ml\n\t$(CAMLOPTC) $(ZDEBUG) $(ZFLAGS) $(PP) $<\n\n";
    print "%.ml.d: %.ml\n";
    print "\t$(CAMLBIN)ocamldep -slash $(ZFLAGS) $(PP) \"$<\" > \"$@\"\n\n"
  and v_rule () =
    print "%.vo %.glob: %.v\n\t$(COQC) -dump-glob $*.glob $(COQDEBUG) $(COQFLAGS) $*\n\n";
    print "%.vi: %.v\n\t$(COQC) -i $(COQDEBUG) $(COQFLAGS) $*\n\n";
    print "%.g: %.v\n\t$(GALLINA) $<\n\n";
    print "%.tex: %.v\n\t$(COQDOC) -latex $< -o $@\n\n";
    print "%.html: %.v %.glob\n\t$(COQDOC) -glob-from $*.glob  -html $< -o $@\n\n";
    print "%.g.tex: %.v\n\t$(COQDOC) -latex -g $< -o $@\n\n";
    print "%.g.html: %.v %.glob\n\t$(COQDOC) -glob-from $*.glob -html -g $< -o $@\n\n";
    print "%.v.d: %.v\n";
    print "\t$(COQDEP) -glob -slash $(COQLIBS) \"$<\" > \"$@\" || ( RV=$$?; rm -f \"$@\"; exit $${RV} )\n\n"
  in
    if !some_mlfile then ml_rules ();
    if !some_vfile then v_rule ()

let variables l =
  let rec var_aux = function
    | [] -> ()
    | Def(v,def) :: r -> print v; print "="; print def; print "\n"; var_aux r
    | _ :: r -> var_aux r
  in
    section "Variables definitions.";
    print "CAMLP4LIB:=$(shell $(CAMLBIN)camlp5 -where 2> /dev/null || $(CAMLBIN)camlp4 -where)\n";
    print "CAMLP4:=$(notdir $(CAMLP4LIB))\n"; 
    if Coq_config.local then
      (print "COQSRC:=$(COQTOP)\n";
       print "COQSRCLIBS:=-I $(COQTOP)/kernel -I $(COQTOP)/lib \\
  -I $(COQTOP)/library -I $(COQTOP)/parsing \\
  -I $(COQTOP)/pretyping -I $(COQTOP)/interp \\
  -I $(COQTOP)/proofs -I $(COQTOP)/tactics \\
  -I $(COQTOP)/toplevel -I $(COQTOP)/contrib/correctness \\
  -I $(COQTOP)/contrib/extraction -I $(COQTOP)/contrib/field \\
  -I $(COQTOP)/contrib/fourier \\
  -I $(COQTOP)/contrib/interface -I $(COQTOP)/contrib/jprover \\
  -I $(COQTOP)/contrib/omega -I $(COQTOP)/contrib/romega \\
  -I $(COQTOP)/contrib/ring -I $(COQTOP)/contrib/xml \\
  -I $(CAMLP4LIB)\n")
    else
      (print "COQSRC:=$(shell $(COQTOP)coqc -where)\n"; 
       print "COQSRCLIBS:=-I $(COQSRC)\n");
    print "ZFLAGS:=$(OCAMLLIBS) $(COQSRCLIBS)\n";
    if !opt = "-byte" then 
      print "override OPT:=-byte\n"
    else
      print "OPT:=\n";
    if !impredicative_set = true then print "OTHERFLAGS=-impredicative-set\n";
    (* Coq executables and relative variables *)
    print "COQFLAGS:=-q $(OPT) $(COQLIBS) $(OTHERFLAGS) $(COQ_XML)\n";
    print "COQC:=$(COQBIN)coqc\n";
    print "COQDEP:=$(COQBIN)coqdep -c\n";
    print "GALLINA:=$(COQBIN)gallina\n";
    print "COQDOC:=$(COQBIN)coqdoc\n";
    (* Caml executables and relative variables *)
    printf "CAMLC:=$(CAMLBIN)ocamlc -rectypes -c\n";
    printf "CAMLOPTC:=$(CAMLBIN)ocamlopt -rectypes -c\n";
    printf "CAMLLINK:=$(CAMLBIN)ocamlc -rectypes\n";
    printf "CAMLOPTLINK:=$(CAMLBIN)ocamlopt -rectypes\n";
    print "GRAMMARS:=grammar.cma\n";
    print "CAMLP4EXTEND:=pa_extend.cmo pa_macro.cmo q_MLast.cmo\n";

    (if Coq_config.local then
      print "PP:=-pp \"$(CAMLBIN)$(CAMLP4)o -I . -I $(COQTOP)/parsing $(CAMLP4EXTEND) $(GRAMMARS) -impl\"\n"
    else
      print "PP:=-pp \"$(CAMLBIN)$(CAMLP4)o -I . -I $(COQSRC) $(CAMLP4EXTEND) $(GRAMMARS) -impl\"\n"); 
    var_aux l;
    print "\n"

let absolute_dir dir =
  let current = Sys.getcwd () in
    Sys.chdir dir;
    let dir' = Sys.getcwd () in
      Sys.chdir current;
      dir'

let is_prefix dir1 dir2 =
  let l1 = String.length dir1 in
  let l2 = String.length dir2 in
    dir1 = dir2 or (l1 < l2 & String.sub dir2 0 l1 = dir1 & dir2.[l1] = '/')

let is_included dir = function
  | RInclude (dir',_) -> is_prefix (absolute_dir dir') (absolute_dir dir)
  | Include dir' -> absolute_dir dir = absolute_dir dir'
  | _ -> false

let dir_of_target t = 
  match t with
    | RInclude (dir,_) -> dir
    | Include dir -> dir
    | _ -> assert false

let include_dirs l =
  let rec split_includes l = 
    match l with
      | [] -> [], []
      | Include _ as i :: rem ->
	  let ri, rr = split_includes rem in 
	    (i :: ri), rr
      | RInclude _ as r :: rem -> 
	  let ri, rr = split_includes rem in 
	    ri, (r :: rr)
      | _ :: rem -> split_includes rem
  in
  let rec parse_includes l = 
    match l with
      | [] -> []
      | Include x :: rem -> ("-I " ^ x) :: parse_includes rem
      | RInclude (p,l) :: rem ->
	  let l' = if l = "" then "\"\"" else l in
            ("-R " ^ p ^ " " ^ l') :: parse_includes rem
      | _ :: rem -> parse_includes rem
  in
  let l' = if List.exists (is_included ".") l then l else Include "." :: l in
  let inc_i, inc_r = split_includes l' in
  let inc_i' = List.filter (fun i -> not (List.exists (fun i' -> is_included (dir_of_target i) i') inc_r)) inc_i in 
  let str_i = parse_includes inc_i in
  let str_i' = parse_includes inc_i' in
  let str_r = parse_includes inc_r in
    section "Libraries definition.";
    print "OCAMLLIBS:="; print_list "\\\n  " str_i; print "\n";
    print "COQLIBS:="; print_list "\\\n  " str_i'; print " "; print_list "\\\n  " str_r; print "\n";
    print "COQDOCLIBS:=";   print_list "\\\n  " str_r; print "\n\n"

let rec special = function
  | [] -> []
  | Special (file,deps,com) :: r -> (file,deps,com) :: (special r)
  | _ :: r -> special r
      
let custom sps =
  let pr_sp (file,dependencies,com) =
    print file; print ": "; print dependencies; print "\n";
    print "\t"; print com; print "\n\n"
  in
    if sps <> [] then section "Custom targets.";
    List.iter pr_sp sps

let subdirs l =
  let rec subdirs_aux = function
    | [] -> []
    | Subdir x :: r -> x :: (subdirs_aux r)
    | _ :: r -> subdirs_aux r
  and pr_subdir s =
    print s; print ":\n\tcd "; print s; print " ; $(MAKE) all\n\n"
  in
  let sds = subdirs_aux l in
    if sds <> [] then section "Subdirectories.";
    List.iter pr_subdir sds;
    section "Special targets.";
    print ".PHONY: ";
    print_list " "
      ("all" ::  "opt" :: "byte" :: "archclean" :: "clean" :: "install" 
	:: "depend" :: "html" :: sds);
    print "\n\n";
    sds


let all_target l =
  let rec parse_arguments l = 
    match l with
      | ML n :: r -> let v,m,o = parse_arguments r in (v,n::m,o)
      | Subdir n :: r -> let v,m,o = parse_arguments r in (v,m,n::o)
      | V n :: r -> let v,m,o = parse_arguments r in (n::v,m,o)
      | Special (n,_,_) :: r -> let v,m,o = parse_arguments r in (v,m,n::o)
      | Include _ :: r -> parse_arguments r
      | RInclude _ :: r -> parse_arguments r
      | Def _ :: r -> parse_arguments r
      | [] -> [],[],[]
  in
  let 
      vfiles, mlfiles, other_targets = parse_arguments l
  in
    section "Definition of the \"all\" target.";
    if !some_vfile then
      begin
	print "VFILES:="; print_list "\\\n  " vfiles; print "\n";
	print "VOFILES:=$(VFILES:.v=.vo)\n";
	print "GLOBFILES:=$(VFILES:.v=.glob)\n";
	print "VIFILES:=$(VFILES:.v=.vi)\n";
	print "GFILES:=$(VFILES:.v=.g)\n";
	print "HTMLFILES:=$(VFILES:.v=.html)\n";
	print "GHTMLFILES:=$(VFILES:.v=.g.html)\n"
      end;
    if !some_mlfile then
      begin
	print "MLFILES:="; print_list "\\\n  " mlfiles; print "\n";
	print "CMOFILES:=$(MLFILES:.ml=.cmo)\n";
      end;
    print "\nall: ";
    if !some_vfile then print "$(VOFILES) ";
    if !some_mlfile then print "$(CMOFILES) ";
    print_list "\\\n  " other_targets; print "\n";
    if !some_vfile then 
      begin
	print "spec: $(VIFILES)\n\n";
	print "gallina: $(GFILES)\n\n";
	print "html: $(GLOBFILES) $(VFILES)\n";
	print "\t- mkdir html\n"; 
	print "\t$(COQDOC) -toc -html $(COQDOCLIBS) -d html $(VFILES)\n\n";
	print "gallinahtml: $(GLOBFILES) $(VFILES)\n";
	print "\t- mkdir html\n"; 
	print "\t$(COQDOC) -toc -html -g $(COQDOCLIBS) -d html $(VFILES)\n\n";
	print "all.ps: $(VFILES)\n";
	print "\t$(COQDOC) -toc -ps $(COQDOCLIBS) -o $@ `$(COQDEP) -sort -suffix .v $(VFILES)`\n\n";
	print "all-gal.ps: $(VFILES)\n";
	print "\t$(COQDOC) -toc -ps -g $(COQDOCLIBS) -o $@ `$(COQDEP) -sort -suffix .v $(VFILES)`\n\n";
	print "\n\n"
      end
      
let parse f =
  let rec string = parser 
    | [< '' ' | '\n' | '\t' >] -> ""
    | [< 'c; s >] -> (String.make 1 c)^(string s)
    | [< >] -> ""
  and string2 = parser 
    | [< ''"' >] -> ""
    | [< 'c; s >] -> (String.make 1 c)^(string2 s)
  and skip_comment = parser 
    | [< ''\n'; s >] -> s
    | [< 'c; s >] -> skip_comment s
    | [< >] -> [< >]
  and args = parser 
    | [< '' ' | '\n' | '\t'; s >] -> args s
    | [< ''#'; s >] -> args (skip_comment s)
    | [< ''"'; str = string2; s >] -> ("" ^ str) :: args s
    | [< 'c; str = string; s >] -> ((String.make 1 c) ^ str) :: (args s)
    | [< >] -> []
  in
  let c = open_in f in
  let res = args (Stream.of_channel c) in
    close_in c;
    res

let rec process_cmd_line = function
  | [] -> 
      some_file := !some_file or !some_mlfile or !some_vfile; []
  | ("-h"|"--help") :: _ -> 
      usage ()
  | ("-no-opt"|"-byte") :: r -> 
      opt := "-byte"; process_cmd_line r
  | ("-full"|"-opt") :: r -> 
      opt := "-opt"; process_cmd_line r
  | "-impredicative-set" :: r ->
      impredicative_set := true; process_cmd_line r
  | "-custom" :: com :: dependencies :: file :: r ->
      let check_dep f =
	if Filename.check_suffix f ".v" then
          some_vfile := true
	else if Filename.check_suffix f ".ml" then
          some_mlfile := true
	else
	  () 
      in
	List.iter check_dep (Str.split (Str.regexp "[ \t]+") dependencies);
	Special (file,dependencies,com) :: (process_cmd_line r)
  | "-I" :: d :: r ->
      Include d :: (process_cmd_line r)
  | "-R" :: p :: l :: r ->
      RInclude (p,l) :: (process_cmd_line r)
  | ("-I"|"-custom") :: _ -> 
      usage ()
  | "-f" :: file :: r -> 
      make_name := file;
      process_cmd_line ((parse file)@r)
  | ["-f"] -> 
      usage ()
  | "-o" :: file :: r -> 
      makefile_name := file;
      output_channel := (open_out file);
      (process_cmd_line r)
  | v :: "=" :: def :: r -> 
      Def (v,def) :: (process_cmd_line r)
  | f :: r ->
      if Filename.check_suffix f ".v" then begin
          some_vfile := true; 
	  V f :: (process_cmd_line r)
	end else if Filename.check_suffix f ".ml" then begin
            some_mlfile := true; 
	    ML f :: (process_cmd_line r)
      end else
            Subdir f :: (process_cmd_line r)
	      
let banner () =
  print
"##########################################################################
##  v      #                  The Coq Proof Assistant                   ##
## <O___,, # CNRS-Ecole Polytechnique-INRIA Futurs-Universite Paris Sud ##
##   \\VV/  #                                                            ##
##    //   #   Makefile automagically generated by coq_makefile V8.2    ##
##########################################################################

"

let warning () =
  print "# WARNING\n#\n";
  print "# This Makefile has been automagically generated\n";
  print "# Edit at your own risks !\n";
  print "#\n# END OF WARNING\n\n"
    
let print_list l = List.iter (fun x -> print x; print " ") l
  
let command_line args =
  print "#\n# This Makefile was generated by the command line :\n";
  print "# coq_makefile ";
  print_list args;
  print "\n#\n\n"
    
let directories_deps l =
  let print_dep f dep = 
    if dep <> [] then begin print f; print ": "; print_list dep; print "\n" end
  in
  let rec iter ((dirs,before) as acc) = function
    | [] -> 
	()
    | (Subdir d) :: l -> 
	print_dep d before; iter (d :: dirs, d :: before) l
    | (ML f) :: l ->
	print_dep f dirs; iter (dirs, f :: before) l
    | (V f) :: l ->
	print_dep f dirs; iter (dirs, f :: before) l
    | (Special (f,_,_)) :: l ->
	print_dep f dirs; iter (dirs, f :: before) l
    | _ :: l -> 
	iter acc l
  in
    iter ([],[]) l

let do_makefile args =
  let l = process_cmd_line args in
    banner ();
    warning ();
    command_line args;
    include_dirs l;
    variables l;
    all_target l;
    let sps = special  l in
      custom sps;
      let sds = subdirs l in
	implicit ();
	standard sds sps;
	(* TEST directories_deps l; *)
	includes ();
	warning ();
	if not (!output_channel == stdout) then close_out !output_channel;
	exit 0
	  
let main () =
  let args =
    if Array.length Sys.argv = 1 then usage ();
    List.tl (Array.to_list Sys.argv)
  in
    do_makefile args
      
let _ = Printexc.catch main ()

