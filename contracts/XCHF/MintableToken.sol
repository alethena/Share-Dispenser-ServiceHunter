pragma solidity ^0.5.0;
// produced by the Solididy File Flattener (c) David Appleton 2018
// contact : dave@akomba.com
// released under Apache 2.0 licence
// input  C:\projects\BTCS.CHFToken\contracts\Chftoken\CryptoFranc.sol
// flattened :  Wednesday, 24-Oct-18 14:07:18 UTC
import "./PausableToken.sol";

contract MintableToken is PausableToken
{
    using SafeMath for uint256;

    address public minter; // minter

    uint256 internal minted; // total minted tokens
    uint256 internal burned; // total burned tokens

    // MODIFIERS

    modifier onlyMinter {
        assert(msg.sender == minter);
        _; 
    }

    constructor() public {
        minter = msg.sender;   // Set the owner to minter
    }

    // EXTERNAL FUNCTIONS

    // PUBLIC FUNCTIONS

    /// @dev  mint tokens to address
    /// @notice mint `_value` token to `_to`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be minted
    function mint(address _to, uint256 _value) public notNull(_to) onlyMinter {
        addTokens(_to, _value);
        notifyMinted(_to, _value);
    }

    /// @dev burn tokens, e.g. when migrating
    /// @notice burn `_value` token to `_to`
    /// @param _value The amount of token to be burned from the callers account
    function burn(uint256 _value) public whenNotPaused {
        uint256 value = subTokens(msg.sender, _value);
        notifyBurned(msg.sender, value);
    }

    /// @dev transfer minter to new address
    /// @notice transfer minter addres from  `minter` to `_newMinter`
    /// @param _newMinter The address of the recipient
    function transferMinter(address _newMinter) public notNull(_newMinter) onlyOwner {
        address oldMinter = minter;
        minter = _newMinter;
        emit TransferMinter(oldMinter, _newMinter);
    }

    // INTERNAL FUNCTIONS

    /// @dev update burned and emit Transfer event of burned tokens
    /// @notice burn `_value` token from `_owner`
    /// @param _owner The address of the owner
    /// @param _value The amount of token burned
    function notifyBurned(address _owner, uint256 _value) internal {
        burned = burned.add(_value);
        emit Transfer(_owner, address(0), _value);
    }

    /// @dev update burned and emit Transfer event of burned tokens
    /// @notice mint `_value` token to `_to`
    /// @param _to The address of the recipient
    /// @param _value The amount of token minted
    function notifyMinted(address _to, uint256 _value) internal {
        minted = minted.add(_value);
        emit Transfer(address(0), _to, _value);
    }

    /// @dev helper function to update token supply state and emit events 
    /// @notice checkMintOrBurn for account `_owner` tokens chainging  from `_balanceBefore` to `_balanceAfter`
    /// @param _owner The address of the owner
    /// @param _balanceBefore The balance before the transaction
    /// @param _balanceAfter The balance after the tranaaction
    function checkMintOrBurn(address _owner, uint256 _balanceBefore, uint256 _balanceAfter) internal {
        if (_balanceBefore > _balanceAfter) {
            uint256 burnedTokens = _balanceBefore.sub(_balanceAfter);
            notifyBurned(_owner, burnedTokens);
        } else if (_balanceBefore < _balanceAfter) {
            uint256 mintedTokens = _balanceAfter.sub(_balanceBefore);
            notifyMinted(_owner, mintedTokens);
        }
    }

    /// @dev return total amount of tokens
    function totalSupply() public view returns(uint256 supply) {
        return minted.sub(burned);
    }

    // PRIVATE FUNCTIONS

    // EVENTS
    
    event TransferMinter(address indexed from, address indexed to);
}

