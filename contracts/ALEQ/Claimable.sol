pragma solidity ^0.5.0;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./ERC20Basic.sol";

/**
 * @title Claimable
 * In case of tokens that represent real-world assets such as shares of a company, one needs a way
 * to handle lost private keys. With physical certificates, courts can declare share certificates as
 * invalid so the company can issue replacements. Here, we want a solution that does not depend on 
 * third parties to resolve such cases. Instead, when someone has lost a private key, he can use the
 * declareLost function to post a deposit and claim that the shares assigned to a specific address are
 * lost. To prevent front running, a commit reveal scheme is used. If he actually is the owner of the shares,
 * he needs to wait for a certain period and can then reclaim the lost shares as well as the deposit. 
 * If he is an attacker trying to claim shares belonging to someone else, he risks losing the deposit 
 * as it can be claimed at anytime by the rightful owner.
 * Furthermore, the company itself can delete claims at any time and take the deposit. So in order to
 * use this functionality, one needs to trust the company to do the right thing and to handle potential
 * disputes responsibly. If you do not trust the company to do so, don't lose your private keys. :)
 */
contract Claimable is ERC20Basic, Ownable {

    using SafeMath for uint256;

    struct Claim {
        address payable claimant; // the person who created the claim
        uint256 collateral; // the amount of wei deposited
        uint256 timestamp;  // the timestamp of the block in which the claim was made
    }

    struct PreClaim {
        bytes32 msghash; // the hash of nonce + address to be claimed
        uint256 timestamp;  // the timestamp of the block in which the preclaim was made
    }

    /** @param collateralRate Sets the collateral needed per share to file a claim */
    uint256 public collateralRate = 5*10**15 wei;

    uint256 public claimPeriod = 60*60*24*180; // In seconds ;
    uint256 public preClaimPeriod = 60*60*24; // In seconds ;

    mapping(address => Claim) public claims; // there can be at most one claim per address, here address is claimed address
    mapping(address => PreClaim) public preClaims; // there can be at most one preclaim per address, here address is claimer


    function setClaimParameters(uint256 _collateralRateInWei, uint256 _claimPeriodInDays) public onlyOwner() {
        uint256 claimPeriodInSeconds = _claimPeriodInDays*60*60*24;
        require(_collateralRateInWei > 0);
        require(_claimPeriodInDays > 90); // must be at least 90 days
        collateralRate = _collateralRateInWei;
        claimPeriod = claimPeriodInSeconds;
        emit ClaimParametersChanged(collateralRate, claimPeriod);
    }

    event ClaimMade(address indexed _lostAddress, address indexed _claimant, uint256 _balance);
    event ClaimPrepared(address indexed _claimer);
    event ClaimCleared(address indexed _lostAddress, uint256 collateral);
    event ClaimDeleted(address indexed _lostAddress, address indexed _claimant, uint256 collateral);
    event ClaimResolved(address indexed _lostAddress, address indexed _claimant, uint256 collateral);
    event ClaimParametersChanged(uint256 _collateralRate, uint256  _claimPeriodInDays); 
 
  
  /** Anyone can declare that the private key to a certain address was lost by calling declareLost
    * providing a deposit/collateral. There are three possibilities of what can happen with the claim:
    * 1) The claim period expires and the claimant can get the deposit and the shares back by calling resolveClaim
    * 2) The "lost" private key is used at any time to call clearClaim. In that case, the claim is deleted and
    *    the deposit sent to the shareholder (the owner of the private key). It is recommended to call resolveClaim
    *    whenever someone transfers funds to let claims be resolved automatically when the "lost" private key is
    *    used again.
    * 3) The owner deletes the claim and assigns the deposit to the claimant. This is intended to be used to resolve
    *    disputes. Generally, using this function implies that you have to trust the issuer of the tokens to handle 
    *    the situation well. As a rule of thumb, the contract owner should assume the owner of the lost address to be the
    *    rightful owner of the deposit. 
    * It is highly recommended that the owner observes the claims made and informs the owners of the claimed addresses
    * whenever a claim is made for their address (this of course is only possible if they are known to the owner, e.g.
    * through a shareholder register).
    * To prevent frontrunning attacks, a claim can only be made if the information revealed when calling "declareLost" 
    * was previously commited using the "prepareClaim" function. 
    */

    function prepareClaim(bytes32 _hashedpackage) public{
        preClaims[msg.sender] = PreClaim({ 
            msghash: _hashedpackage,
            timestamp: block.timestamp
        });
        emit ClaimPrepared(msg.sender);
    }

    function validateClaim(address _lostAddress, bytes32 _nonce) private view returns (bool){
        PreClaim memory preClaim = preClaims[msg.sender];
        require(preClaim.msghash != 0);
        require(preClaim.timestamp + preClaimPeriod <= block.timestamp);
        require(preClaim.timestamp + 2*preClaimPeriod >= block.timestamp);
        return preClaim.msghash == keccak256(abi.encodePacked(_nonce, msg.sender, _lostAddress));
    }

    function declareLost(address _lostAddress, bytes32 _nonce) public payable{
        uint256 balance = balanceOf(_lostAddress);
        require(balance > 0);
        require(msg.value >= balance.mul(collateralRate));
        require(claims[_lostAddress].collateral == 0);
        require(validateClaim(_lostAddress, _nonce));

        claims[_lostAddress] = Claim({
            claimant: msg.sender,
            collateral: msg.value,
            timestamp: block.timestamp
        });
        delete preClaims[msg.sender];
        emit ClaimMade(_lostAddress, msg.sender, balance);
    }

    function getClaimant(address _lostAddress) public view returns (address){
        return claims[_lostAddress].claimant;
    }

    function getCollateral(address _lostAddress) public view returns (uint256){
        return claims[_lostAddress].collateral;
    }

    function getTimeStamp(address _lostAddress) public view returns (uint256){
        return claims[_lostAddress].timestamp;
    }

    function getPreClaimTimeStamp(address _claimerAddress) public view returns (uint256){
        return preClaims[_claimerAddress].timestamp;
    }

    function getMsgHash(address _claimerAddress) public view returns (bytes32){
        return preClaims[_claimerAddress].msghash;
    }

    /**
     * @dev Clears a claim after the key has been found again and assigns the collateral to the "lost" address.
     */
    function clearClaim() public returns (uint256){
        uint256 collateral = claims[msg.sender].collateral;
        if (collateral != 0){
            delete claims[msg.sender];
            msg.sender.transfer(collateral);
            emit ClaimCleared(msg.sender, collateral);
            return collateral;
        } else {
            return 0;
        }
    }
    
   /** 
    * @dev This function is used to resolve a claim.
    * @dev After waiting period, the tokens on the lost address and collateral can be transferred.
   */
    function resolveClaim(address _lostAddress) public returns (uint256){
        Claim memory claim = claims[_lostAddress];
        require(claim.collateral != 0, "No claim found");
        require(claim.claimant == msg.sender);
        require(claim.timestamp + claimPeriod <= block.timestamp); 
        address payable claimant = claim.claimant;
        delete claims[_lostAddress];
        claimant.transfer(claim.collateral);
        internalTransfer(_lostAddress, claimant, balanceOf(_lostAddress));
        emit ClaimResolved(_lostAddress, claimant, claim.collateral);
        return claim.collateral;
    }

    function internalTransfer(address _from, address _to, uint256 _value) internal;

     /** @dev This function is to be executed by the owner only in case a dispute needs to be resolved manually. */
    function deleteClaim(address _lostAddress) public onlyOwner(){
        Claim memory claim = claims[_lostAddress];
        require(claim.collateral != 0, "No claim found");
        delete claims[_lostAddress];
        claim.claimant.transfer(claim.collateral);
        emit ClaimDeleted(_lostAddress, claim.claimant, claim.collateral);
    }

}