{-# OPTIONS -cpp -pgmPcpphs -optP--cpp #-}
{-# LANGUAGE OverloadedStrings #-}
 
module Compile
  ( compile
  ) where

import Error
import Program
import Term

import Data.List
import Text ((+++))
import qualified Text as Text

data Context = Context
  { quotation   :: Bool
  , definitions :: [Text.Text]
  }

quoted :: Context -> Context
quoted e = e { quotation = True }

defining :: Context -> Text.Text -> Context
e `defining` s = e { definitions = definitions e ++ [s] }

#include "builtins.h"
#define INIT(NAME) #NAME,
#define LAST(NAME) #NAME
builtins :: [Text.Text]
builtins = [ KITTEN_BUILTINS(INIT, LAST) ]
#undef LAST
#undef INIT

emptyContext :: Context
emptyContext = Context False []

compile :: Program -> ErrorMonad Text.Text
compile (Program terms) = do
  result <- compileWith emptyContext terms
  return $ Text.concat 
    [ "#include <kitten.h>\nKITTEN_PROGRAM("
    , Text.unwords result
    , ")"
    ]

compileWith
  :: Context
  -> [Term]
  -> ErrorMonad [Text.Text]
compileWith _ [] = Right []
compileWith here terms = case compileTerm here (head terms) of
  Left compileError   -> throwError compileError
  Right (first, next) -> case compileWith next (tail terms) of
    Right rest   -> return $ first : rest
    compileError -> compileError

compileTerm
  :: Context
  -> Term
  -> ErrorMonad (Text.Text, Context)
compileTerm here value =
  case value of
    Inexact f   -> return $ (compileInexact here f, here)
    Integer i   -> return $ (compileInteger here i, here)
    Quotation q -> compileQuotation here q
    Word w      -> compileWord here w
    Definition (Word name) body@(Quotation _)
      -> compileDefinition here name body
    _ -> throwError $ CompileError "Unable to compile malformed term."

compileQuotation
  :: Context
  -> [Term]
  -> ErrorMonad (Text.Text, Context)
compileQuotation here terms
  = if quotation here then compileInside else compileOutside
  where
    compileInside
      = case compileQuotation' of
        Right result      -> return ("MKQ(" +++ result +++ ")", here)
        Left compileError -> throwError compileError

    compileOutside
      = case compileQuotation' of
        Right result      -> return ("PUSHQ(" +++ result +++ ")", here)
        Left compileError -> throwError compileError

    compiledBody = compileWith (quoted here) terms

    compileQuotation'
      = case compiledBody of
          Right compiledTerms ->
            Right $ prefix +++ Text.intercalate ", " compiledTerms
          Left compileError ->
            throwError compileError

    prefix
      = if null terms
          then "0, 0"
          else Text.show (length terms) +++ ", "

compileInexact
  :: Context
  -> Double
  -> Text.Text
compileInexact here f
  = if quotation here
      then "MKF(" +++ Text.show f +++ ")"
      else "PUSHF(" +++ Text.show f +++ ")"

compileInteger
  :: Context
  -> Integer
  -> Text.Text
compileInteger here i
  = if quotation here
      then "MKI(" +++ Text.show i +++ ")"
      else "PUSHI(" +++ Text.show i +++ ")"

compileWord
  :: Context
  -> Text.Text
  -> ErrorMonad (Text.Text, Context)
compileWord here name
  = if quotation here then compileInside else compileOutside
  where
    compileInside
      = case name `elemIndex` definitions here of
        Just index ->
          return ("MKW(" +++ Text.show index +++ ")", here)
        Nothing ->
          if name `elem` builtins
            then return ("word_new(WORD_" +++ name +++ ")", here)
            else throwError . CompileError
              $ "Undefined word \"" +++ name +++ "\""

    compileOutside
      = case name `elemIndex` definitions here of
        Just index ->
          return ("DO(" +++ Text.show index +++ ")", here)
        Nothing ->
          if name `elem` builtins
            then return ("BUILTIN(" +++ name +++ ")", here)
            else throwError . CompileError
              $ "Undefined word \"" +++ name +++ "\""

compileDefinition
  :: Context
  -> Text.Text
  -> Term
  -> ErrorMonad (Text.Text, Context)
compileDefinition here name body
  = if quotation here
      then throwError
        $ CompileError "A definition cannot appear inside a quotation."
      else case compiledBody of
        Right terms -> return
          ("DEF(" +++ Text.unwords terms +++ ")", next)
        Left compileError -> throwError compileError
  where
    compiledBody = compileWith (quoted next) [body]
    next = here `defining` name
