var ShareDispenser = artifacts.require("../contracts/ShareDispenser.sol");
var CryptoFranc = "0xb4272071ecadd69d933adcd19ca99fe80664fc08";
var DSHS = "TBD";
var UsageFee = "0x42f9c600a76bd9343da1536d203fa74fc570fc21";

module.exports = function (deployer) {
  deployer.deploy(ShareDispenser, CryptoFranc, DSHS, UsageFee)
};