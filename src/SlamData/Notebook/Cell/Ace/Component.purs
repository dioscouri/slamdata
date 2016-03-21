{-
Copyright 2016 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module SlamData.Notebook.Cell.Ace.Component
  ( aceComponent
  , AceEvaluator()
  , AceDSL()
  , AceHTML()
  , AceSetup()
  , module SlamData.Notebook.Cell.Ace.Component.Query
  , module SlamData.Notebook.Cell.Ace.Component.State
  ) where

import SlamData.Prelude

import Control.Monad.Eff.Class (liftEff)

import Ace.Editor as Editor
import Ace.EditSession as Session
import Ace.Halogen.Component (AceQuery(..), AceState(), Autocomplete(..), aceConstructor)
import Ace.Types (Editor())

import Halogen as H
import Halogen.HTML.Indexed as HH
import Halogen.HTML.Properties.Indexed as HP

import SlamData.Notebook.Cell.Ace.Component.Query
import SlamData.Notebook.Cell.Ace.Component.State
import SlamData.Notebook.Cell.Ace.Model as Model
import SlamData.Notebook.Cell.CellType (AceMode(), aceMode, aceCellName, aceCellGlyph)
import SlamData.Notebook.Cell.Common.EvalQuery (CellEvalQuery(..), CellEvalResult(), CellEvalInput(), CellSetupInfo())
import SlamData.Notebook.Cell.Component (CellStateP(), CellQueryP(), makeEditorCellComponent, makeQueryPrism, _AceState, _AceQuery)
import SlamData.Effects (Slam())
import SlamData.Render.CSS as CSS

import Utils.Ace (getRangeRecs, readOnly)

type AceDSL = H.ParentDSL Unit AceState CellEvalQuery AceQuery Slam Unit
type AceHTML = H.ParentHTML AceState CellEvalQuery AceQuery Slam Unit
type AceEvaluator = CellEvalInput -> String -> AceDSL CellEvalResult
type AceSetup = CellSetupInfo -> AceDSL Unit

type AceConfig =
  { mode :: AceMode
  , evaluator :: AceEvaluator
  , setup :: AceSetup
  }

aceComponent :: AceConfig -> H.Component CellStateP CellQueryP Slam
aceComponent {mode, evaluator, setup} = makeEditorCellComponent
  { name: aceCellName mode
  , glyph: aceCellGlyph mode
  , component: H.parentComponent { render, eval, peek: Nothing }
  , initialState: H.parentState unit
  , _State: _AceState
  , _Query: makeQueryPrism _AceQuery
  }

  where
  render :: Unit -> AceHTML
  render _ =
    HH.div
      [ HP.classes [CSS.cellInput, CSS.aceContainer] ]
      [ HH.Slot (aceConstructor unit aceSetup (Just Live) ) ]

  aceSetup :: Editor -> Slam Unit
  aceSetup editor = liftEff do
    Editor.setMinLines 4 editor
    Editor.setMaxLines 10000 editor
    Editor.setAutoScrollEditorIntoView true editor
    Editor.setTheme "ace/theme/chrome" editor
    Editor.setEnableLiveAutocompletion true editor
    Editor.setEnableBasicAutocompletion true editor
    session <- Editor.getSession editor
    Session.setMode (aceMode mode) session

  eval :: Natural CellEvalQuery AceDSL
  eval (NotifyRunCell next) = pure next
  eval (EvalCell info k) = do
    content <- fromMaybe "" <$> H.query unit (H.request GetText)
    result <- evaluator info content
    pure $ k result
  eval (SetupCell input next) = setup input $> next
  eval (Save k) = do
    content <- fromMaybe "" <$> H.query unit (H.request GetText)
    mbEditor <- H.query unit (H.request GetEditor)
    rrs <- H.fromEff $ maybe (pure []) getRangeRecs $ join mbEditor
    pure $ k $ Model.encode { text: content, ranges: rrs }
  eval (Load json next) = do
    let model = either (const Model.emptyModel) id $ Model.decode json
        text = model.text
        ranges = model.ranges
    H.query unit $ H.action (SetText text)
    mbEditor <- H.query unit $ H.request GetEditor
    H.fromEff $ for_ (join mbEditor) \editor -> do
      traverse_ (readOnly editor) ranges
      Editor.navigateFileEnd editor
    pure next
  eval (SetCanceler _ next) = pure next
