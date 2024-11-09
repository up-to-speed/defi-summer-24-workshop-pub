# DeFi Security Summer 2024 <> Mastering Smart Contract Audits: A Comprehensive

We just developed a bug-free implementation of a staking contract that will invest your stablecoins (USDT & DAI supported for now) into profitable strategies. It is going to be deployed on Ethereum mainnet. In order to make sure we have equal balances of USDT and DAI, when depositing different amounts they will be auto-swapped so that the nominal value matches. 

Every deposit needs to wait for 10 days before they can withdraw penalty-free (linear decay). Deposits move funds into the contract, but someone needs to call invest() so the funds are actually invested into the strategy.

This contract is meant to be upgradeable. It will leave behind a proxy that follows the transparent proxy pattern.

NOTE: Assume Strategy.sol exists and works, but treat it as a blackbox. It is supposed to do something with funds to generate yield automagically.
