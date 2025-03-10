module Foreign.Purs where

import Registry.Prelude

import Data.Array as Array
import Data.String as String
import Effect.Exception as Exception
import Node.ChildProcess as NodeProcess
import Registry.Json as Json
import Sunde as Process

-- | Call a specific version of the PureScript compiler
callCompiler_ :: { version :: String, args :: Array String, cwd :: Maybe FilePath } -> Aff Unit
callCompiler_ = void <<< callCompiler

data CompilerFailure
  = CompilationError (Array CompilerError)
  | UnknownError String
  | MissingCompiler

derive instance Eq CompilerFailure

type CompilerError =
  { position :: SourcePosition
  , message :: String
  , errorCode :: String
  , errorLink :: String
  , filename :: FilePath
  , moduleName :: String
  }

type SourcePosition =
  { startLine :: Int
  , startColumn :: Int
  , endLine :: Int
  , endColumn :: Int
  }

printCompilerErrors :: Array CompilerError -> String
printCompilerErrors errors = do
  let
    total = Array.length errors
    printed =
      errors # Array.mapWithIndex \n error -> String.joinWith "\n"
        [ "Error " <> show (n + 1) <> " of " <> show total
        , ""
        , printCompilerError error
        ]

  String.joinWith "\n" printed
  where
  printCompilerError :: CompilerError -> String
  printCompilerError { moduleName, filename, message, errorLink } =
    String.joinWith "\n"
      [ "  Module: " <> moduleName
      , "  File: " <> filename
      , "  Message:"
      , ""
      , "  " <> message
      , ""
      , "  Error details:"
      , "  " <> errorLink
      ]

type CompilerArgs =
  { version :: String
  , cwd :: Maybe FilePath
  , args :: Array String
  }

-- | Call a specific version of the PureScript compiler
callCompiler :: CompilerArgs -> Aff (Either CompilerFailure String)
callCompiler compilerArgs = do
  let
    args = Array.snoc compilerArgs.args "--json-errors"
    -- Converts a string version 'v0.13.0' or '0.13.0' to the standard format for
    -- executables 'purs-0_13_0'
    cmd =
      append "purs-"
        $ String.replaceAll (String.Pattern ".") (String.Replacement "_")
        $ fromMaybe compilerArgs.version
        $ String.stripPrefix (String.Pattern "v") compilerArgs.version

  result <- try $ Process.spawn { cmd, stdin: Nothing, args } (NodeProcess.defaultSpawnOptions { cwd = compilerArgs.cwd })
  pure $ case result of
    Left exception -> Left $ case Exception.message exception of
      errorMessage
        | errorMessage == String.joinWith " " [ "spawn", cmd, "ENOENT" ] -> MissingCompiler
        | otherwise -> UnknownError errorMessage
    Right { exit: NodeProcess.Normally 0, stdout } -> Right $ String.trim stdout
    Right { stdout } -> Left do
      case Json.parseJson (String.trim stdout) of
        Left err -> UnknownError $ String.joinWith "\n" [ stdout, err ]
        Right ({ errors } :: { errors :: Array CompilerError })
          | Array.null errors -> UnknownError "Non-normal exit code, but no errors reported."
          | otherwise -> CompilationError errors
