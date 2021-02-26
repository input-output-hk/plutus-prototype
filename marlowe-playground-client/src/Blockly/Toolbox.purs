module Blockly.Toolbox
  ( Toolbox(..)
  , ToolboxBlock
  , Category
  , encodeToolbox
  , block
  , category
  , leaf
  ) where

import Prelude
import Data.Argonaut.Core (Json)
import Data.Argonaut.Core as A
import Data.Array (catMaybes)
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Foreign.Object as Object

data Toolbox
  = FlyoutToolbox (Array ToolboxBlock)
  | CategoryToolbox (Array Category)

encodeToolbox :: Toolbox -> Json
encodeToolbox (FlyoutToolbox xs) =
  A.fromObject
    ( Object.fromFoldable
        [ Tuple "kind" (A.fromString "flyoutToolbox")
        , Tuple "contents" (A.fromArray $ encodeBlock <$> xs)
        ]
    )

encodeToolbox (CategoryToolbox xs) =
  A.fromObject
    ( Object.fromFoldable
        [ Tuple "kind" (A.fromString "categoryToolbox")
        , Tuple "contents" (A.fromArray $ encodeCategory <$> xs)
        ]
    )

type ToolboxBlock
  = { type :: String
    }

encodeBlock :: ToolboxBlock -> Json
encodeBlock b =
  A.fromObject
    ( Object.fromFoldable
        [ Tuple "kind" (A.fromString "block")
        , Tuple "type" (A.fromString b.type)
        ]
    )

block :: String -> ToolboxBlock
block _type = { type: _type }

type CategoryFields
  = { name :: String
    , toolboxitemid :: Maybe String
    , colour :: Maybe String
    , categorystyle :: Maybe String
    -- https://developers.google.com/blockly/guides/configure/web/toolbox#expanded
    , expanded :: Boolean -- (default to false) (encoded as string)
    -- Categories can also have this properties that we don't need to implement at the moment
    -- cssConfig :: Object String
    -- https://developers.google.com/blockly/guides/configure/web/toolbox#dynamic_categories
    -- custom :: Maybe String
    }

defaultCategoryFields :: CategoryFields
defaultCategoryFields =
  { name: ""
  , toolboxitemid: Nothing
  , colour: Nothing
  , categorystyle: Nothing
  , expanded: false
  }

category :: String -> String -> Array Category -> Category
category name colour children =
  Category
    (defaultCategoryFields { name = name, colour = Just colour })
    children

leaf :: String -> Category
leaf _type = CategoryLeaf $ block _type

data Category
  = Category CategoryFields (Array Category)
  | CategoryLeaf ToolboxBlock

-- A category could also be one of these, but not worth to implement at the moment
-- https://developers.google.com/blockly/guides/configure/web/toolbox#preset_blocks
-- https://developers.google.com/blockly/guides/configure/web/toolbox#separators
-- https://developers.google.com/blockly/guides/configure/web/toolbox#buttons_and_labels
encodeCategory :: Category -> Json
encodeCategory (Category fields children) =
  A.fromObject
    ( Object.fromFoldable
        ( [ Tuple "kind" (A.fromString "category")
          , Tuple "name" (A.fromString fields.name)
          , Tuple "contents" (A.fromArray $ encodeCategory <$> children)
          , Tuple "expanded" (A.fromString $ show fields.expanded)
          ]
            <> catMaybes
                [ Tuple "toolboxitemid" <<< A.fromString <$> fields.toolboxitemid
                , Tuple "colour" <<< A.fromString <$> fields.colour
                , Tuple "categorystyle" <<< A.fromString <$> fields.categorystyle
                ]
        )
    )

encodeCategory (CategoryLeaf b) = encodeBlock b
