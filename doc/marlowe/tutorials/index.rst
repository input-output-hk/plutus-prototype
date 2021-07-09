.. _marlowe_tutorials:

Tutorials
=========

This document gives an overview the Marlowe tutorials.

1.  :ref:`introducing-marlowe`
    This tutorial gives an overview of the ideas behind Marlowe, as a
    domain-specific language embedded in Haskell. It also introduces
    commitments and timeouts, which are central to how Marlowe works in
    a blockchain context.

2.  :ref:`escrow-ex` This tutorial introduces
    a simple financial contract in pseudocode, before explaining how it
    is modified to work in Marlowe, giving the first example of a
    Marlowe contract.

3.  :ref:`marlowe-model` In this
    tutorial we look at our general approach to modelling contracts in
    Marlowe, and the context in which Marlowe contracts are executed:
    the Cardano blockchain. In doing this we also introduce some of the
    standard terminology that we will use in describing Marlowe.

4.  :ref:`marlowe-step-by-step`
    This tutorial explains the six ways of building contracts in
    Marlowe. Five of these – ``Pay``, ``Let``, ``If``, ``When`` and ``Assert`` –
    build a complex contract from simpler contracts, and the sixth,
    ``Close``, is a simple contract. In explaining these contracts we
    will also explain Marlowe *values*, *observations* and *actions*,
    which are used to supply external information and inputs to a
    running contract to control how it will evolve.

5.  :ref:`playground-blockly`
    This section shows how Marlowe contracts are built using the Blockly
    visual programming environment.

6.  :ref:`marlowe-data` This tutorial
    formally introduces Marlowe as a Haskell data type, as well as
    presenting the different types used by the model, and discussing a
    number of assumptions about the infrastructure in which contracts
    will be run.

7.  :ref:`embedded-marlowe`
    This tutorial shows how to use some simple features of Haskell to
    write Marlowe contracts that are more readable, maintainable and
    reusable, illustrated by revisiting the escrow contract.

8.  :ref:`javascript-embedding`
    Marlowe is also embedded in JavaScript, and here we show how Marlowe
    contracts can be created and edited in JavaScript.

9.  :ref:`playground-overview`
    This tutorial introduces the Marlowe Playground, an online tool for
    creating embedded Marlowe contracts and interactively stepping
    through their execution.

10. :ref:`potential-problems-with-contracts`
    This tutorial reviews how not to write Marlowe contracts, and what
    can go wrong when executing contracts even if they have been written
    correctly.

11. :ref:`static-analysis`
    Marlowe contracts can be analysed without running them, and so, for
    instance, we can verify that a contract will always make the
    payments that it is required to, irrespective of the inputs that it
    receives. This tutorial explains this, and how to run an analysis in
    the playground.

12. :ref:`actus-marlowe` This
    tutorial gives an introduction to the general idea of the ACTUS
    taxonomy, plus examples implemented in Marlowe.

13. :ref:`actus-labs` The Actus Labs
    support generation of different styles of Actus contract from the
    parameters that describe the particular contract instance.

14. :ref:`wallets-simulation`
    The wallets simulation present a view of a running contract from the
    perspective of a participant in that contract, rather than the
    ‘omniscient‘ view given in the simulation tab.

15. :ref:`using-marlowe` This
    tutorial shows you how to use Marlowe from the command line in ghci,
    and in particular shows how to exercise a contract using the
    semantics given earlier.

16. :ref:`migrating` Here we explain how the
    current version of Marlowe is related to earlier versions.

..

   These tutorials address the current version of Marlowe, which is
   implemented in the `Marlowe Playground`_.

   The version covered in the ISoLA paper, and supported in the original
   version of the Playground (called Meadow), is tagged as **v1.3** and
   is available
   `here <https://github.com/input-output-hk/marlowe/tree/v1.3>`_.

.. toctree::
   :maxdepth: 3
   :titlesonly:
   :hidden:

   introducing-marlowe
   escrow-ex
   marlowe-model
   marlowe-step-by-step
   playground-blockly
   marlowe-data
   embedded-marlowe
   javascript-embedding
   playground-overview
   potential-problems-with-contracts
   static-analysis
   actus-marlowe
   actus-labs
   wallets-simulation
   using-marlowe
   migrating
