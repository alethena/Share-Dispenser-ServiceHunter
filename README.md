<h1>Alethena Share Dispenser for Draggable ServiceHunter Shares (DSHS)</h1>

The Share Dispenser allows ServiceHunter AG to provide a certain degree of liquidity to their draggable ServiceHunter shares (DSHS). ServiceHunter AG deploys the Share Dispenser smart contract and supplies it with tokenised DSHS and (optionally) an amount of Crypto Francs ([XCHF](https://www.swisscryptotokens.ch)). Anyone can then buy and sell DSHS directly at a price dynamically computed depending on the current supply.

<h2>Smart Contract Documentation</h2>

**State Variables**

The contract uses the following variables:

* `address public XCHFContractAddress` is the contract address where the Crypto Franc is deployed

* `address public DSHSContractAddress` is the contract address where the DSHS are deployed

* `address public usageFeeAddress` is a (non-contract) address where the usage fees are collected

The three addresses above have to be supplied to the constructor function (allows for easy cascaded deployment).

* `uint256 public usageFeeBSP` This is the usage fee expressed in basis points (10000BSP = 100%). When DSHS are bought or sold, this fraction (currently 0.9%) on top of the XCHF payment is transferred to the `usageFeeAddress`.

**Pricing Model**

* The price is adjusted according to the available supply.
* Initially a total of `uint256 public initialNumberOfShares` shares are allocated (i.e. sent to) the Share Dispenser contract.
* The first share is to be sold at price `uint256 public minPriceInXCHF` and the last at price `uint256 public maxPriceInXCHF`. In-between a linear interpolation is used.
* The pricing functions are implemented in the `getCumulatedPrice` and `getCumulatedBuyBackPrice` functions which both take two arguments, namely the number of shares to be bought/sold and the number of shares currently available. 
* There is a relation between buy and sell prices in the sense that buying shares and subsequently selling them straight away should have no effect apart from transaction & usage fees spent.
* If the company additionally supplies XCHF, a situation can occur where the number of shares held by the contract exceeds `initialNumberOfShares`. In this case, the share surplus will be sold at price `minPriceInXCHF`.
* The buy and sell sides can be separately enabled/disabled through the variables `bool public buyEnabled` and `bool public sellEnabled`.

**The Buy Process**

To buy shares the user first grants a sufficient XCHF allowance to the Share Dispenser smart contract. Then the user calls the function `buyShares` with one argument, the number of shares to buy. If any conditions is not met or an ERC20 transaction does not go through, the function reverts. Any user can call `buyShares`.

**The Sell Process**

To sell shares the user first grants a sufficient DSHS allowance to the Share Dispenser smart contract. Then the user calls the function `sellShares` with two arguments, the number of shares to sell and the lowest price the seller will accept (see section Race Conditions). If any conditions is not met or an ERC20 transaction does not go through, the function reverts.
Any user can call `sellShares`.

**Decimals and Arithmetic**

XCHF has 18 decimals, DSHS has zero decimals. Share prices are entered by the user in Rappen (0.01 XCHF). Hence we need a factor of 10**16 in-between. Given transaction costs (as well as usage fee) rounding errors in integer division will not lead to an arbitrage possibility through repeated buying and selling.

**Additional Functions**

* The XCHF or DSHS balance held by the Share Dispenser contract can be retrieved through `getERC20Balance` which takes the corresponding contract address as an argument. 
* To check that a share purchase can happen, the user needs to hold a sufficient amount of XCHF (or DSHS) but they also need to give a sufficient allowance to the Share Dispenser contract. This is checked using the `getERC20Available` function which takes two arguments, the contract address (DSHS or XCHF) as well as the potential buyer/seller.
* In order for the company to retrieve XCHF or DSHS from the Share Dispenser contract the `retrieveERC20` function is implemented. It expects three arguments, the contract address (DSHS or XCHF), the address to send the tokens to as well as the amount. This function can only be called by the contract owner.

**Permissions**

* The contract has an owner (ServiceHunter AG). This is handled through the corresponding open-zeppelin contract.
* The contract is pausible by the owner (using the corresponding open-zeppelin contract).
* The user can call the following functions `buyShares`, `sellShares`, `getERC20Balance`, `getERC20Available`, `getCumulatedPrice`, `getCumulatedBuyBackPrice`.
* All other functions are restricted to internal use or can only be called by the contract owner.

Users interact with the Share Dispenser only during transactions. It is therefore important that the process is transparent and the user is fully aware of the logic at the time of the transaction. However, the operator of the Share Dispenser reserves the right to unilaterally
change parameters or pause the contract at any time. The contract is not autonomous and is not intended to act in a DAO-like fashion. "Trust" in the system should therefore only refer to transactions (e.g. the contract is not a honeypot).

**Race Conditions**

Consider a situation where two users (Alice and Bob) both check the cumulated price for buying 10 shares roughly at the same time. Based on this Alice and Bob both give the corresponding XCHF allowance to the Share Dispenser contract. Let's assume Alice and Bob now both call the `buyShares` function roughly at the same time. If the transaction of Alice goes through first, the transaction of Bob will revert because the price for the same number of shares has increased in the meantime. 

A similar case can occur when selling shares. To protect the seller, along with the number of shares to sell a limit needs to be supplied. If the price moves below the limit after a transaction is broadcasted, it will revert.

Both of these cases can be handled in the front-end so that the user understands what has happened.