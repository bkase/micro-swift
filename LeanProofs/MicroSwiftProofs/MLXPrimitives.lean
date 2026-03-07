import Mathlib.Data.List.Basic

/-!
# MLX Primitives

Translation layer mapping MLX operations to standard Lean/Mathlib functions.
These definitions let us state and prove theorems about vectorized MLX code
using Mathlib's existing library of list/array lemmas.
-/

namespace MLX

/-- `cummin(reverse: true)` — reverse cumulative minimum via `scanr`. -/
def cumminRev (xs : List Nat) (sentinel : Nat) : List Nat :=
  xs.scanr min sentinel

/-- `cummin(reverse: false)` — forward cumulative minimum via `scanl`. -/
def cumminFwd (xs : List Nat) (sentinel : Nat) : List Nat :=
  xs.scanl min sentinel

/-- MLX `take` along axis — modeled as list indexing / map over indices. -/
def take {α : Type} (xs : List α) (indices : List Nat) : List α :=
  indices.filterMap (xs[·]?)

/-- MLX `concatenated` — just list append. -/
def concatenated {α : Type} (a b : List α) : List α :=
  a ++ b

/-- Shift-left by `n`, padding with `padVal` on the right. -/
def shiftLeft {α : Type} (xs : List α) (n : Nat) (padVal : α) : List α :=
  (xs.drop n) ++ (List.replicate n padVal)

/-- Shift-right by `n`, padding with `padVal` on the left. -/
def shiftRight {α : Type} (xs : List α) (n : Nat) (padVal : α) : List α :=
  (List.replicate n padVal) ++ (xs.take (xs.length - n))

/-! ## Conditional Selection -/

/-- MLX `which` — ternary selection based on a boolean mask. -/
def which {α : Type} (mask : List Bool) (tVals fVals : List α) : List α :=
  List.zip mask (List.zip tVals fVals) |>.map fun ⟨m, ⟨t, f⟩⟩ =>
    if m then t else f

/-! ## Array Generators -/

/-- MLX `arange` — generates [0, 1, ..., n-1]. -/
def arange (n : Nat) : List Nat :=
  List.range n

/-- MLX `zeros` — generates an array of size `n` filled with a default zero-like value. -/
def zeros {α : Type} [Inhabited α] (n : Nat) : List α :=
  List.replicate n default

/-- MLX `full` / `filled` — generates an array of size `n` filled with a specific value. -/
def full {α : Type} (n : Nat) (val : α) : List α :=
  List.replicate n val

/-! ## Element-wise Logical & Relational Operators -/

/-- MLX `.&&` — element-wise logical AND. -/
def elemAnd (a b : List Bool) : List Bool :=
  List.zipWith and a b

/-- MLX `.||` — element-wise logical OR. -/
def elemOr (a b : List Bool) : List Bool :=
  List.zipWith or a b

/-- MLX `.!` — element-wise logical NOT. -/
def elemNot (a : List Bool) : List Bool :=
  a.map not

/-- MLX `.==` — element-wise equality. -/
def elemEq {α : Type} [DecidableEq α] (a b : List α) : List Bool :=
  List.zipWith (· == ·) a b

/-- MLX `.>` — element-wise greater than. -/
def elemGt (a b : List Nat) : List Bool :=
  List.zipWith (· > ·) a b

/-- MLX `.<` — element-wise less than. -/
def elemLt (a b : List Nat) : List Bool :=
  List.zipWith (· < ·) a b

/-- MLX `.+` — element-wise addition. -/
def elemAdd (a b : List Nat) : List Nat :=
  List.zipWith (· + ·) a b

/-- MLX `.-` — element-wise saturating subtraction. -/
def elemSub (a b : List Nat) : List Nat :=
  List.zipWith (· - ·) a b

/-- MLX `.>=` — element-wise greater-or-equal. -/
def elemGe (a b : List Nat) : List Bool :=
  List.zipWith (fun x y => decide (x ≥ y)) a b

/-- Element-wise minimum. -/
def elemMin (a b : List Nat) : List Nat :=
  List.zipWith min a b

/-! ## Reductions & Scans -/

/-- MLX `cummax` — forward cumulative maximum. Crucial for GreedySelector. -/
def cummaxFwd (xs : List Nat) (init : Nat := 0) : List Nat :=
  (xs.scanl max init).drop 1

/-- MLX `sum` — scalar sum of an array. -/
def sum (xs : List Nat) : Nat :=
  xs.foldl (· + ·) 0

/-- MLX `any` — scalar boolean reduction; true if any element is true. -/
def any (xs : List Bool) : Bool :=
  xs.any (· == true)

end MLX
