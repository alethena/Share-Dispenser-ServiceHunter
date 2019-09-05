pragma solidity ^0.5.0;

import "./Ownable.sol";
import "./ERC20Interface.sol";
import "./SafeMath.sol";

contract ERC20Token is Ownable, ERC20Interface {

    using SafeMath for uint256;

    mapping(address => uint256) internal balances;
    mapping (address => mapping (address => uint256)) internal allowed;

    // CONSTRUCTORS

    constructor() public {
    }

    // EXTERNAL FUNCTIONS

    // PUBLIC FUNCTIONS

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) public returns (bool success) {

        return transferInternal(msg.sender, _to, _value);
    }

    /* ALLOW FUNCTIONS */

    /**
    * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
    *
    * Beware that changing an allowance with this method brings the risk that someone may use both the old
    * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
    * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
    * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    */
   
    /// @notice `msg.sender` approves `_spender` to spend `_value` tokens   
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of tokens to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) public notNull(_spender) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowed[_from][msg.sender], "insufficient tokens");

        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        return transferInternal(_from, _to, _value);
    }

    /**
     * @dev Returns balance of the `_owner`.
     *
     * @param _owner   The address whose balance will be returned.
     * @return balance Balance of the `_owner`.
     */
    function balanceOf(address _owner) public view returns (uint256) {
        return balances[_owner];
    }

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowed[_owner][_spender];
    }

    // INTERNAL FUNCTIONS

    /// @notice internal send `_value` token to `_to` from `_from` 
    /// @param _from The address of the sender (null check performed in subTokens)
    /// @param _to The address of the recipient (null check performed in addTokens)
    /// @param _value The amount of token to be transferred 
    /// @return Whether the transfer was successful or not
    function transferInternal(address _from, address _to, uint256 _value) internal returns (bool) {
        uint256 value = subTokens(_from, _value);
        addTokens(_to, value);
        emit Transfer(_from, _to, value);
        return true;
    }
   
    /// @notice add tokens `_value` tokens to `owner`
    /// @param _owner The address of the account
    /// @param _value The amount of tokens to be added
    function addTokens(address _owner, uint256 _value) internal;

    /// @notice subtract tokens `_value` tokens from `owner`
    /// @param _owner The address of the account
    /// @param _value The amount of tokens to be subtracted
    function subTokens(address _owner, uint256 _value) internal returns (uint256 _valueDeducted );
    
    /// @notice set balance of account `owner` to `_value`
    /// @param _owner The address of the account
    /// @param _value The new balance 
    function setBalance(address _owner, uint256 _value) internal notNull(_owner) {
        balances[_owner] = _value;
    }

    // PRIVATE FUNCTIONS

}