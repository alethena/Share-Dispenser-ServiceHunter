/**
* MIT License with Automated License Fee Payments
*
* Copyright (c) 2019 Equility AG (alethena.com)
*
* Permission is hereby granted to any person obtaining a copy of this software
* and associated documentation files (the "Software"), to deal in the Software
* without restriction, including without limitation the rights to use, copy,
* modify, merge, publish, distribute, sublicense, and/or sell copies of the
* Software, and to permit persons to whom the Software is furnished to do so,
* subject to the following conditions:
*
* - The above copyright notice and this permission notice shall be included in
*   all copies or substantial portions of the Software.
* - All automated license fee payments integrated into this and related Software
*   are preserved.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/
pragma solidity 0.5.10;

import "../node_modules/openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../node_modules/openzeppelin-solidity/contracts/lifecycle/Pausable.sol";

/**
 * @title Alethena Share Dispenser for Draggable ServiceHunter Shares (DSHS)
 * @author Benjamin Rickenbacher, benjamin@alethena.com
 * @dev This contract uses the open-zeppelin library.
 *
 * This smart contract is intended to serve as a tool that ServiceHunter AG can use to
 * provide liquidity for their DSHS.
 *
 * The currency used for payment is the Crypto Franc XCHF (https://www.swisscryptotokens.ch/)
 * which makes it possible to quote DSHS prices directly in Swiss Francs.
 *
 * ServiceHunter AG can allocate a certain number of DSHS and (optionally) also some XCHF
 * to the Share Dispenser and defines a linear price dependency.
 **/

interface ERC20 {
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint tokens) external returns (bool success);
    function transferFrom(address from, address to, uint256 value) external returns (bool success);
    function totalShares() external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256 balance);
}


contract ShareDispenser is Ownable, Pausable {
    constructor(
        address initialXCHFContractAddress,
        address initialDSHSContractAddress,
        address initialusageFeeAddress,
        address initialBackendAddress
        ) public {

        require(initialXCHFContractAddress != address(0), "XCHF does not reside at address 0!");
        require(initialDSHSContractAddress != address(0), "DSHS does not reside at address 0!");
        require(initialusageFeeAddress != address(0), "Usage fee address cannot be 0!");

        XCHFContractAddress = initialXCHFContractAddress;
        DSHSContractAddress = initialDSHSContractAddress;
        usageFeeAddress = initialusageFeeAddress;
        backendAddress = initialBackendAddress;
    }

    /*
     * Fallback function to prevent accidentally sending Ether to the contract
     * It is still possible to force Ether into the contract as this cannot be prevented fully.
     * Sending Ether to this contract does not create any problems for the contract, but the Ether will be lost.
    */

    function () external payable {
        revert("This contract does not accept Ether.");
    }

    using SafeMath for uint256;

    // Variables

    address public XCHFContractAddress;     // Address where XCHF is deployed
    address public DSHSContractAddress;     // Address where DSHS is deployed
    address public usageFeeAddress;         // Address where usage fee is collected
    address public backendAddress;          // Address used by backend server (triggers buy/sell)

    uint256 public usageFeeBSP  = 90;       // 0.9% usage fee (10000 basis points = 100%)
    uint256 public minVolume = 1;          // Minimum number of shares to buy/sell

    uint256 public minPriceInXCHF = 300*10**18; // Minimum price
    uint256 public maxPriceInXCHF = 350*10**18; // Maximum price
    uint256 public initialNumberOfShares = 2000; //Price slope (TBD)

    bool public buyEnabled = true;
    bool public sellEnabled = true;

    // Events

    event XCHFContractAddressSet(address newXCHFContractAddress);
    event DSHSContractAddressSet(address newDSHSContractAddress);
    event UsageFeeAddressSet(address newUsageFeeAddress);

    event SharesPurchased(address indexed buyer, uint256 amount, uint256 price, uint256 nextPrice);
    event SharesSold(address indexed seller, uint256 amount, uint256 buyBackPrice, uint256 nextPrice);

    event TokensRetrieved(address contractAddress, address indexed to, uint256 amount);

    event UsageFeeSet(uint256 usageFee);
    event MinVolumeSet(uint256 minVolume);
    event MinPriceSet(uint256 minPrice);
    event MaxPriceSet(uint256 maxPrice);
    event InitialNumberOfSharesSet(uint256 initialNumberOfShares);

    event BuyStatusChanged(bool newStatus);
    event SellStatusChanged(bool newStatus);


    // Function for buying shares

    function buyShares(address buyer, uint256 numberOfSharesToBuy) public whenNotPaused() returns (bool) {

        // Check that buying is enabled
        require(buyEnabled, "Buying is currenty disabled");
        require(numberOfSharesToBuy >= minVolume, "Volume too low");

        // Check user is allowed to trigger buy
        require(msg.sender == buyer || msg.sender == backendAddress, "You do not have permission to trigger buying shares for someone else.");

        // Fetch the price (excluding the usage fee)
        uint256 sharesAvailable = getERC20Balance(DSHSContractAddress);
        uint256 price = getCumulatedPrice(numberOfSharesToBuy, sharesAvailable);

        // Check that there are enough shares available
        require(sharesAvailable >= numberOfSharesToBuy, "Not enough shares available");

       // Compute usage fee
        uint256 usageFee = price.mul(usageFeeBSP).div(10000);

        // Check that allowance is set XCHF balance is sufficient to cover price + usage fee
        require(getERC20Available(XCHFContractAddress, buyer) >= price.add(usageFee), "Payment not authorized or funds insufficient");

        // Instantiate contracts
        ERC20 DSHS = ERC20(DSHSContractAddress);
        ERC20 XCHF = ERC20(XCHFContractAddress);

        // Transfer usage fee and total price
        require(XCHF.transferFrom(buyer, usageFeeAddress, usageFee), "Usage fee transfer failed");
        require(XCHF.transferFrom(buyer, address(this), price), "XCHF payment failed");

        // Transfer the shares
        require(DSHS.transfer(buyer, numberOfSharesToBuy), "Share transfer failed");
        uint256 nextPrice = getCumulatedPrice(1, sharesAvailable.sub(numberOfSharesToBuy));
        emit SharesPurchased(buyer, numberOfSharesToBuy, price, nextPrice);
        return true;
    }

    // Function for selling shares

    function sellShares(address seller, uint256 numberOfSharesToSell, uint256 limitInXCHF) public whenNotPaused() returns (bool) {

        // Check that selling is enabled
        require(sellEnabled, "Selling is currenty disabled");
        require(numberOfSharesToSell >= minVolume, "Volume too low");

        // Check user is allowed to trigger sale;
        require(msg.sender == buyer || msg.sender == backendAddress, "You do not have permission to trigger selling shares for someone else.");

        uint256 XCHFAvailable = getERC20Balance(XCHFContractAddress);
        uint256 sharesAvailable = getERC20Balance(DSHSContractAddress);

        // The full price. The usage fee is deducted from this to obtain the seller's payout
        uint256 price = getCumulatedBuyBackPrice(numberOfSharesToSell, sharesAvailable);
        require(limitInXCHF <= price, "Price too low");

        // Check that XCHF reserve is sufficient
        require(XCHFAvailable >= price, "Reserves to small to buy back this amount of shares");

        // Check that seller has sufficient shares and allowance is set
        require(getERC20Available(DSHSContractAddress, seller) >= numberOfSharesToSell, "Seller doesn't have enough shares");

        // Instantiate contracts
        ERC20 DSHS = ERC20(DSHSContractAddress);
        ERC20 XCHF = ERC20(XCHFContractAddress);

        // Transfer the shares
        require(DSHS.transferFrom(seller, address(this), numberOfSharesToSell), "Share transfer failed");

        // Compute usage fee
        uint256 usageFee = price.mul(usageFeeBSP).div(10000);

        // Transfer usage fee and buyback price
        require(XCHF.transfer(usageFeeAddress, usageFee), "Usage fee transfer failed");
        require(XCHF.transfer(seller, price.sub(usageFee)), "XCHF payment failed");
        uint256 nextPrice = getCumulatedBuyBackPrice(1, sharesAvailable.add(numberOfSharesToSell));
        emit SharesSold(seller, numberOfSharesToSell, price, nextPrice);
        return true;
    }

    // Getters for ERC20 balances (for convenience)

    function getERC20Balance(address contractAddress) public view returns (uint256) {
        ERC20 contractInstance = ERC20(contractAddress);
        return contractInstance.balanceOf(address(this));
    }

    function getERC20Available(address contractAddress, address owner) public view returns (uint256) {
        ERC20 contractInstance = ERC20(contractAddress);
        uint256 allowed = contractInstance.allowance(owner, address(this));
        uint256 bal = contractInstance.balanceOf(owner);
        return (allowed <= bal) ? allowed : bal;
    }

    // Price getters

    function getCumulatedPrice(uint256 amount, uint256 supply) public view returns (uint256) {
        uint256 cumulatedPrice = 0;
        if (supply <= initialNumberOfShares) {
            uint256 first = initialNumberOfShares.add(1).sub(supply);
            uint256 last = first.add(amount).sub(1);
            cumulatedPrice = helper(first, last);
        } else if (supply.sub(amount) >= initialNumberOfShares) {
            cumulatedPrice = minPriceInXCHF.mul(amount);
        } else {
            cumulatedPrice = supply.sub(initialNumberOfShares).mul(minPriceInXCHF);
            uint256 first = 1;
            uint256 last = amount.sub(supply.sub(initialNumberOfShares));
            cumulatedPrice = cumulatedPrice.add(helper(first,last));
        }

        return cumulatedPrice;
    }

    function getCumulatedBuyBackPrice(uint256 amount, uint256 supply) public view returns (uint256) {
        return getCumulatedPrice(amount, supply.add(amount)); // For symmetry reasons
    }

    // Function to retrieve DSHS or XCHF from contract
    // This can also be used to retrieve any other ERC-20 token sent to the smart contract by accident

    function retrieveERC20(address contractAddress, address to, uint256 amount) public onlyOwner() returns(bool) {
        ERC20 contractInstance = ERC20(contractAddress);
        require(contractInstance.transfer(to, amount), "Transfer failed");
        emit TokensRetrieved(contractAddress, to, amount);
        return true;
    }

    // Setters for addresses

    function setXCHFContractAddress(address newXCHFContractAddress) public onlyOwner() {
        require(newXCHFContractAddress != address(0), "XCHF does not reside at address 0");
        XCHFContractAddress = newXCHFContractAddress;
        emit XCHFContractAddressSet(XCHFContractAddress);
    }

    function setDSHSContractAddress(address newDSHSContractAddress) public onlyOwner() {
        require(newDSHSContractAddress != address(0), "DSHS does not reside at address 0");
        DSHSContractAddress = newDSHSContractAddress;
        emit DSHSContractAddressSet(DSHSContractAddress);
    }

    function setUsageFeeAddress(address newUsageFeeAddress) public onlyOwner() {
        require(newUsageFeeAddress != address(0), "DSHS does not reside at address 0");
        usageFeeAddress = newUsageFeeAddress;
        emit UsageFeeAddressSet(usageFeeAddress);
    }

    function setBackendAddress(address newBackendAddress) public onlyOwner() {
        backendAddress = newBackendAddress;
    }

    // Setters for constants

    function setUsageFee(uint256 newUsageFeeInBSP) public onlyOwner() {
        require(newUsageFeeInBSP <= 10000, "Usage fee must be given in basis points");
        usageFeeBSP = newUsageFeeInBSP;
        emit UsageFeeSet(usageFeeBSP);
    }

    function setMinVolume(uint256 newMinVolume) public onlyOwner() {
        require(newMinVolume > 0, "Minimum volume can't be zero");
        minVolume = newMinVolume;
        emit MinVolumeSet(minVolume);
    }

    function setminPriceInXCHF(uint256 newMinPriceInRappen) public onlyOwner() {
        require(newMinPriceInRappen > 0, "Price must be positive number");
        minPriceInXCHF = newMinPriceInRappen.mul(10**16);
        require(minPriceInXCHF <= maxPriceInXCHF, "Minimum price cannot exceed maximum price");
        emit MinPriceSet(minPriceInXCHF);
    }

    function setmaxPriceInXCHF(uint256 newMaxPriceInRappen) public onlyOwner() {
        require(newMaxPriceInRappen > 0, "Price must be positive number");
        maxPriceInXCHF = newMaxPriceInRappen.mul(10**16);
        require(minPriceInXCHF <= maxPriceInXCHF, "Minimum price cannot exceed maximum price");
        emit MaxPriceSet(maxPriceInXCHF);
    }

    function setInitialNumberOfShares(uint256 newInitialNumberOfShares) public onlyOwner() {
        require(newInitialNumberOfShares > 0, "Initial number of shares must be positive");
        initialNumberOfShares = newInitialNumberOfShares;
        emit InitialNumberOfSharesSet(initialNumberOfShares);
    }

    // Enable buy and sell separately

    function buyStatus(bool newStatus) public onlyOwner() {
        buyEnabled = newStatus;
        emit BuyStatusChanged(newStatus);
    }

    function sellStatus(bool newStatus) public onlyOwner() {
        sellEnabled = newStatus;
        emit SellStatusChanged(newStatus);
    }

    // Helper functions

    function helper(uint256 first, uint256 last) internal view returns (uint256) {
        uint256 tempa = last.sub(first).add(1).mul(minPriceInXCHF);                                   // (l-m+1)*p_min
        uint256 tempb = maxPriceInXCHF.sub(minPriceInXCHF).div(initialNumberOfShares.sub(1)).div(2);  // (p_max-p_min)/(2(N-1))
        uint256 tempc = last.mul(last).add(first.mul(3)).sub(last).sub(first.mul(first)).sub(2);      // l*l+3*m-l-m*m-2)
        return tempb.mul(tempc).add(tempa);
    }

}