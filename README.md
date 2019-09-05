<h1>Alethena Share Dispenser</h1>

The share dispenser allows a company to provide a certain degree of liquidity to their shares. 
The company deploys the share dispenser smart contract and supplies it with tokenised shares (and optionally an amount of Crypto Francs). Anyone can then buy and sell shares directly at a price dynamically computed depending on the current supply.


<h2>Smart Contract Documentation</h2>

**Running the Smart Contract Locally**

This project uses the truffle framework (https://truffleframework.com/). 

Clone the whole repository and install the necessary dependecies with `npm install` (or run `./init.sh` which includes the ng dependencies).

To run the test cases use `truffle test` - you need to run a local blockchain (Ganache https://truffleframework.com/ganache) to do this.

To deploy, run `truffle compile` and then `truffle migrate`. You can choose the network to deploy to in `tuffle-config.js`.

This will deploy a new instance of the ALEQ, XCHF, and Share Dispenser contracts and will provide the right arguments to the constructor of the Share Dispenser. 

**State Variables**

The contract uses the following variables:

* `address public XCHFContractAddress` is the contract address where the Crypto Franc is deployed

* `address public ALEQContractAddress` is the contract address where the Alethena Shares Token is deployed

* `address public usageFeeAddress` is a (non-contract) address where the usage fees are collected

The three addresses above have to be supplied to the constructor function (allows for easy cascaded deployment).

* `uint256 public usageFeeBSP`  This is the usage fee expressed in basis points (10000BSP = 100%). When shares are bought or sold, this fraction of the XCHF payment is transferred to the `usageFeeAddress`. A value of zero corresponds to no usage fee, a value of 500 corresponds to 5% usage fee.


**Pricing Model**

* The price is adjusted according to the available supply.
* Initially a total of `uint256 public initialNumberOfShares` shares are allocated (i.e. sent to) the share dispenser contract.
* The first share is to be sold at price `uint256 public minPriceInXCHF` and the last at price `uint256 public maxPriceInXCHF`. Inbetween a linear interpolation is used, please see the pricing documentation for details and formulas.
* The pricing functions are implemented in the `getCumulatedPrice` and `getCumulatedBuyBackPrice` functions which both take two arguments, namely the number of shares to be bought/sold and the number of shares currently available. 
* There is a relation between buy and sell prices in the sense that buying shares and subsequently selling them straight away should have no effect apart from transactions fees spent.
* If the company additionally supplies XCHF, a situation can occur where the number of shares held by the contract exceeds `initialNumberOfShares`. In this case, the share surplus will be sold at price `minPriceInXCHF`.
* The buy and sell sides can be separately enabled/disabled through the variables `bool public buyEnabled` and `bool public sellEnabled`.

**The Buy Process**

To buy shares the user first grants a sufficient XCHF allowance to the dispenser smart contract.
Then the user calls the function `buyShares` with one argument, the number of shares to buy.

1. It is checked that buying is enabled.
2. The number of shares available is fetched and the totalPrice is computed using `getCumulatedPrice`.
3. It is checked that the dispenser has enough shares and the buyer has sufficient XCHF balance and allowance set.
4. The usage fee is computed and subtracted from the total price.
5. Usage fee is transferred to the corresponding address.
6. The remaining XCHF is transferred to the dispenser contract.
7. The shares are transferred to the buyer.
8. An event is emitted and the function returns `true`.

If any conditions is not met or an ERC20 transaction does not go through, the function reverts.
Any user can call `buyShares`.

**The Sell Process**

To buy shares the user first grants a sufficient ALEQ allowance to the dispenser smart contract.
Then the user calls the function `sellShares` with two arguments, the number of shares to sell and the lowest price the seller will accept (see section Race Conditions).

1. It is checked that selling is enabled.
2. The number of XCHF available is fetched and the totalPrice is computed using `getCumulatedBuyBackPrice`.
3. It is checked that the totalPrice is not lower than the price limit supplied as the second argument.
4. It is checked that the dispenser has enough XCHF and the seller has sufficient ALEQ balance and allowance set.
5. The usage fee is computed and subtracted from the total price.
6. The shares are transferred from the seller to the dispenser contract.
7. Usage fee is transferred to the corresponding address.
8. The remaining XCHF is transferred to the dispenser seller.
9. An event is emitted and the function returns `true`.

If any conditions is not met or an ERC20 transaction does not go through, the function reverts.
Any user can call `sellShares`.

**Decimals and Arithmetic**

XCHF has 18 decimals, ALEQ has zero decimals.
Share prices are entered by the user in Rappen (0.01 XCHF). Hence we need a factor of 10**16 inbetween.

All arithmetic operations are handled using the `safeMath` open-zeppelin library (https://www.npmjs.com/package/openzeppelin-solidity). 
Given transaction costs (as well as usage fee) rounding errors in integer division will not lead to an arbitrage possibility through repeated buying and selling.

**Additional Functions**

* The XCHF or ALEQ balance held by the dispenser contract can be retrieved through `getERC20Balance` which takes the corresponding contract address as an argument. 
* To check that a share purchase can happen, the user needs to hold a sufficient amount of XCHF (or ALEQ) but they also need to give a sufficient allowance to the dispenser contract. This is checked using the `getERC20Available` function which takes two arguments, the contract address (ALEQ or XCHF) as well as the potential buyer/seller.
* In order for the company to retrieve XCHF or ALEQ from the dispenser contract the `retrieveERC20` function is implemented. It expects three arguments, the contract address (ALEQ or XCHF), the address to send the tokens to as well as the amount. This function can only be called by the contract owner.

**Permissions**

* The contract has an owner. This is handled through the corresponding open-zeppelin contract.
* The contract is pausible by the owner (using the corresponding open-zeppelin contract).
* The user can call the following functions `buyShares`, `sellShares`, `getERC20Balance`, `getERC20Available`, `getCumulatedPrice`, `getCumulatedBuyBackPrice`.
* All other functions are restricted to internal use or can only be called by the contract owner.

Users interact with the Share Dispenser only during transactions. It is therefore important that the process is transparent
and the user is fully aware of the logic at the time of the transaction.
However, the operator of the Share Dispenser reserves the right to unilaterally
change parameters or pause the contract at any time. 
The contract is not autonomous and is not intended to act in a DAO like fashion.

"Trust" in the system should therefore only refer to transactions (e.g. the contract is not a honeypot).

**A Note on Versions**

The deployed version of the ALEQ contract (https://etherscan.io/address/0xf40c5e190a608b6f8c0bf2b38c9506b327941402#code) uses Solidity 0.4.24, the deployed version of the XCHF contract (https://etherscan.io/address/0xb4272071ecadd69d933adcd19ca99fe80664fc08#code) uses Solidity 0.4.25. 
The share dispenser uses Solidity version 0.5.0 (because of Truffle compatibility).
For simplicity the ALEQ and XCHF contracts in this repository have been updated to Solidity version 0.5.0.
Only the core ERC20 functionality of these two tokens is used, which is not affected by the compiler version.

**Race Conditions**

Consider a situation where two users (Alice and Bob) both check the cumulated price for buying 10 shares roughly at the same time. Based on this Alice and Bob both give the corresponding XCHF allowance to the Share Dispenser contract.
Let's assume Alice and Bob now both call the `buyShares` function roughly at the same time. 
If the transaction of Alice goes through first, the transaction of Bob will revert because the price for the same number of shares has increased in the meantime. 

A similar case can occur when selling shares. To protect the seller, along with the number of shares to sell a limit needs to be supplied. If the price moves below the limit after a transaction is broadcasted, it will revert.

Both of these cases can be handled in the front-end so that the user understands what has happened.


<h1>Front-end Documentation</h1>

**Running Locally**

To run locally:
- cd into folder
- run `./init.sh` (on Windows use `sh .\init`)

**Attention:** 

There is a breaking change in the npm module `truffle-contract` from version 4.x.x onwards (breaks bignumber dependencies).
