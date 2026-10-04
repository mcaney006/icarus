module Icarus.Codes

import Language.Reflection
import public Icarus.Types

%default total
%language ElabReflection

var : Name -> TTImp
var = IVar EmptyFC

natural : Nat -> TTImp
natural Z = `(Z)
natural (S k) = `(S ~(natural k))

claim : Name -> TTImp -> Decl
claim name type = IClaim (NoFC (MkIClaimData MW Public [Totality Total] (MkTy EmptyFC (NoFC name) type)))

enumeration : Name -> (encode, decode : String) -> Elab ()
enumeration type encode decode = do
  [(resolved, MkNameInfo (TyCon _ _))] <- getInfo type
    | _ => fail "\{show type} does not name a unique type constructor"
  constructors <- getCons resolved
  let encoder = UN (Basic encode)
      decoder = UN (Basic decode)
      indexed = zip [0 .. length constructors] constructors
  declare
    [ claim encoder `(~(var resolved) -> Nat)
    , IDef EmptyFC encoder [PatClause EmptyFC `(~(var encoder) ~(var c)) (natural i) | (i, c) <- indexed]
    , claim decoder `(Nat -> Maybe ~(var resolved))
    , IDef EmptyFC decoder $
        [PatClause EmptyFC `(~(var decoder) ~(natural i)) `(Just ~(var c)) | (i, c) <- indexed]
        ++ [PatClause EmptyFC `(~(var decoder) _) `(Nothing)]
    ]

%runElab enumeration `{Icarus.Types.Mode} "modeCode" "modeOfCode"
%runElab enumeration `{Icarus.Types.Health.Health} "healthCode" "healthOfCode"
%runElab enumeration `{Icarus.Types.FaultKind} "faultCode" "faultOfCode"

public export
Eq Icarus.Types.Mode where
  a == b = modeCode a == modeCode b

public export
Eq Icarus.Types.Health.Health where
  a == b = healthCode a == healthCode b

public export
Eq Icarus.Types.FaultKind where
  a == b = faultCode a == faultCode b
