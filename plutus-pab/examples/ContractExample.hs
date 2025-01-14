{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE DerivingStrategies  #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

module ContractExample(
    ExampleContracts(..)
    , handlers
    ) where

import Control.Monad.Freer
import Data.Aeson (FromJSON, ToJSON)
import Data.Default (Default (def))
import GHC.Generics (Generic)
import Prettyprinter

import ContractExample.AtomicSwap qualified as Contracts.AtomicSwap
import ContractExample.IntegrationTest qualified as Contracts.IntegrationTest
import ContractExample.PayToWallet qualified as Contracts.PayToWallet
import ContractExample.WaitForTx qualified as Contracts.WaitForTx
import Data.OpenApi.Schema qualified as OpenApi
import Data.Row
import Language.PureScript.Bridge (argonaut, equal, genericShow, mkSumType, order)
import Language.PureScript.Bridge.TypeParameters (A)
import Ledger (TxId)
import Playground.Types (FunctionSchema)
import Plutus.Contracts.Currency qualified as Contracts.Currency
import Plutus.Contracts.GameStateMachine qualified as Contracts.GameStateMachine
import Plutus.Contracts.PingPong qualified as Contracts.PingPong
import Plutus.Contracts.Prism.Mirror qualified as Contracts.Prism
import Plutus.Contracts.Prism.Unlock qualified as Contracts.Prism
import Plutus.Contracts.Uniswap (Uniswap)
import Plutus.Contracts.Uniswap qualified as Contracts.Uniswap
import Plutus.Contracts.Uniswap.Types (Coin, U)
import Plutus.PAB.Effects.Contract.Builtin (Builtin, BuiltinHandler (..), HasDefinitions (..), SomeBuiltin (..))
import Plutus.PAB.Effects.Contract.Builtin qualified as Builtin
import Plutus.PAB.Run.PSGenerator (HasPSTypes (..))
import Plutus.PAB.Simulator (SimulatorEffectHandlers)
import Plutus.PAB.Simulator qualified as Simulator
import Schema (FormSchema)

data ExampleContracts = UniswapInit
                      | UniswapOwner
                      | UniswapUser Contracts.Uniswap.Uniswap
                      | GameStateMachine
                      | PayToWallet
                      | AtomicSwap
                      | Currency
                      | PrismMirror
                      | PrismUnlockExchange
                      | PrismUnlockSto
                      | PingPong
                      | PingPongAuto -- ^ Variant of 'PingPong' that starts the initialise phase automatically
                      | WaitForTx TxId
                      | IntegrationTest -- ^ Contract that runs a number of transactions (no user input)
    deriving (Eq, Ord, Show, Generic)
    deriving anyclass (FromJSON, ToJSON, OpenApi.ToSchema)

instance Pretty ExampleContracts where
    pretty = viaShow

instance HasPSTypes ExampleContracts where
    psTypes =
        [ equal . genericShow . argonaut $ mkSumType @ExampleContracts
        -- These types come from the Uniswap contract and need to be available in PS
        , equal . genericShow . argonaut $ mkSumType @Uniswap
        , equal . genericShow . argonaut $ mkSumType @(Coin A)
        , order . equal . genericShow $ argonaut $ mkSumType @U
        ]

instance HasDefinitions ExampleContracts where
    getDefinitions = [ UniswapInit
                     , UniswapOwner
                     , GameStateMachine
                     , PayToWallet
                     , AtomicSwap
                     , Currency
                     , PrismMirror
                     , PrismUnlockExchange
                     , PrismUnlockSto
                     , PingPong
                     , PingPongAuto
                     , IntegrationTest
                     ]
    getContract = getExampleContracts
    getSchema = getExampleContractsSchema

getExampleContractsSchema :: ExampleContracts -> [FunctionSchema FormSchema]
getExampleContractsSchema = \case
    UniswapInit         -> Builtin.endpointsToSchemas @Empty
    UniswapUser _       -> Builtin.endpointsToSchemas @Contracts.Uniswap.UniswapUserSchema
    UniswapOwner        -> Builtin.endpointsToSchemas @Contracts.Uniswap.UniswapOwnerSchema
    GameStateMachine    -> Builtin.endpointsToSchemas @Contracts.GameStateMachine.GameStateMachineSchema
    PayToWallet         -> Builtin.endpointsToSchemas @Contracts.PayToWallet.PayToWalletSchema
    AtomicSwap          -> Builtin.endpointsToSchemas @Contracts.AtomicSwap.AtomicSwapSchema
    Currency            -> Builtin.endpointsToSchemas @Contracts.Currency.CurrencySchema
    PrismMirror         -> Builtin.endpointsToSchemas @Contracts.Prism.MirrorSchema
    PrismUnlockExchange -> Builtin.endpointsToSchemas @Contracts.Prism.UnlockExchangeSchema
    PrismUnlockSto      -> Builtin.endpointsToSchemas @Contracts.Prism.STOSubscriberSchema
    PingPong            -> Builtin.endpointsToSchemas @Contracts.PingPong.PingPongSchema
    PingPongAuto        -> Builtin.endpointsToSchemas @Contracts.PingPong.PingPongSchema
    WaitForTx{}         -> Builtin.endpointsToSchemas @Empty
    IntegrationTest{}   -> Builtin.endpointsToSchemas @Empty

getExampleContracts :: ExampleContracts -> SomeBuiltin
getExampleContracts = \case
    UniswapInit         -> SomeBuiltin Contracts.Uniswap.setupTokens
    UniswapUser us      -> SomeBuiltin $ Contracts.Uniswap.userEndpoints us
    UniswapOwner        -> SomeBuiltin Contracts.Uniswap.ownerEndpoint
    GameStateMachine    -> SomeBuiltin Contracts.GameStateMachine.contract
    PayToWallet         -> SomeBuiltin Contracts.PayToWallet.payToWallet
    AtomicSwap          -> SomeBuiltin Contracts.AtomicSwap.atomicSwap
    Currency            -> SomeBuiltin Contracts.Currency.mintCurrency
    PrismMirror         -> SomeBuiltin (Contracts.Prism.mirror @Contracts.Prism.MirrorSchema @())
    PrismUnlockExchange -> SomeBuiltin (Contracts.Prism.unlockExchange @() @Contracts.Prism.UnlockExchangeSchema)
    PrismUnlockSto      -> SomeBuiltin (Contracts.Prism.subscribeSTO @() @Contracts.Prism.STOSubscriberSchema)
    PingPong            -> SomeBuiltin Contracts.PingPong.simplePingPong
    PingPongAuto        -> SomeBuiltin Contracts.PingPong.simplePingPongAuto
    WaitForTx txi       -> SomeBuiltin (Contracts.WaitForTx.waitForTx txi)
    IntegrationTest     -> SomeBuiltin Contracts.IntegrationTest.run

handlers :: SimulatorEffectHandlers (Builtin ExampleContracts)
handlers =
    Simulator.mkSimulatorHandlers def def
    $ interpret (contractHandler Builtin.handleBuiltin)
