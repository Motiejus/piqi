(*pp camlp4o -I `ocamlfind query piqi.syntax` pa_labelscope.cmo pa_openin.cmo *)
(*
   Copyright 2009, 2010, 2011, 2012 Anton Lavrik

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*)


(*
 * This module generates default values for all Erlang types generated by
 * Piqic_erlang_types
 *)

open Piqi_common
open Iolist


(* reuse several functions *)
open Piqic_erlang_types
open Piqic_erlang_out


let gen_default_type erlang_type wire_type x =
  match x with
    | `any ->
        if !Piqic_common.is_self_spec
        then ios "default_" ^^ ios !any_erlname ^^ ios "()"
        else ios "piqi_piqi:default_any()"
    | (#T.typedef as x) ->
        let modname = gen_parent x in
        modname ^^ ios "default_" ^^ ios (typedef_erlname x) ^^ ios "()"
    | _ -> (* gen parsers for built-in types *)
        let default = Piqic_common.gen_builtin_default_value wire_type x in
        let default_expr = Piqic_erlang_in.gen_erlang_binary default in
        iol [
          ios "piqirun:";
          ios (gen_erlang_type_name x erlang_type);
          ios "_of_";
          ios (W.get_wire_type_name x wire_type);
          ios "("; default_expr; ios ")";
        ]


let gen_default_piqtype ?erlang_type ?wire_type (t: T.piqtype) =
  gen_default_type erlang_type wire_type t


let gen_field_cons f =
  let open Field in
  let value =
    match f.mode with
      | `required -> gen_default_piqtype (some_of f.typeref)
      | `optional when f.typeref = None -> ios "false" (* flag *)
      (* XXX: generate default value? (see piqic_ocaml_defaults.ml)
      | `optional when f.default <> None ->
      *)
      (* XXX: don't generate such field as it will be set to 'undefined' by
       * default? *)
      | `optional -> ios "'undefined'"
      | `repeated -> ios "[]"
  in
  (* field construction code *)
  iol [ ios (erlname_of_field f); ios " = "; value; ] 


let gen_record r =
  (* fully-qualified capitalized record name *)
  let rname = some_of r.R#erlang_name in
  let fields = r.R#wire_field in
  let fconsl = (* field constructor list *)
    List.map gen_field_cons fields
  in (* default_<record-name> function delcaration *)
  iol [
    ios "default_"; ios rname; ios "() ->"; indent;
      ios "#"; ios (scoped_name rname); ios "{"; indent;
        iod ",\n        " fconsl;
        unindent; eol;
      ios "}.";
      unindent;
  ]


let gen_enum e =
  let open Enum in
  (* there must be at least one option *)
  let const = List.hd e.option in
  iol [
    ios "default_"; ios (some_of e.erlang_name); ios "() ->";
    ios (some_of const.O#erlang_name);
    ios "."
  ]


let rec gen_option varname o =
  let open Option in
  match o.erlang_name, o.typeref with
    | Some n, None ->
        ios n
    | None, Some ((`variant _) as t) | None, Some ((`enum _) as t) ->
        gen_default_piqtype t
    | _, Some t ->
        let n = erlname_of_option o in
        iol [
          ios "{"; ios n; ios ", "; gen_default_piqtype t; ios "}";
        ]
    | None, None -> assert false


let gen_variant v =
  let open Variant in
  (* there must be at least one option *)
  let opt = gen_option (some_of v.erlang_name) (List.hd v.option) in
  iol [
    ios "default_"; ios (some_of v.erlang_name); ios "() -> "; opt; ios "."
  ]


let gen_alias a =
  let open Alias in
  iol [
    ios "default_"; ios (some_of a.erlang_name); ios "() -> ";
    Piqic_erlang_in.gen_convert_of a.typeref a.erlang_type (
      gen_default_piqtype
        (some_of a.typeref) ?erlang_type:a.erlang_type ?wire_type:a.wire_type;
    );
    ios ".";
  ]


let gen_list l =
  let open L in
  iol [
    ios "default_"; ios (some_of l.erlang_name); ios "() -> [].";
  ]


let gen_def = function
  | `record t -> gen_record t
  | `variant t -> gen_variant t
  | `enum t -> gen_enum t
  | `list t -> gen_list t
  | `alias t -> gen_alias t


let gen_defs (defs:T.typedef list) =
  let defs = List.map gen_def defs in
  if defs = []
  then iol []
  else iol
    [
      iod "\n\n" defs;
      ios "\n";
    ]


let gen_piqi (piqi:T.piqi) =
  gen_defs piqi.P#resolved_typedef
