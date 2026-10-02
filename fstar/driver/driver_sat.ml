let () =
  match Sys.argv with
  | [| _; path |] ->
    let content = In_channel.with_open_bin path In_channel.input_all in
    exit (Z.to_int (Icarus_SatCheck.run content))
  | _ -> prerr_string "usage: icarus_sat <ops file>\n"; exit 2
