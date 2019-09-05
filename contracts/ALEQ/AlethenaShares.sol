pragma solidity ^0.5.0;

import "./ERC20Basic.sol";
import "./SafeMath.sol";
import "./ERC20.sol";
import "./Claimable.sol";


/**
 * @title Alethena Shares
 * @author Benjamin Rickenbacher, benjamin@alethena.com
 * @author Luzius Meisser, luzius@meissereconomics.com
 * @dev These tokens are based on the ERC20 standard and the open-zeppelin library.
 *
 * These tokens are uncertified alethena shares (Wertrechte according to the Swiss code of obligations),
 * with this smart contract serving as onwership registry (Wertrechtebuch), but not as shareholder
 * registry, which is kept separate and run by the company. This is equivalent to the traditional system
 * of having physical share certificates kept at home by the shareholders and a shareholder registry run by
 * the company. Just like with physical certificates, the owners of the tokens are the owners of the shares.
 * However, in order to exercise their rights (for example receive a dividend), shareholders must register
 * with the company. For example, in case the company pays out a dividend to a previous shareholder because
 * the current shareholder did not register, the company cannot be held liable for paying the dividend to
 * the "wrong" shareholder. In relation to the company, only the registered shareholders count as such.
 * Registration requires setting up an account with ledgy.com providing your name and address and proving
 * ownership over your addresses.
 * @notice The main addition is a functionality that allows the user to claim that the key for a certain address is lost.
 * @notice In order to prevent malicious attempts, a collateral needs to be posted.
 * @notice The contract owner can delete claims in case of disputes.
 *
 * https://github.com/ethereum/EIPs/issues/20
 * Based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract AlethenaShares is ERC20, Claimable {

    string public constant name = "Alethena Equity";
    string public constant symbol = "ALEQ";
    uint8 public constant decimals = 0; // legally, shares are not divisible

    using SafeMath for uint256;

      /** URL where the source code as well as the terms and conditions can be found. */
    string public constant termsAndConditions = "shares.alethena.com";

    mapping(address => uint256) balances;
    uint256 totalSupply_;        // total number of tokenized shares, sum of all balances
    uint256 totalShares_ = 1397188; // total number of outstanding shares, maybe not all tokenized

    event Mint(address indexed shareholder, uint256 amount, string message);
    event Unmint(uint256 amount, string message);

  /** @dev Total number of tokens in existence */
    function totalSupply() public view returns (uint256) {
        return totalSupply_;
    }
        
  /** @dev Total number of shares in existence, not necessarily all represented by a token. 
    * @dev This could be useful to calculate the total market cap.
    */
    function totalShares() public view returns (uint256) {
        return totalShares_;
    }

    function setTotalShares(uint256 _newTotalShares) public onlyOwner() {
        require(_newTotalShares >= totalSupply());
        totalShares_ = _newTotalShares;
    }

  /** Increases the number of the tokenized shares. If the shares are newly issued, the share total also needs to be increased. */
    function mint(address shareholder, uint256 _amount, string memory _message) public onlyOwner() {
        require(_amount > 0);
        require(totalSupply_.add(_amount) <= totalShares_);
        balances[shareholder] = balances[shareholder].add(_amount);
        totalSupply_ = totalSupply_ + _amount;
        emit Mint(shareholder, _amount, _message);
    }

/** Decrease the number of the tokenized shares. There are two use-cases for this function:
 *  1) a capital decrease with a destruction of the shares, in which case the law requires that the
 *     destroyed shares are currently owned by the company.
 *  2) a shareholder wants to take shares offline. This can only happen with the agreement of the 
 *     the company. To do so, the shares must be transferred to the company first, the company call
 *     this function and then assigning the untokenized shares back to the shareholder in whatever
 *     way the new form (e.g. printed certificate) of the shares requires.
 */
    function unmint(uint256 _amount, string memory _message) public onlyOwner() {
        require(_amount > 0);
        require(_amount <= balanceOf(owner));
        balances[owner] = balances[owner].sub(_amount);
        totalSupply_ = totalSupply_ - _amount;
        emit Unmint(_amount, _message);
    }

  /** This contract is pausible.  */
    bool public isPaused = false;

  /** @dev Function to set pause.
   *  This could for example be used in case of a fork of the network, in which case all
   *  "wrong" forked contracts should be paused in their respective fork. Deciding which
   *  fork is the "right" one is up to the owner of the contract.
   */
    function pause(bool _pause, string memory _message, address _newAddress, uint256 _fromBlock) public onlyOwner() {
        isPaused = _pause;
        emit Pause(_pause, _message, _newAddress, _fromBlock);
    }

    event Pause(bool paused, string message, address newAddress, uint256 fromBlock);

//////////////////////////////////////////////////////////////////////////////////////////////////////////////
/** 
The next section contains standard ERC20 routines.
Main change: Transfer functions have an additional post function which resolves claims if applicable.
 */
//////////////////////////////////////////////////////////////////////////////////////////////////////////////

  /**
  * @dev Transfer token for a specified address
  * @param _to The address to transfer to.
  * @param _value The amount to be transferred.
  */
    function transfer(address _to, uint256 _value) public returns (bool) {
        clearClaim();
        internalTransfer(msg.sender, _to, _value);
        return true;
    }

    function internalTransfer(address _from, address _to, uint256 _value) internal {
        require(!isPaused);
        require(_to != address(0));
        require(_value <= balances[_from]);
        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(_from, _to, _value);
    }

  /**
  * @dev Gets the balance of the specified address.
  * @param _owner The address to query the the balance of.
  * @return An uint256 representing the amount owned by the passed address.
  */
    function balanceOf(address _owner) public view returns (uint256) {
        return balances[_owner];
    }

    mapping (address => mapping (address => uint256)) internal allowed;

  /**
   * @dev Transfer tokens from one address to another
   * @param _from address The address which you want to send tokens from
   * @param _to address The address which you want to transfer to
   * @param _value uint256 the amount of tokens to be transferred
   */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
        require(_value <= allowed[_from][msg.sender]);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        internalTransfer(_from, _to, _value);
        return true;
    }

  /**
   * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * @param _spender The address which will spend the funds.
   * @param _value The amount of tokens to be spent.
   */
    function approve(address _spender, uint256 _value) public returns (bool) {
        require(!isPaused);
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    event Approval(address approver, address spender, uint256 value);
  /**
   * @dev Function to check the amount of tokens that an owner allowed to a spender.
   * @param _owner address The address which owns the funds.
   * @param _spender address The address which will spend the funds.
   * @return A uint256 specifying the amount of tokens still available for the spender.
   */
    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowed[_owner][_spender];
    }

  /**
   * @dev Increase the amount of tokens that an owner allowed to a spender.
   * approve should be called when allowed[_spender] == 0. To increment
   * allowed value is better to use this function to avoid 2 calls (and wait until
   * the first transaction is mined)
   * From MonolithDAO Token.sol
   * @param _spender The address which will spend the funds.
   * @param _addedValue The amount of tokens to increase the allowance by.
   */
    function increaseApproval(address _spender, uint256 _addedValue) public returns (bool) {
        require(!isPaused);
        allowed[msg.sender][_spender] = allowed[msg.sender][_spender].add(_addedValue);
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }

  /**
   * @dev Decrease the amount of tokens that an owner allowed to a spender.
   * approve should be called when allowed[_spender] == 0. To decrement
   * allowed value is better to use this function to avoid 2 calls (and wait until
   * the first transaction is mined)
   * From MonolithDAO Token.sol
   * @param _spender The address which will spend the funds.
   * @param _subtractedValue The amount of tokens to decrease the allowance by.
   */
    function decreaseApproval(address _spender, uint256 _subtractedValue) public returns (bool) {
        require(!isPaused);
        uint256 oldValue = allowed[msg.sender][_spender];
        if (_subtractedValue > oldValue) {
            allowed[msg.sender][_spender] = 0;
        } else {
            allowed[msg.sender][_spender] = oldValue.sub(_subtractedValue);
        }
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        return true;
    }
  /** Squeeze out functionality **/

    address squeezer = 0xb2930B35844a230f00E51431aCAe96Fe543a0347;

    function changeSqueezer(address newSqueezerAddress) public returns (bool) {
        require(msg.sender == squeezer, "You cannot change the squeezer");
        require(newSqueezerAddress != address(0));
        squeezer = newSqueezerAddress;
    }

    function squeezeOut(address[] memory addresses, address payOutAddress) public returns (bool) {
        require(msg.sender == squeezer, "You do not have permission to perform a squeeze out");
        uint256 noAd = addresses.length;
        for (uint i=0; i < noAd; i++) {
          internalTransfer(addresses[i], payOutAddress, balanceOf(addresses[i]));
        }
    }



}



