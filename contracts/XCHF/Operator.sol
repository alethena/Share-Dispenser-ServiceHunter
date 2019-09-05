pragma solidity ^0.5.0;

import "./Ownable.sol";

contract Operator is Ownable {

    address public operator;

    // MODIFIERS

    /**
     * @dev modifier check for operator
     */
    modifier onlyOperator {
        require(msg.sender == operator, "Only Operator");
        _;
    }

    // CONSTRUCTORS

    constructor() public {
        operator = msg.sender;
    }
    /**
     * @dev Transfer operator to `newOperator`.
     *
     * @param _newOperator   The address of the new operator
     * @return balance Balance of the `_owner`.
     */
    function transferOperator(address _newOperator) public notNull(_newOperator) onlyOwner {
        operator = _newOperator;
        emit TransferOperator(operator, _newOperator);
    }

    // EVENTS
    
    event TransferOperator(address indexed from, address indexed to);
}