(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(* $Id$ *)

(* Parsing of vernacular. *)

open Pp
open Lexer
open Util
open Options
open System
open Coqast
open Vernacexpr
open Vernacinterp
open Ppvernacnew

(* The functions in this module may raise (unexplainable!) exceptions.
   Use the module Coqtoplevel, which catches these exceptions
   (the exceptions are explained only at the toplevel). *)

exception DuringCommandInterp of Util.loc * exn

(* Specifies which file is read. The intermediate file names are
   discarded here. The Drop exception becomes an error. We forget
   if the error ocurred during interpretation or not *)

let raise_with_file file exc =
  let (cmdloc,re) =
    match exc with
      | DuringCommandInterp(loc,e) -> (loc,e)
      | e -> (dummy_loc,e) 
  in
  let (inner,inex) =
    match re with
      | Error_in_file (_, (b,f,loc), e) when loc <> dummy_loc ->
          ((b, f, loc), e)
      | Stdpp.Exc_located (loc, e) when loc <> dummy_loc ->
          ((false,file, loc), e)
      | _ -> ((false,file,cmdloc), re)
  in 
  raise (Error_in_file (file, inner, disable_drop inex))

let real_error = function
  | Stdpp.Exc_located (_, e) -> e
  | Error_in_file (_, _, e) -> e
  | e -> e

(* Opening and closing a channel. Open it twice when verbose: the first
   channel is used to read the commands, and the second one to print them.
   Note: we could use only one thanks to seek_in, but seeking on and on in
   the file we parse seems a bit risky to me.  B.B.  *)

let open_file_twice_if verbosely fname =
  let _,longfname = find_file_in_path (Library.get_load_path ()) fname in
  let in_chan = open_in longfname in
  let verb_ch = if verbosely then Some (open_in longfname) else None in
  let po = Pcoq.Gram.parsable (Stream.of_channel in_chan) in
  (in_chan, longfname, (po, verb_ch))

let close_input in_chan (_,verb) =
  try 
    close_in in_chan;
    match verb with
      | Some verb_ch -> close_in verb_ch
      | _ -> ()
  with _ -> ()

let verbose_phrase verbch loc =
  match verbch with
    | Some ch ->
	let len = snd loc - fst loc in
	let s = String.create len in
        seek_in ch (fst loc);
        really_input ch s 0 len;
        message s;
        pp_flush()
    | _ -> ()

exception End_of_input
  
let parse_phrase (po, verbch) =
  match Pcoq.Gram.Entry.parse Pcoq.main_entry po with
    | Some (loc,_ as com) -> verbose_phrase verbch loc; com
    | None -> raise End_of_input

(* vernac parses the given stream, executes interpfun on the syntax tree it
 * parses, and is verbose on "primitives" commands if verbosely is true *)

let just_parsing = ref false
let chan_translate = ref stdout
let last_char = ref '\000'

(* postprocessor to avoid lexical icompatibilities between V7 and V8.
   Ex: auto.(* comment *)  or  simpl.auto
 *)
let set_formatter_translator() =
  let ch = !chan_translate in
  let out s b e =
    let n = e-b in
    if n > 0 then begin
      (match !last_char with
          '.' -> 
            (match s.[b] with
                '('|'a'..'z'|'A'..'Z' -> output ch " " 0 1 
              | _ -> ())
        | _ -> ());
      last_char := s.[e-1]
    end;
    output ch s b e
  in
  Format.set_formatter_output_functions out (fun () -> flush ch);
  Format.set_max_boxes max_int

let pre_printing = function
  | VernacSolve (i,tac,deftac) when Options.do_translate () ->
      (try
        let (_,env) = Pfedit.get_goal_context i in
        let t = Options.with_option Options.translate_syntax
	  (Tacinterp.glob_tactic_env [] env) tac in
        let pfts = Pfedit.get_pftreestate () in
        let gls = fst (Refiner.frontier (Tacmach.proof_of_pftreestate pfts)) in
        Some (env,t,Pfedit.focus(),List.length gls)
      with UserError _|Stdpp.Exc_located _ -> None)
  | _ -> None

let post_printing loc (env,t,f,n) = function
  | VernacSolve (i,_,deftac) ->
      set_formatter_translator();
      let pp = Ppvernacnew.pr_vernac_solve (i,env,t,deftac) ++ sep_end () in
      (if !translate_file then begin
	msg (hov 0 (comment (fst loc) ++ pp ++ comment (snd loc - 1)));
      end
      else
	msgnl (hov 4 (str"New Syntax:" ++ fnl() ++ pp)));
      Format.set_formatter_out_channel stdout
  | _ -> ()

let pr_new_syntax loc ocom =
  if !translate_file then set_formatter_translator();
  let fs = States.freeze () in
  let com = match ocom with
    | Some (VernacV7only _) ->
        Options.v7_only := true;
        mt()
    | Some VernacNop -> mt()
    | Some com -> pr_vernac com
    | None -> mt() in
  if !translate_file then
    msg (hov 0 (comment (fst loc) ++ com ++ comment (snd loc)))
  else
    msgnl (hov 4 (str"New Syntax:" ++ fnl() ++ (hov 0 com)));
  States.unfreeze fs;
  Constrintern.set_temporary_implicits_in [];
  Constrextern.set_temporary_implicits_out [];
  Format.set_formatter_out_channel stdout

let rec vernac_com interpfun (loc,com) =
  let rec interp = function
    | VernacLoad (verbosely, fname) ->
        let ch = !chan_translate in
        let cs = Lexer.com_state() in
        let lt = Lexer.location_table() in
        let cl = !Pp.comments in
        if !Options.translate_file then begin
          let _,f = find_file_in_path (Library.get_load_path ())
            (make_suffix fname ".v") in
          chan_translate := open_out (f^"8");
          Pp.comments := []
        end;
        begin try
          read_vernac_file verbosely (make_suffix fname ".v");
          if !Options.translate_file then close_out !chan_translate;
          chan_translate := ch;
          Lexer.restore_com_state cs;
          Lexer.restore_location_table lt;
          Pp.comments := cl
        with e ->
          if !Options.translate_file then close_out !chan_translate;
          chan_translate := ch;
          Lexer.restore_com_state cs;
          Lexer.restore_location_table lt;
          Pp.comments := cl;
          raise e end;

    | VernacList l -> List.iter (fun (_,v) -> interp v) l

    | VernacTime v ->
	let tstart = System.get_time() in
        if not !just_parsing then interpfun v;
	let tend = System.get_time() in
        msgnl (str"Finished transaction in " ++
                 System.fmt_time_difference tstart tend)

    (* To be interpreted in v7 or translator input only *)
    | VernacV7only v ->
        Options.v7_only := true;
        if !Options.v7 || Options.do_translate() then interp v;
        Options.v7_only := false

    (* To be interpreted in translator output only *)
    | VernacV8only v -> 
        if not !Options.v7 && not (do_translate()) then
          interp v

    | v -> if not !just_parsing then interpfun v

  in 
  try
    Options.v7_only := false;
    if do_translate () then
      match pre_printing com with
          None ->
            pr_new_syntax loc (Some com);
            interp com
        | Some state ->
            (try
              interp com;
              post_printing loc state com
            with e ->
              post_printing loc state com;
              raise e)
    else
      interp com
  with e -> 
    Format.set_formatter_out_channel stdout;
    Options.v7_only := false;
    raise (DuringCommandInterp (loc, e))

and vernac interpfun input =
  vernac_com interpfun (parse_phrase input)

and read_vernac_file verbosely s =
  let interpfun =
    if verbosely then 
      Vernacentries.interp
    else 
      Options.silently Vernacentries.interp 
  in
  let (in_chan, fname, input) = open_file_twice_if verbosely s in
  try
    (* we go out of the following infinite loop when a End_of_input is
     * raised, which means that we raised the end of the file being loaded *)
    while true do vernac interpfun input; pp_flush () done
  with e ->   (* whatever the exception *)
    Format.set_formatter_out_channel stdout;
    close_input in_chan input;    (* we must close the file first *)
    match real_error e with
      | End_of_input ->
          if do_translate () then pr_new_syntax (max_int,max_int) None
      | _ -> raise_with_file fname e

(* raw_do_vernac : char Stream.t -> unit
 * parses and executes one command of the vernacular char stream.
 * Marks the end of the command in the lib_stk to make vernac undoing
 * easier. *)

let raw_do_vernac po =
  vernac (States.with_heavy_rollback Vernacentries.interp) (po,None);
  Lib.mark_end_of_command()

(* Load a vernac file. Errors are annotated with file and location *)
let load_vernac verb file =
  chan_translate :=
    if !Options.translate_file then open_out (file^"8") else stdout;
  try 
    read_vernac_file verb file;
    if !Options.translate_file then close_out !chan_translate;
  with e -> 
    if !Options.translate_file then close_out !chan_translate;
    raise_with_file file e

(* Compile a vernac file (f is assumed without .v suffix) *)
let compile verbosely f =
(*
    let s = Filename.basename f in
    let m = Names.id_of_string s in
    let _,longf = find_file_in_path (Library.get_load_path ()) (f^".v") in
    let ldir0 = Library.find_logical_path (Filename.dirname longf) in
    let ldir = Libnames.extend_dirpath ldir0 m in
    Termops.set_module ldir; (* Just for universe naming *)
    Lib.start_module ldir;
    if !dump then dump_string ("F" ^ Names.string_of_dirpath ldir ^ "\n");
    let _ = load_vernac verbosely longf in
    let mid = Lib.end_module m in
    assert (mid = ldir);
    Library.save_module_to ldir (longf^"o")
*)
  let ldir,long_f_dot_v = Library.start_library f in
  if !dump then dump_string ("F" ^ Names.string_of_dirpath ldir ^ "\n");
  let _ = load_vernac verbosely long_f_dot_v in
  if Pfedit.get_all_proof_names () <> [] then
    (message "Error: There are pending proofs"; exit 1);
  Library.save_library_to ldir (long_f_dot_v ^ "o")
