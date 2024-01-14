# Simple-AA-Wallet

## description
以太坊歷時多年的發展，在上面的開發變得越來越多元，也越來越有趣，但錢包的實用性常常是被討論的部分，如何能夠更加實做出安全與彈性兼具的錢包也是一大挑戰，而在去年三月份左右一個值得期待的ERC4337問世，提供錢包更多方便且彈性的操作同時又具備安全性的提案，我也希望透過這個專案設計一個簡易的AA-wallet，實作並探索這個有趣的提案。

## features
1. ERC-4337 
2. MultiSig
3. Social Recovery

## SetUp
```shell
git clone https://github.com/max8633/Simple_AA_Wallet.git
cd Simple_AA_Wallet
forge build
forge test
```

## testing
- `wallet.t.sol`：直接與wallet合約互動，測試function功能
- `walletInteractWithEntryPoint.t.sol`：測試透過entryPoint與wallet合約互動

