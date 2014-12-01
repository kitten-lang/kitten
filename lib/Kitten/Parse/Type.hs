{-# LANGUAGE OverloadedStrings #-}

module Kitten.Parse.Type
  ( baseType
  , scalarQuantifier
  , signature
  , typeDefType
  , type_
  ) where

import Control.Applicative
import Data.Either
import Data.Vector (Vector)

import qualified Data.Vector as V

import Kitten.Annotation
import Kitten.Name
import Kitten.Parse.Monad
import Kitten.Parse.Primitive
import Kitten.Parsec
import Kitten.Token
import Kitten.Util.Parsec
import Kitten.Util.Tuple

signature :: Parser Anno
signature = (<?> "type signature") . locate
  $ Anno <$> (quantified sig <|> sig)
  where sig = grouped functionType

typeDefType :: Parser Anno
typeDefType = locate $ Anno <$> baseType

type_ :: Parser AnType
type_ = (<?> "type") $ try functionType <|> baseType

scalarQuantifier :: Parser (Vector Name)
scalarQuantifier = V.fromList <$> angled (word `sepEndBy1` comma)

quantifier :: Parser (Vector Name, Vector Name)
quantifier = both V.fromList . partitionEithers
  <$> angled (variable `sepEndBy1` comma)
  where
  variable = do
    name <- word
    ($ name) <$> option Right (Left <$ ellipsis)

angled :: Parser a -> Parser a
angled = between leftAngle rightAngle
  where
  leftAngle = match (TkOperator "<")
  rightAngle = match (TkOperator ">")

quantified :: Parser AnType -> Parser AnType
quantified thing = uncurry AnQuantified <$> quantifier <*> thing

ellipsis :: Parser Token
ellipsis = match TkEllipsis

functionType :: Parser AnType
functionType = (<?> "function type") $ choice
  [ try $ AnStackFunction
    <$> (word <* ellipsis) <*> left <*> (word <* ellipsis) <*> right
  , AnFunction <$> left <*> right
  ]
  where
  left, right :: Parser (Vector AnType)
  left = manyV baseType <* match TkArrow
  right = manyV type_

baseType :: Parser AnType
baseType = (<?> "base type") $ do
  prefix <- choice
    [ quantified (grouped type_)
    , AnVar <$> qualified_
    , vector
    , grouped type_
    ]
  (<?> "") $ choice
    [ AnChoice prefix
      <$> (match (TkOperator "|") *> baseType)
    , AnOption prefix <$ match (TkOperator "?")
    , AnPair prefix
      <$> (match (TkOperator "&") *> baseType)
    , AnApp prefix
      <$> (forAll *> choice
        [ grouped (baseType `sepEndBy1V` comma)
        , V.singleton <$> baseType
        ])
    , pure prefix
    ]

forAll :: Parser Token
forAll = match (TkOperator "@") <|> match (TkOperator "\x2200")

comma :: Parser Token
comma = match TkComma

vector :: Parser AnType
vector = AnVector <$> between
  (match TkVectorBegin) (match TkVectorEnd) type_
