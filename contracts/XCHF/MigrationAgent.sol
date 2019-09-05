pragma solidity ^0.5.0;

import "./Ownable.sol";

contract MigrationAgent is Ownable {

    address public migrationToContract; // the contract to migrate to
    address public migrationFromContract; // the conttactto migate from

    // MODIFIERS
    
    modifier onlyMigrationFromContract() {
        require(msg.sender == migrationFromContract, "Only from migration contract");
        _;
    }
    // EXTERNAL FUNCTIONS

    // PUBLIC FUNCTIONS

    /// @dev set contract to migrate to 
    /// @param _toContract Then contract address to migrate to
    function startMigrateToContract(address _toContract) public onlyOwner {
        migrationToContract = _toContract;
        require(MigrationAgent(migrationToContract).isMigrationAgent(), "not a migratable contract");
        emit StartMigrateToContract(address(this), _toContract);
    }

    /// @dev set contract to migrate from
    /// @param _fromConstract Then contract address to migrate from
    function startMigrateFromContract(address _fromConstract) public onlyOwner {
        migrationFromContract = _fromConstract;
        require(MigrationAgent(migrationFromContract).isMigrationAgent(), "not a migratable contract");
        emit StartMigrateFromContract(_fromConstract, address(this));
    }

    /// @dev Each user calls the migrate function on the original contract to migrate the users’ tokens to the migration agent migrateFrom on the `migrationToContract` contract
    function migrate() public;   

    /// @dev migrageFrom is called from the migrating contract `migrationFromContract`
    /// @param _from The account to be migrated into new contract
    /// @param _value The token balance to be migrated
    function migrateFrom(address _from, uint256 _value) public returns(bool);

    /// @dev is a valid migration agent
    /// @return true if contract is a migratable contract
    function isMigrationAgent() public pure returns(bool) {
        return true;
    }

    // INTERNAL FUNCTIONS

    // PRIVATE FUNCTIONS

    // EVENTS

    event StartMigrateToContract(address indexed fromConstract, address indexed toContract);

    event StartMigrateFromContract(address indexed fromConstract, address indexed toContract);

    event MigratedTo(address indexed owner, address indexed _contract, uint256 value);

    event MigratedFrom(address indexed owner, address indexed _contract, uint256 value);
}