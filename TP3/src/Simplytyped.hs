module Simplytyped
  ( conversion
  ,    -- conversion a terminos localmente sin nombre
    eval
  ,          -- evaluador
    infer
  ,         -- inferidor de tipos
    quote          -- valores -> terminos
  )
where

import           Data.List
import           Data.Maybe
import           Prelude                 hiding ( (>>=) )
import           Text.PrettyPrint.HughesPJ      ( render )
import           PrettyPrinter
import           Common

-- conversion a términos localmente sin nombres
conversion :: LamTerm -> Term
conversion = conversion' []

conversion' :: [String] -> LamTerm -> Term
conversion' b (LVar n    ) = maybe (Free (Global n)) Bound (n `elemIndex` b)
conversion' b (LApp t u  ) = conversion' b t :@: conversion' b u
conversion' b (LAbs n t u) = Lam t (conversion' (n : b) u)
conversion' b (LLet n l1 l2) =
                                let a1 = (conversion' b l1)
                                    a2 = (conversion' (n:b) l2)
                                in Let a1 a2
conversion' b (LUnit) = Unit
conversion' b (LPair t1 t2) = Pair (conversion' b t1) (conversion' b t2)
conversion' b (LFst t) = Fst (conversion' b t)
conversion' b (LSnd t) = Snd (conversion' b t)
conversion' b (LZero)  = Zero
conversion' b (LSuc t) = Suc (conversion' b t)
conversion' b (LRec t1 t2 t3) = Rec (conversion' b t1) (conversion' b t2) (conversion' b t3)

-----------------------
--- eval
-----------------------

-- 
sub :: Int -> Term -> Term -> Term
sub i t (Bound j) | i == j    = t
sub _ _ (Bound j) | otherwise = Bound j
sub _ _ (Free n   )           = Free n
sub i t (u   :@: v)           = sub i t u :@: sub i t v
sub i t (Lam t'  u)           = Lam t' (sub (i + 1) t u)
sub i t (Let t1 t2)           = Let (sub i t t1) (sub (i + 1) t t2)
sub i t (Fst t')              = Fst (sub i t t')
sub i t (Snd t')              = Snd (sub i t t')
sub i t (Pair t1 t2)          = Pair (sub i t t1) (sub i t t2)
sub i t (Zero)                = Zero
sub i t (Suc t')              = Suc (sub i t t')
sub i t (Rec t1 t2 t3)        = Rec (sub i t t1) (sub i t t2) (sub i t t3)

-- evaluador de términos
eval :: NameEnv Value Type -> Term -> Value
eval _ (Bound _             ) = error "variable ligada inesperada en eval"
eval e (Free  n             ) = fst $ fromJust $ lookup n e
eval _ (Lam      t   u      ) = VLam t u
eval e (Lam _ u  :@: Lam s v) = eval e (sub 0 (Lam s v) u)
eval e (Lam t u1 :@: u2) = let v2 = eval e u2 in eval e (sub 0 (quote v2) u1)
eval e (Let t1 t2) = let v2 = eval e t1 in eval e (sub 0 (quote v2) t2)
eval e (Unit) = VUnit
eval e (Zero) = VNum NZero
eval e (Suc t) = VNum NZero
eval e (Pair t1 t2) = VPair (eval e t1) (eval e t2)
eval e (Fst t) = case (eval e t) of
          (VPair t1 t2) -> t1
          _ -> error "Error de tipo en run-time, verificar type checker"
eval e (Snd t) = case (eval e t) of
          (VPair t1 t2) -> t2
          _ -> error "Error de tipo en run-time, verificar type checker"
eval e (u        :@: v      ) = case eval e u of
  VLam t u' -> eval e (Lam t u' :@: v)
  _         -> error "Error de tipo en run-time, verificar type checker"




-----------------------
--- quoting
-----------------------

quote :: Value -> Term
quote (VLam t f) = Lam t f
quote (VUnit) = Unit
quote (VPair t1 t2) = Pair (quote t1) (quote t2)

----------------------
--- type checker
-----------------------

-- type checker
infer :: NameEnv Value Type -> Term -> Either String Type
infer = infer' []

-- definiciones auxiliares
ret :: Type -> Either String Type
ret = Right

err :: String -> Either String Type
err = Left

(>>=)
  :: Either String Type -> (Type -> Either String Type) -> Either String Type
(>>=) v f = either Left f v
-- fcs. de error

matchError :: Type -> Type -> Either String Type
matchError t1 t2 =
  err
    $  "se esperaba "
    ++ render (printType t1)
    ++ ", pero "
    ++ render (printType t2)
    ++ " fue inferido."

notfunError :: Type -> Either String Type
notfunError t1 = err $ render (printType t1) ++ " no puede ser aplicado."

notfoundError :: Name -> Either String Type
notfoundError n = err $ show n ++ " no está definida."

notpairError :: Type -> Either String Type
notpairError t1 = err $ render (printType t1) ++ " no es un par."

infer' :: Context -> NameEnv Value Type -> Term -> Either String Type
infer' c _ (Bound i) = ret (c !! i)
infer' _ e (Free  n) = case lookup n e of
  Nothing     -> notfoundError n
  Just (_, t) -> ret t
infer' c e (t :@: u) = infer' c e t >>= \tt -> infer' c e u >>= \tu ->
  case tt of
    FunT t1 t2 -> if (tu == t1) then ret t2 else matchError t1 tu
    _          -> notfunError tt
infer' c e (Lam t u) = infer' (t : c) e u >>= \tu -> ret $ FunT t tu
infer' c e (Let t1 t2) = infer' c e t1 >>= \tt -> infer' (tt : c) e t2 >>= \tu -> ret tu
infer' c e (Unit) = ret UnitT
infer' c e (Pair t1 t2) = infer' c e t1 >>= \tt1 -> infer' c e t2 >>= \tt2 -> ret $ PairT tt1 tt2
infer' c e (Fst t) = infer' c e t >>= \tt -> 
  case tt of
    PairT t1 t2 -> ret t1
    _           -> notpairError tt
infer' c e (Snd t) = infer' c e t >>= \tt -> 
  case tt of
    PairT t1 t2 -> ret t1
    _           -> notpairError tt
infer' c e (Pair t1 t2) = infer' c e t1 >>= \tt1 -> infer' c e t2 >>= \tt2 -> ret $ PairT tt1 tt2
  --case tt of
  --  FunT t1 t2 -> if (tu == t1) then ret t2 else matchError t1 tu
  --  _          -> notfunError tt

----------------------------------
