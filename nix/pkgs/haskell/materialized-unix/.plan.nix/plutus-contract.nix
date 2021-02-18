{ system
  , compiler
  , flags
  , pkgs
  , hsPkgs
  , pkgconfPkgs
  , errorHandler
  , config
  , ... }:
  {
    flags = {};
    package = {
      specVersion = "2.2";
      identifier = { name = "plutus-contract"; version = "0.1.0.0"; };
      license = "Apache-2.0";
      copyright = "";
      maintainer = "jann.mueller@iohk.io";
      author = "Jann Müller";
      homepage = "https://github.com/iohk/plutus#readme";
      url = "";
      synopsis = "";
      description = "Please see the README on GitHub at <https://github.com/input-output-hk/plutus#readme>";
      buildType = "Simple";
      isLocal = true;
      detailLevel = "FullDetails";
      licenseFiles = [ "LICENSE" "NOTICE" ];
      dataDir = "";
      dataFiles = [];
      extraSrcFiles = [];
      extraTmpFiles = [];
      extraDocFiles = [];
      };
    components = {
      "library" = {
        depends = [
          (hsPkgs."plutus-ledger" or (errorHandler.buildDepError "plutus-ledger"))
          (hsPkgs."plutus-tx" or (errorHandler.buildDepError "plutus-tx"))
          (hsPkgs."aeson" or (errorHandler.buildDepError "aeson"))
          (hsPkgs."base" or (errorHandler.buildDepError "base"))
          (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
          (hsPkgs."deepseq" or (errorHandler.buildDepError "deepseq"))
          (hsPkgs."lens" or (errorHandler.buildDepError "lens"))
          (hsPkgs."text" or (errorHandler.buildDepError "text"))
          (hsPkgs."hashable" or (errorHandler.buildDepError "hashable"))
          (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
          (hsPkgs."servant" or (errorHandler.buildDepError "servant"))
          (hsPkgs."servant-server" or (errorHandler.buildDepError "servant-server"))
          (hsPkgs."serialise" or (errorHandler.buildDepError "serialise"))
          (hsPkgs."mtl" or (errorHandler.buildDepError "mtl"))
          (hsPkgs."semigroupoids" or (errorHandler.buildDepError "semigroupoids"))
          (hsPkgs."profunctors" or (errorHandler.buildDepError "profunctors"))
          (hsPkgs."template-haskell" or (errorHandler.buildDepError "template-haskell"))
          (hsPkgs."transformers" or (errorHandler.buildDepError "transformers"))
          (hsPkgs."warp" or (errorHandler.buildDepError "warp"))
          (hsPkgs."newtype-generics" or (errorHandler.buildDepError "newtype-generics"))
          (hsPkgs."hedgehog" or (errorHandler.buildDepError "hedgehog"))
          (hsPkgs."transformers-base" or (errorHandler.buildDepError "transformers-base"))
          (hsPkgs."monad-control" or (errorHandler.buildDepError "monad-control"))
          (hsPkgs."mmorph" or (errorHandler.buildDepError "mmorph"))
          (hsPkgs."row-types" or (errorHandler.buildDepError "row-types"))
          (hsPkgs."freer-simple" or (errorHandler.buildDepError "freer-simple"))
          (hsPkgs."prettyprinter" or (errorHandler.buildDepError "prettyprinter"))
          (hsPkgs."semigroups" or (errorHandler.buildDepError "semigroups"))
          (hsPkgs."cryptonite" or (errorHandler.buildDepError "cryptonite"))
          (hsPkgs."fingertree" or (errorHandler.buildDepError "fingertree"))
          (hsPkgs."uuid" or (errorHandler.buildDepError "uuid"))
          (hsPkgs."aeson-pretty" or (errorHandler.buildDepError "aeson-pretty"))
          (hsPkgs."unordered-containers" or (errorHandler.buildDepError "unordered-containers"))
          (hsPkgs."foldl" or (errorHandler.buildDepError "foldl"))
          (hsPkgs."streaming" or (errorHandler.buildDepError "streaming"))
          ] ++ (pkgs.lib).optionals (!(compiler.isGhcjs && true || system.isGhcjs)) [
          (hsPkgs."tasty" or (errorHandler.buildDepError "tasty"))
          (hsPkgs."tasty-hunit" or (errorHandler.buildDepError "tasty-hunit"))
          ];
        buildable = true;
        modules = [
          "Data/Row/Extras"
          "Data/Text/Extras"
          "Data/UUID/Extras"
          "Language/Plutus/Contract"
          "Language/Plutus/Contract/Effects/AwaitSlot"
          "Language/Plutus/Contract/Effects/AwaitTxConfirmed"
          "Language/Plutus/Contract/Effects/Instance"
          "Language/Plutus/Contract/Effects/RPC"
          "Language/Plutus/Contract/Effects/ExposeEndpoint"
          "Language/Plutus/Contract/Effects/Notify"
          "Language/Plutus/Contract/Effects/OwnPubKey"
          "Language/Plutus/Contract/Effects/UtxoAt"
          "Language/Plutus/Contract/Effects/WatchAddress"
          "Language/Plutus/Contract/Effects/WriteTx"
          "Language/Plutus/Contract/Request"
          "Language/Plutus/Contract/Checkpoint"
          "Language/Plutus/Contract/Constraints"
          "Language/Plutus/Contract/State"
          "Language/Plutus/Contract/Schema"
          "Language/Plutus/Contract/Trace"
          "Language/Plutus/Contract/Trace/RequestHandler"
          "Language/Plutus/Contract/Servant"
          "Language/Plutus/Contract/Resumable"
          "Language/Plutus/Contract/StateMachine"
          "Language/Plutus/Contract/StateMachine/OnChain"
          "Language/Plutus/Contract/Tx"
          "Language/Plutus/Contract/Types"
          "Language/Plutus/Contract/Util"
          "Language/Plutus/Contract/Wallet"
          "Language/Plutus/Contract/Typed/Tx"
          "Wallet/Emulator"
          "Wallet/Emulator/Types"
          "Wallet/Emulator/Chain"
          "Wallet/Emulator/ChainIndex"
          "Wallet/Emulator/ChainIndex/Index"
          "Wallet/Emulator/Error"
          "Wallet/Emulator/Folds"
          "Wallet/Emulator/LogMessages"
          "Wallet/Emulator/NodeClient"
          "Wallet/Emulator/MultiAgent"
          "Wallet/Emulator/Stream"
          "Wallet/Emulator/Wallet"
          "Wallet/Rollup"
          "Wallet/Rollup/Types"
          "Wallet/Rollup/Render"
          "Wallet"
          "Wallet/API"
          "Wallet/Effects"
          "Wallet/Graph"
          "Wallet/Types"
          "Control/Monad/Freer/Extras"
          "Control/Monad/Freer/Log"
          "Control/Monad/Freer/Stream"
          "Plutus/Trace"
          "Plutus/Trace/Effects/ContractInstanceId"
          "Plutus/Trace/Effects/RunContract"
          "Plutus/Trace/Effects/RunContractPlayground"
          "Plutus/Trace/Effects/EmulatedWalletAPI"
          "Plutus/Trace/Effects/EmulatorControl"
          "Plutus/Trace/Effects/Waiting"
          "Plutus/Trace/Emulator"
          "Plutus/Trace/Emulator/ContractInstance"
          "Plutus/Trace/Emulator/System"
          "Plutus/Trace/Emulator/Types"
          "Plutus/Trace/Playground"
          "Plutus/Trace/Scheduler"
          "Plutus/Trace/Tag"
          ] ++ (pkgs.lib).optional (!(compiler.isGhcjs && true || system.isGhcjs)) "Language/Plutus/Contract/Test";
        hsSourceDirs = [ "src" ];
        };
      tests = {
        "contract-doctests" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."template-haskell" or (errorHandler.buildDepError "template-haskell"))
            (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
            (hsPkgs."plutus-core" or (errorHandler.buildDepError "plutus-core"))
            (hsPkgs."plutus-contract" or (errorHandler.buildDepError "plutus-contract"))
            (hsPkgs."plutus-ledger" or (errorHandler.buildDepError "plutus-ledger"))
            (hsPkgs."prettyprinter" or (errorHandler.buildDepError "prettyprinter"))
            (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
            ];
          build-tools = [
            (hsPkgs.buildPackages.unlit or (pkgs.buildPackages.unlit or (errorHandler.buildToolDepError "unlit")))
            (hsPkgs.buildPackages.doctest or (pkgs.buildPackages.doctest or (errorHandler.buildToolDepError "doctest")))
            ];
          buildable = true;
          modules = [ "ContractAPI" ];
          hsSourceDirs = [ "doctest" "doc" ];
          mainPath = [ "Main.hs" ];
          };
        "plutus-contract-test" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
            (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
            (hsPkgs."hedgehog" or (errorHandler.buildDepError "hedgehog"))
            (hsPkgs."tasty" or (errorHandler.buildDepError "tasty"))
            (hsPkgs."tasty-hunit" or (errorHandler.buildDepError "tasty-hunit"))
            (hsPkgs."tasty-hedgehog" or (errorHandler.buildDepError "tasty-hedgehog"))
            (hsPkgs."text" or (errorHandler.buildDepError "text"))
            (hsPkgs."mtl" or (errorHandler.buildDepError "mtl"))
            (hsPkgs."aeson" or (errorHandler.buildDepError "aeson"))
            (hsPkgs."lens" or (errorHandler.buildDepError "lens"))
            (hsPkgs."transformers" or (errorHandler.buildDepError "transformers"))
            (hsPkgs."extensible-effects" or (errorHandler.buildDepError "extensible-effects"))
            (hsPkgs."plutus-contract" or (errorHandler.buildDepError "plutus-contract"))
            (hsPkgs."plutus-ledger" or (errorHandler.buildDepError "plutus-ledger"))
            (hsPkgs."plutus-tx" or (errorHandler.buildDepError "plutus-tx"))
            (hsPkgs."freer-simple" or (errorHandler.buildDepError "freer-simple"))
            (hsPkgs."aeson" or (errorHandler.buildDepError "aeson"))
            ] ++ (pkgs.lib).optional (!(compiler.isGhcjs && true || system.isGhcjs)) (hsPkgs."plutus-tx-plugin" or (errorHandler.buildDepError "plutus-tx-plugin"));
          buildable = true;
          modules = [
            "Spec/Contract"
            "Spec/Emulator"
            "Spec/Rows"
            "Spec/State"
            ];
          hsSourceDirs = [ "test" ];
          mainPath = [ "Spec.hs" ];
          };
        };
      };
    } // rec { src = (pkgs.lib).mkDefault ../plutus-contract; }