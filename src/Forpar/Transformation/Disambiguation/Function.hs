{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE PatternGuards #-}

module Forpar.Transformation.Disambiguation.Function (disambiguateFunction) where

import Prelude hiding (lookup)
import Data.Generics.Uniplate.Data
import Data.Map ((!), lookup, Map)
import Data.Maybe (isJust, fromJust)
import Data.Data

import Forpar.Analysis.Types (IDType(..), ConstructType(..), TypeScope(..))
import Forpar.AST
import Forpar.Transformation.TransformMonad

import Debug.Trace

disambiguateFunction :: Data a => Transform a ()
disambiguateFunction = do
  disambiguateFunctionStatements
  disambiguateFunctionCalls

disambiguateFunctionStatements :: forall a . Data a => Transform a ()
disambiguateFunctionStatements = do
  pf <- getProgramFile
  mapping <- getTypes
  putProgramFile $ descendBi (transform' mapping) pf
  where
    transform' :: Data a => Map TypeScope (Map String IDType) -> ProgramUnit a -> ProgramUnit a
    transform' mapping pu =
      descendBi (transform'' (Local (getName pu) `lookup` mapping)) pu
    transform'' :: Data a => Maybe (Map String IDType) -> Statement a -> Statement a
    transform''
      mInnerMapping
      st@(StExpressionAssign a1 s
        (ExpSubscript _ _
          (ExpValue a3 s'' (ValVariable _ n)) indicies)
        e2)
      | Just innerMapping <- mInnerMapping
      , Just (IDType _ (Just CTFunction)) <- n `lookup` innerMapping =
          StFunction a1 s
            (ExpValue a3 s'' (ValFunctionName n))
            (aMap fromIndex indicies)
            e2
      | otherwise = st
    transform'' _ (x :: Statement a) = x

disambiguateFunctionCalls :: forall a . Data a => Transform a ()
disambiguateFunctionCalls = do
  pf <- getProgramFile
  mapping <- getTypes
  putProgramFile $ descendBi (transform' mapping) pf
  where
    transform' :: Data a => Map TypeScope (Map String IDType) -> ProgramUnit a -> ProgramUnit a
    transform' mapping pu =
      descendBi (transform'' (Global `lookup` mapping) (Local (getName pu) `lookup` mapping)) pu
    transform'' :: Data a => Maybe (Map String IDType) -> Maybe (Map String IDType) -> Expression a -> Expression a
    transform''
        mGlobalMapping
        mInnerMapping
        exp@(ExpSubscript a1 s (ExpValue a2 s' (ValVariable a3 n)) l)
      | Just innerMapping <- mInnerMapping
      , Just (IDType _ (Just CTFunction)) <- n `lookup` innerMapping
      = ExpFunctionCall a1 s
                        (ExpValue a2 s' (ValFunctionName n))
                        (aMap fromIndex l)
      | Just globalMapping <- mGlobalMapping
      , Just (IDType _ (Just CTFunction)) <- n `lookup` globalMapping
      = ExpFunctionCall a1 s
                        (ExpValue a2 s' (ValFunctionName n))
                        (aMap fromIndex l)
      | otherwise = exp
    transform'' mGlobalMapping mLocalMapping x =
      descend (transform'' mGlobalMapping mLocalMapping) x

fromIndex (IxSingle _ _ e) = e
fromIndex IxRange{} =
  error "Deduced a function but argument is not an expression."

