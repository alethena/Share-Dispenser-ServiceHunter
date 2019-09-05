var AlethenaShares = artifacts.require("../contracts/ALEQ/AlethenaShares.sol");
var ShareDispenser = artifacts.require("../contracts/ShareDispenser.sol");
var CryptoFranc = artifacts.require("../contracts/XCHF/CryptoFranc.sol");

// For productive deployment, deploy only share dispenser

// module.exports = function (deployer) {
//   deployer.deploy(AlethenaShares).then(() => { return deployer.deploy(CryptoFranc, 'Test XCHF', 0) }).then(
//     () => { return deployer.deploy(ShareDispenser, CryptoFranc.address, AlethenaShares.address, "0xaF897e6DEE7d36130a3103D0E9B2299b5199F338") });
// };


module.exports = function (deployer) {
  deployer.deploy(ShareDispenser, "0xb4272071ecadd69d933adcd19ca99fe80664fc08", "0xf40c5e190a608b6f8c0bf2b38c9506b327941402", "0x42f9c600a76bd9343da1536d203fa74fc570fc21")
};