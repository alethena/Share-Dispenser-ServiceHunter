const BN = require('bn.js');
const AlethenaShares = artifacts.require('../contracts/ALEQ/AlethenaShares.sol');
const CryptoFranc = artifacts.require('../contracts/XCHF/CryptoFranc.sol');
const ShareDispenser = artifacts.require('../contracts/ShareDispenser.sol');


contract('ShareDispenser', (accounts) => {

    //Accounts used

    const Owner = accounts[0];
    const Seller = accounts[1];
    const Buyer = accounts[2];
    const Buyer2 = accounts[3];
    const conflictingBuyer1 = accounts[4];
    const conflictingBuyer2 = accounts[5];
    const treasury = accounts[6];
    const conflictingSeller1 = accounts[7];
    const conflictingSeller2 = accounts[8];

    const ALEQAmountToMint = new BN(127043, 10);

    let AlethenaSharesInstance;
    let ShareDispenserInstance;
    let XCHFInstance;

    before(async () => {
        AlethenaSharesInstance = await AlethenaShares.deployed();
        XCHFInstance = await CryptoFranc.deployed();
        ShareDispenserInstance = await ShareDispenser.deployed();
        console.log("AlethenaSharesInstance lives at: ", AlethenaSharesInstance.address);
        console.log("XCHFInstancee lives at: ", XCHFInstance.address);
        console.log("ShareDispenserInstance lives at: ", ShareDispenserInstance.address);
    });

    it('Mint ALEQ tokens', async () => {
        await AlethenaSharesInstance.setTotalShares(ALEQAmountToMint);
        await AlethenaSharesInstance.mint(ShareDispenserInstance.address, 10000, "Test");
        await AlethenaSharesInstance.mint(treasury, ALEQAmountToMint.sub(new BN(31000)), "Test");
        await AlethenaSharesInstance.mint(conflictingSeller1, 10000, "Test");
        await AlethenaSharesInstance.mint(conflictingSeller2, 10000, "Test");
        await AlethenaSharesInstance.mint(Seller, 1000, "Test");
    });

    it('Mint CXHF tokens', async () => {
        let mintAmount1 = new BN(10000, 10);
        let multiplier = new BN(10, 10);
        let decimals = new BN(18, 10);

        let mintBN = multiplier.pow(decimals).mul(mintAmount1);

        await XCHFInstance.mint(Buyer, mintBN);
        await XCHFInstance.mint(Buyer2, mintBN);
        await XCHFInstance.mint(conflictingBuyer1, mintBN);
        await XCHFInstance.mint(conflictingBuyer2, mintBN);
        await XCHFInstance.mint(ShareDispenserInstance.address, mintBN.mul(new BN(10000)));

    });

    it('Change SD parameters', async () => {
        const newUsageFee = new BN(236, 10);
        // const newSpread = new BN(9534, 10);

        const tx1 = await ShareDispenserInstance.setUsageFee(newUsageFee);
        // const tx2 = await ShareDispenserInstance.setSpread(newSpread);

        // Check events

        assert.equal(tx1.logs[0].event, "UsageFeeSet");
        assert.equal(tx1.logs[0].args.usageFee.toString(), newUsageFee.toString());
        // assert.equal(tx2.logs[0].event, "SpreadSet");
        // assert.equal(tx2.logs[0].args.spread.toString(), newSpread.toString());

        // Check effect

        const usageFeeAfter = await ShareDispenserInstance.usageFeeBSP();
        // const spreadAfter = await ShareDispenserInstance.spreadBSP();

        assert.equal(usageFeeAfter.toString(), newUsageFee.toString());
        // assert.equal(spreadAfter.toString(), newSpread.toString());

    });

    it('Set XCHF allowance', async () => {
        const numberOfSharesToBuy = new BN(234, 10);
        const supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);
        const totalPrice = await ShareDispenserInstance.getCumulatedPrice(numberOfSharesToBuy, supply);
        await XCHFInstance.approve(ShareDispenserInstance.address, totalPrice, {
            from: Buyer
        });
    })

    it('Buy shares', async () => {
        const numberOfSharesToBuy = new BN(234, 10);
        const supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);
        const totalPrice = await ShareDispenserInstance.getCumulatedPrice(numberOfSharesToBuy, supply);
        const usageFeeAddress = await ShareDispenserInstance.usageFeeAddress();

        const XCHFBalancePreBuyer = await XCHFInstance.balanceOf(Buyer);
        const XCHFBalancePreSD = await XCHFInstance.balanceOf(ShareDispenserInstance.address);
        const XCHFBalancePreFee = await XCHFInstance.balanceOf(usageFeeAddress);
        const ALEQBalancePreBuyer = await AlethenaSharesInstance.balanceOf(Buyer);
        const ALEQBalancePreSD = await AlethenaSharesInstance.balanceOf(ShareDispenserInstance.address);

        const usageFeeBSP = await ShareDispenserInstance.usageFeeBSP();
        const BSP = new BN(10000, 10);
        const usageFee = totalPrice.mul(usageFeeBSP).div(BSP);

        var tx = await ShareDispenserInstance.buyShares(numberOfSharesToBuy, {
            from: Buyer
        });

        const XCHFBalancePostBuyer = await XCHFInstance.balanceOf(Buyer);
        const XCHFBalancePostSD = await XCHFInstance.balanceOf(ShareDispenserInstance.address);
        const XCHFBalancePostFee = await XCHFInstance.balanceOf(usageFeeAddress);
        const ALEQBalancePostBuyer = await AlethenaSharesInstance.balanceOf(Buyer);
        const ALEQBalancePostSD = await AlethenaSharesInstance.balanceOf(ShareDispenserInstance.address);

        // Check balances

        assert.equal(XCHFBalancePreBuyer.sub(totalPrice).toString(), XCHFBalancePostBuyer.toString());
        assert.equal(ALEQBalancePreBuyer.add(numberOfSharesToBuy).toString(), ALEQBalancePostBuyer.toString());
        assert.equal(XCHFBalancePreSD.add(totalPrice).sub(usageFee).toString(), XCHFBalancePostSD.toString());
        assert.equal(ALEQBalancePreSD.sub(numberOfSharesToBuy).toString(), ALEQBalancePostSD.toString());
        assert.equal(XCHFBalancePostFee.sub(XCHFBalancePreFee).toString(), usageFee.toString());

        // Check events

        assert.equal(tx.logs[0].event, "SharesPurchased");
        assert.equal(tx.logs[0].args.buyer, Buyer);
        assert.equal(tx.logs[0].args.amount.toString(), numberOfSharesToBuy.toString());
        assert.equal(tx.logs[0].args.totalPrice.toString(), totalPrice.toString());
        console.log("Next price:", tx.logs[0].args.nextPrice.toString());

    });

    it('Set ALEQ allowance', async () => {
        const numberOfSharesToSell = new BN(234, 10);
        await AlethenaSharesInstance.approve(ShareDispenserInstance.address, numberOfSharesToSell, {
            from: Buyer
        });
    })

    it('Sell shares', async () => {
        const numberOfSharesToSell = new BN(234, 10);
        const supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);
        const buybackPrice = await ShareDispenserInstance.getCumulatedBuyBackPrice(numberOfSharesToSell, supply);
        const usageFeeAddress = await ShareDispenserInstance.usageFeeAddress();

        const XCHFBalancePreBuyer = await XCHFInstance.balanceOf(Buyer);
        const XCHFBalancePreSD = await XCHFInstance.balanceOf(ShareDispenserInstance.address);
        const XCHFBalancePreFee = await XCHFInstance.balanceOf(usageFeeAddress);
        const ALEQBalancePreBuyer = await AlethenaSharesInstance.balanceOf(Buyer);
        const ALEQBalancePreSD = await AlethenaSharesInstance.balanceOf(ShareDispenserInstance.address);

        const usageFeeBSP = await ShareDispenserInstance.usageFeeBSP();
        const BSP = new BN(10000, 10);
        const usageFee = buybackPrice.mul(usageFeeBSP).div(BSP);

        var tx = await ShareDispenserInstance.sellShares(numberOfSharesToSell, buybackPrice, {
            from: Buyer
        });

        const XCHFBalancePostBuyer = await XCHFInstance.balanceOf(Buyer);
        const XCHFBalancePostSD = await XCHFInstance.balanceOf(ShareDispenserInstance.address);
        const XCHFBalancePostFee = await XCHFInstance.balanceOf(usageFeeAddress);
        const ALEQBalancePostBuyer = await AlethenaSharesInstance.balanceOf(Buyer);
        const ALEQBalancePostSD = await AlethenaSharesInstance.balanceOf(ShareDispenserInstance.address);

        // Check balances

        assert.equal(XCHFBalancePreBuyer.add(buybackPrice).sub(usageFee).toString(), XCHFBalancePostBuyer.toString());
        assert.equal(ALEQBalancePreBuyer.sub(numberOfSharesToSell).toString(), ALEQBalancePostBuyer.toString());
        assert.equal(XCHFBalancePreSD.sub(buybackPrice).toString(), XCHFBalancePostSD.toString());
        assert.equal(ALEQBalancePreSD.add(numberOfSharesToSell).toString(), ALEQBalancePostSD.toString());
        assert.equal(XCHFBalancePostFee.sub(XCHFBalancePreFee).toString(), usageFee.toString());

        // Check events

        assert.equal(tx.logs[0].event, "SharesSold");
        assert.equal(tx.logs[0].args.seller, Buyer);
        assert.equal(tx.logs[0].args.amount.toString(), numberOfSharesToSell.toString());
        assert.equal(tx.logs[0].args.buyBackPrice.toString(), buybackPrice.toString());
        console.log(tx.logs[0].args.nextPrice.toString());

    });

    // Negative test for all setters

    it('Only owner can use setter functions', async () => {
        const newAddress = "0x109A3f712bA34c1f93297702F2Cd06e799b8f23c";

        await shouldRevert(ShareDispenserInstance.setXCHFContractAddress(newAddress, {
            from: Buyer2
        }));
        await shouldRevert(ShareDispenserInstance.setALEQContractAddress(newAddress, {
            from: Buyer2
        }));
        await shouldRevert(ShareDispenserInstance.setUsageFeeAddress(newAddress, {
            from: Buyer2
        }));

        const newValue = new BN(123, 10);

        await shouldRevert(ShareDispenserInstance.setUsageFee(newValue, {
            from: Buyer2
        }));
  
        await shouldRevert(ShareDispenserInstance.setMinVolume(newValue, {
            from: Buyer2
        }));

        await shouldRevert(ShareDispenserInstance.setminPriceInXCHF(newValue, {
            from: Buyer2
        }));

        await shouldRevert(ShareDispenserInstance.setmaxPriceInXCHF(newValue, {
            from: Buyer2
        }));

        await shouldRevert(ShareDispenserInstance.setInitialNumberOfShares(newValue, {
            from: Buyer2
        }));

        const newStatus = true;

        await shouldRevert(ShareDispenserInstance.buyStatus(newStatus, {
            from: Buyer2
        }));
        await shouldRevert(ShareDispenserInstance.sellStatus(newStatus, {
            from: Buyer2
        }));
    })

    // Unit tests for pricing function

    it('Unit tests for pricing formula', async () => {
        // Due to rounding errors we have to tollerate a deviation roughly in the order of inititalNumberOfShares
        // This is ok as XCHF has 10**18 decimals

        // Check that price of first share is pMin

        const initialNumberOfShares = await ShareDispenserInstance.initialNumberOfShares();
        const pMin = await ShareDispenserInstance.minPriceInXCHF();
        const pMax = await ShareDispenserInstance.maxPriceInXCHF();

        // To run test below make function public in Solidity !!

        // let price1 = await ShareDispenserInstance.helper(1, 1);
        // assert(price1.lte(pMin.add(initialNumberOfShares)));
        // assert(price1.gte(pMin.sub(initialNumberOfShares)));

        price1 = await ShareDispenserInstance.getCumulatedPrice(1, initialNumberOfShares);
        assert(price1.lte(pMin.add(initialNumberOfShares)));
        assert(price1.gte(pMin.sub(initialNumberOfShares)));

        // Check that price of last share is pMax

        // To run test below make function public in Solidity !!

        // let price2 = await ShareDispenserInstance.helper(initialNumberOfShares, initialNumberOfShares);
        // assert(price2.lte(pMax.add(initialNumberOfShares)));
        // assert(price2.gte(pMax.sub(initialNumberOfShares)));

        price2 = await ShareDispenserInstance.getCumulatedPrice(1, 1);
        assert(price2.lte(pMax.add(initialNumberOfShares)));
        assert(price2.gte(pMax.sub(initialNumberOfShares)));

        // Check overflow is priced at pMin

        let price3 = await ShareDispenserInstance.getCumulatedPrice(1, initialNumberOfShares.add(new BN(74324, 10)));
        assert(price3.lte(pMin.add(initialNumberOfShares)));
        assert(price3.gte(pMin.sub(initialNumberOfShares)));

        price3 = await ShareDispenserInstance.getCumulatedPrice(10, initialNumberOfShares.add(new BN(10, 10)));
        assert(price3.div(new BN(10, 10)).lte(pMin.add(initialNumberOfShares)));
        assert(price3.div(new BN(10, 10)).gte(pMin.sub(initialNumberOfShares)));

        // Check "kink" case
        const price4 = await ShareDispenserInstance.getCumulatedPrice(17, initialNumberOfShares.add(new BN(10, 10)));
        const price5 = await ShareDispenserInstance.getCumulatedPrice(7, initialNumberOfShares);
        const price6 = price4.sub(price3);
        assert(price6.lte(price5.add(initialNumberOfShares)));
        assert(price6.gte(price5.sub(initialNumberOfShares)));
    })


    // NEGATIVE TESTS:


    it('Negative test (buy): Balance too low', async () => {
        const numberOfSharesToBuy = new BN(2034, 10);
        const XCHFBalancePreBuyer = await XCHFInstance.balanceOf(Buyer2);
        const supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);
        const totalPrice = await ShareDispenserInstance.getCumulatedPrice(numberOfSharesToBuy, supply);

        await AlethenaSharesInstance.approve(ShareDispenserInstance.address, totalPrice, {
            from: Buyer2
        });

        assert(XCHFBalancePreBuyer.lt(totalPrice));

        const e = await shouldRevert(ShareDispenserInstance.buyShares(numberOfSharesToBuy, {
            from: Buyer
        }));

        assert(e.message.search("Payment not authorized or funds insufficient") >= 0);
    });

    it('Negative test (buy): Allowance too low', async () => {
        const numberOfSharesToBuy = new BN(34, 10);
        const XCHFBalancePreBuyer = await XCHFInstance.balanceOf(Buyer2);
        const supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);
        const totalPrice = await ShareDispenserInstance.getCumulatedPrice(numberOfSharesToBuy, supply);

        assert(XCHFBalancePreBuyer.gte(totalPrice));

        await AlethenaSharesInstance.approve(ShareDispenserInstance.address, totalPrice.sub(new BN(1, 10)), {
            from: Buyer2
        });

        const e = await shouldRevert(ShareDispenserInstance.buyShares(numberOfSharesToBuy, {
            from: Buyer2
        }));

        // console.log(e);
        // assert(e.message.search("Payment not authorized or funds insufficient") >= 0);
    });

    it('Negative test (sell): Balance too low', async () => {
        const numberOfSharesToSell = new BN(1034, 10);
        const ALEQBalancePreSeller = await AlethenaSharesInstance.balanceOf(Seller);
        const supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);
        const totalPrice = await ShareDispenserInstance.getCumulatedBuyBackPrice(numberOfSharesToSell, supply);

        await XCHFInstance.approve(ShareDispenserInstance.address, numberOfSharesToSell, {
            from: Seller
        });

        assert(ALEQBalancePreSeller.lt(numberOfSharesToSell));

        const e = await shouldRevert(ShareDispenserInstance.sellShares(numberOfSharesToSell, totalPrice, {
            from: Seller
        }));

        assert(e.message.search("Seller doesn't have enough shares") >= 0);
    });

    it('Negative test (sell): Allowance too low', async () => {
        const numberOfSharesToSell = new BN(134, 10);
        const ALEQBalancePreSeller = await AlethenaSharesInstance.balanceOf(Seller);
        const supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);
        const totalPrice = await ShareDispenserInstance.getCumulatedBuyBackPrice(numberOfSharesToSell, supply);

        await XCHFInstance.approve(ShareDispenserInstance.address, numberOfSharesToSell.sub(new BN(5, 10)), {
            from: Seller
        });

        assert(ALEQBalancePreSeller.gte(numberOfSharesToSell));

        const e = await shouldRevert(ShareDispenserInstance.sellShares(numberOfSharesToSell, totalPrice, {
            from: Seller
        }));

        assert(e.message.search("Seller doesn't have enough shares") >= 0);
    });

    it('Set zero spread and fees', async () => {
        const newUsageFee = new BN(0, 10);
        // const newSpread = new BN(10000, 10);

        await ShareDispenserInstance.setUsageFee(newUsageFee);
        // await ShareDispenserInstance.setSpread(newSpread);
    });

    it('Buy and immediate resale at zero usage fee and spread only costs Ethereum TX fees', async () => {
        const numberOfSharesToBuy = new BN(23, 10);
        const numberOfSharesToSell = new BN(23, 10);

        let supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);
        const totalPrice = await ShareDispenserInstance.getCumulatedPrice(numberOfSharesToBuy, supply);

        const XCHFBalancePreBuyer = await XCHFInstance.balanceOf(Buyer2);
        const XCHFBalancePreSD = await XCHFInstance.balanceOf(ShareDispenserInstance.address);
        const ALEQBalancePreBuyer = await AlethenaSharesInstance.balanceOf(Buyer2);
        const ALEQBalancePreSD = await AlethenaSharesInstance.balanceOf(ShareDispenserInstance.address);

        await XCHFInstance.approve(ShareDispenserInstance.address, totalPrice, {
            from: Buyer2
        });

        await ShareDispenserInstance.buyShares(numberOfSharesToBuy, {
            from: Buyer2
        });

        supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);
        const buybackPrice = await ShareDispenserInstance.getCumulatedBuyBackPrice(numberOfSharesToSell, supply);

        await AlethenaSharesInstance.approve(ShareDispenserInstance.address, numberOfSharesToSell, {
            from: Buyer2
        });

        await ShareDispenserInstance.sellShares(numberOfSharesToSell, buybackPrice, {
            from: Buyer2
        });

        const XCHFBalancePostBuyer = await XCHFInstance.balanceOf(Buyer2);
        const XCHFBalancePostSD = await XCHFInstance.balanceOf(ShareDispenserInstance.address);
        const ALEQBalancePostBuyer = await AlethenaSharesInstance.balanceOf(Buyer2);
        const ALEQBalancePostSD = await AlethenaSharesInstance.balanceOf(ShareDispenserInstance.address);

        assert.equal(XCHFBalancePreBuyer.toString(), XCHFBalancePostBuyer.toString());
        assert.equal(ALEQBalancePreBuyer.toString(), ALEQBalancePostBuyer.toString());
        assert.equal(XCHFBalancePreSD.toString(), XCHFBalancePostSD.toString());
        assert.equal(ALEQBalancePreSD.toString(), ALEQBalancePostSD.toString());

    });

    it('Collision (i.e. second transaction cancelled (buy)', async () => {
        const numberOfSharesToBuy1 = new BN(2, 10);
        const numberOfSharesToBuy2 = new BN(23, 10);

        let supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);

        const totalPrice1 = await ShareDispenserInstance.getCumulatedPrice(numberOfSharesToBuy1, supply);
        const totalPrice2 = await ShareDispenserInstance.getCumulatedPrice(numberOfSharesToBuy2, supply);

        await XCHFInstance.approve(ShareDispenserInstance.address, totalPrice1, {
            from: conflictingBuyer1
        });

        await XCHFInstance.approve(ShareDispenserInstance.address, totalPrice2, {
            from: conflictingBuyer2
        });

        await ShareDispenserInstance.buyShares(numberOfSharesToBuy1, {
            from: conflictingBuyer1
        });

        await shouldRevert(ShareDispenserInstance.buyShares(numberOfSharesToBuy2, {
            from: conflictingBuyer2
        }));

    });

    it('Collision (i.e. second transaction cancelled (sell)', async () => {
        const numberOfSharesToSell1 = new BN(1, 10);
        const numberOfSharesToSell2 = new BN(23, 10);

        let supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);
        const buyBackPrice1 = await ShareDispenserInstance.getCumulatedBuyBackPrice(numberOfSharesToSell1, supply);
        const buyBackPrice2 = await ShareDispenserInstance.getCumulatedBuyBackPrice(numberOfSharesToSell2, supply);

        await AlethenaSharesInstance.approve(ShareDispenserInstance.address, numberOfSharesToSell1, {
            from: conflictingSeller1
        });

        await AlethenaSharesInstance.approve(ShareDispenserInstance.address, numberOfSharesToSell2, {
            from: conflictingSeller2
        });

        await ShareDispenserInstance.sellShares(numberOfSharesToSell1, buyBackPrice1, {
            from: conflictingSeller1
        });

        const e = await shouldRevert(ShareDispenserInstance.sellShares(numberOfSharesToSell2, buyBackPrice2, {
            from: conflictingSeller2
        }));
        assert(e.message.search('Price too low') >= 0);
    });

    // Test all the setters

    it('Setters work correctly', async () => {

        const newXCHFContractAddress = "0xEA674fdDe714fd979de3EdF0F56AA9716B898ec8";
        const tx1 = await ShareDispenserInstance.setXCHFContractAddress(newXCHFContractAddress);
        const XCHFContractAddress = await ShareDispenserInstance.XCHFContractAddress();
        assert.equal(newXCHFContractAddress, XCHFContractAddress);
        assert.equal("XCHFContractAddressSet", tx1.logs[0].event);
        assert.equal(newXCHFContractAddress, tx1.logs[0].args.newXCHFContractAddress);

        const newALEQContractAddress = "0xEA674fdDe714fd979de3EdF0F56AA9716B898ec8";
        const tx2 = await ShareDispenserInstance.setALEQContractAddress(newALEQContractAddress);
        const ALEQContractAddress = await ShareDispenserInstance.ALEQContractAddress();
        assert.equal(newALEQContractAddress, ALEQContractAddress);
        assert.equal("ALEQContractAddressSet", tx2.logs[0].event);
        assert.equal(newALEQContractAddress, tx2.logs[0].args.newALEQContractAddress);

        const newUsageFeeAddress = "0xEA674fdDe714fd979de3EdF0F56AA9716B898ec8";
        const tx3 = await ShareDispenserInstance.setUsageFeeAddress(newUsageFeeAddress);
        const UsageFeeAddress = await ShareDispenserInstance.usageFeeAddress();
        assert.equal(newUsageFeeAddress, UsageFeeAddress);
        assert.equal("UsageFeeAddressSet", tx3.logs[0].event);
        assert.equal(newUsageFeeAddress, tx3.logs[0].args.newUsageFeeAddress);

        const newValue = new BN(123, 10);

        const tx4 = await ShareDispenserInstance.setUsageFee(newValue);
        const usageFee = await ShareDispenserInstance.usageFeeBSP();
        assert.equal(newValue.toString(), usageFee.toString());
        assert.equal("UsageFeeSet", tx4.logs[0].event);
        assert.equal(newValue.toString(), tx4.logs[0].args.usageFee.toString());

        // const tx5 = await ShareDispenserInstance.setSpread(newValue);
        // const spreadBSP = await ShareDispenserInstance.spreadBSP();
        // assert.equal(newValue.toString(), spreadBSP.toString());
        // assert.equal("SpreadSet", tx5.logs[0].event);
        // assert.equal(newValue.toString(), tx5.logs[0].args.spread.toString());

        const tx6 = await ShareDispenserInstance.setMinVolume(newValue);
        const minVolume = await ShareDispenserInstance.minVolume();
        assert.equal(newValue.toString(), minVolume.toString());
        assert.equal("MinVolumeSet", tx6.logs[0].event);
        assert.equal(newValue.toString(), tx6.logs[0].args.minVolume.toString());

        // Still need to expand tests here...

        // await shouldRevert(ShareDispenserInstance.setMinVolume(newValue, {
        //     from: Buyer2
        // }));

        // await shouldRevert(ShareDispenserInstance.setminPriceInXCHF(newValue, {
        //     from: Buyer2
        // }));
        // await shouldRevert(ShareDispenserInstance.setmaxPriceInXCHF(newValue, {
        //     from: Buyer2
        // }));
        // await shouldRevert(ShareDispenserInstance.setInitialNumberOfShares(newValue, {
        //     from: Buyer2
        // }));

        // const newStatus = true;

        // await shouldRevert(ShareDispenserInstance.buyStatus(newStatus, {
        //     from: Buyer2
        // }));
        // await shouldRevert(ShareDispenserInstance.sellStatus(newStatus, {
        //     from: Buyer2
        // }));
    })

    it('Minimum volume is correctly enforced', async () => {

        const numberOfSharesToBuy = new BN(2, 10);
        const numberOfSharesToSell = new BN(2, 10);
        let supply = await ShareDispenserInstance.getERC20Balance(AlethenaSharesInstance.address);
        const buyBackPrice = await ShareDispenserInstance.getCumulatedBuyBackPrice(numberOfSharesToSell, supply);

        const e1 = await shouldRevert(ShareDispenserInstance.buyShares(numberOfSharesToBuy, {
            from: conflictingBuyer1
        }));
        assert(e1.message.search('Volume too low') >= 0);

        const e2 = await shouldRevert(ShareDispenserInstance.sellShares(numberOfSharesToSell, buyBackPrice, {
            from: conflictingSeller1
        }));
        assert(e2.message.search('Volume too low') >= 0);
    })

    // it('Tokens can be retrieved from contract', async () => {
    //     // TBD
    // })
});


// Used to check that EVM reverts when we expect it to
// Error is returned so we can check that it reverted for the right reason

async function shouldRevert(promise) {
    try {
        await promise;
    } catch (error) {
        // console.log(error);
        const revert = error.message.search('revert') >= 0;
        assert(
            revert,
            'Expected throw, got \'' + error + '\' instead',
        );
        return (error);
    }
    assert.fail('Expected throw not received');
}