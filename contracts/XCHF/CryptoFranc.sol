pragma solidity ^0.5.0;
import "./MintableToken.sol";
import "./MigrationAgent.sol";
import "./Operator.sol";
import "./InterestRateNone.sol";

contract CryptoFranc is MintableToken, MigrationAgent, Operator, InterestRateNone {

    using SafeMath for uint256;

    string constant public name = "CryptoFranc";
    string constant public symbol = "XCHF";
    uint256 constant public decimals = 18;
    string constant public version = "1.0.0.0";
    uint256 public dustAmount;

    // Changes as the token is converted to the next vintage
    string public currentFullName;
    string public announcedFullName;
    uint256 public currentMaturityDate;
    uint256 public announcedMaturityDate;
    uint256 public currentTermEndDate;
    uint256 public announcedTermEndDate;
    InterestRateInterface public currentTerms;
    InterestRateInterface public announcedTerms;

    mapping(address => uint256) internal compoundedInterestFactor;

    // CONSTRUCTORS

    constructor(string memory _initialFullName, uint256 _dustAmount) public {
        // initially, there is no interest. This contract has an interest-free default implementation
        // of the InterestRateInterface. Having this internalized saves gas in comparison to having an
        // external, separate smart contract.
        currentFullName = _initialFullName;
        announcedFullName = _initialFullName;
        dustAmount = _dustAmount;    
        currentTerms = this;
        announcedTerms = this;
        announcedMaturityDate = block.timestamp;
        announcedTermEndDate = block.timestamp;
    }

    // EXTERNAL FUNCTIONS

    // PUBLIC FUNCTIONS

    /// @dev Invoked by the issuer to convert all the outstanding tokens into bonds of the latest vintage.
    /// @param _newName Name of announced bond
    /// @param _newTerms Address of announced bond
    /// @param _newMaturityDate Maturity Date of announced bond
    /// @param _newTermEndDate End Date of announced bond
    function announceRollover(string memory _newName, address _newTerms, uint256 _newMaturityDate, uint256 _newTermEndDate) public notNull(_newTerms) onlyOperator {
        // a new term can not be announced before the current is expired
        require(block.timestamp >= announcedMaturityDate);

        // for test purposes
        uint256 newMaturityDate;
        if (_newMaturityDate == 0)
            newMaturityDate = block.timestamp;
        else
            newMaturityDate = _newMaturityDate;

        // new newMaturityDate must be at least or greater than the existing announced terms end date
        require(newMaturityDate >= announcedTermEndDate);

        //require new term dates not too far in the future
        //this is to prevent severe operator time calculaton errors
        require(newMaturityDate <= block.timestamp.add(100 days),"sanitycheck on newMaturityDate");
        require(newMaturityDate <= _newTermEndDate,"term must start before it ends");
        require(_newTermEndDate <= block.timestamp.add(200 days),"sanitycheck on newTermEndDate");

        InterestRateInterface terms = InterestRateInterface(_newTerms);
        
        // ensure that _newTerms begins at the compoundLevel that the announcedTerms ends
        // they must align
        uint256 newBeginLevel = terms.getCompoundingLevelDate(newMaturityDate);
        uint256 annEndLevel = announcedTerms.getCompoundingLevelDate(newMaturityDate);
        require(annEndLevel == newBeginLevel,"new initialCompoundingLevel <> old finalCompoundingLevel");

        //rollover
        currentTerms = announcedTerms;
        currentFullName = announcedFullName;
        currentMaturityDate = announcedMaturityDate;
        currentTermEndDate = announcedTermEndDate;
        announcedTerms = terms;
        announcedFullName = _newName;
        announcedMaturityDate = newMaturityDate;
        announcedTermEndDate = _newTermEndDate;

        emit AnnounceRollover(_newName, _newTerms, newMaturityDate, _newTermEndDate);
    }

    /// @dev collectInterest is called to update the internal state of `_owner` balance and force a interest payment
    /// This function does not change the effective amount of the `_owner` as returned by balanceOf
    /// and thus, can be called by anyone willing to pay for the gas.
    /// The designed usage for this function is to allow the CryptoFranc owner to collect interest from inactive accounts, 
    /// since interest collection is updated automatically in normal transfers
    /// calling collectInterest is functional equivalent to transfer 0 tokens to `_owner`
    /// @param _owner The account being updated
    function collectInterest( address _owner) public notNull(_owner) whenNotPaused {
        uint256 rawBalance = super.balanceOf(_owner);
        uint256 adjustedBalance = getAdjustedValue(_owner);
        setBalance(_owner, adjustedBalance);
        checkMintOrBurn(_owner, rawBalance, adjustedBalance);
    }

    /*
        MIGRATE FUNCTIONS
     */
    // safe migrate function
    /// @dev migrageFrom is called from the migrating contract `migrationFromContract`
    /// @param _from The account to be migrated into new contract
    /// @param _value The token balance to be migrated
    function migrateFrom(address _from, uint256 _value) public onlyMigrationFromContract returns(bool) {
        addTokens(_from, _value);
        notifyMinted(_from, _value);

        emit MigratedFrom(_from, migrationFromContract, _value);
        return true;
    }

    /// @dev Each user calls the migrate function on the original contract to migrate the users’ tokens to the migration agent migrateFrom on the `migrationToContract` contract
    function migrate() public whenNotPaused {
        require(migrationToContract != 0x0000000000000000000000000000000000000000, "not in migration mode"); // revert if not in migrate mode
        uint256 value = balanceOf(msg.sender);
        require (value > 0, "no balance"); // revert if not value left to transfer
        value = subTokens(msg.sender, value);
        notifyBurned(msg.sender, value);
        require(MigrationAgent(migrationToContract).migrateFrom(msg.sender, value)==true, "migrateFrom must return true");

        emit MigratedTo(msg.sender, migrationToContract, value);
    }

    /*
        Helper FUNCTIONS
    */

    /// @dev helper function to return foreign tokens accidental send to contract address
    /// @param _tokenaddress Address of foreign ERC20 contract
    /// @param _to Address to send foreign tokens to
    function refundForeignTokens(address _tokenaddress,address _to) public notNull(_to) onlyOperator {
        ERC20Interface token = ERC20Interface(_tokenaddress);
        // transfer current balance for this contract to _to  in token contract
        token.transfer(_to, token.balanceOf(address(this)));
    }

    /// @dev get fullname of active interest contract
    function getFullName() public view returns (string memory) {
        if ((block.timestamp <= announcedMaturityDate))
            return currentFullName;
        else
            return announcedFullName;
    }

    /// @dev get compounding level of an owner account
    /// @param _owner tokens address
    /// @return The compouding level
    function getCompoundingLevel(address _owner) public view returns (uint256) {
        uint256 level = compoundedInterestFactor[_owner];
        if (level == 0) {
            // important note that for InterestRateNone or empty accounts the compoundedInterestFactor is newer stored by setBalance
            return SCALEFACTOR;
        } else {
            return level;
        }
    }

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) public view returns (uint256) {
        return getAdjustedValue(_owner);
    }

    // INTERNAL FUNCTIONS

    /// @notice add tokens `_value` tokens to `owner`
    /// @param _owner The address of the account
    /// @param _value The amount of tokens to be added
    function addTokens(address _owner,uint256 _value) notNull(_owner) internal {
        uint256 rawBalance = super.balanceOf(_owner);
        uint256 adjustedBalance = getAdjustedValue(_owner);
        setBalance(_owner, adjustedBalance.add(_value));
        checkMintOrBurn(_owner, rawBalance, adjustedBalance);
    }

    /// @notice subtract tokens `_value` tokens from `owner`
    /// @param _owner The address of the account
    /// @param _value The amount of tokens to be subtracted
    function subTokens(address _owner, uint256 _value) internal notNull(_owner) returns (uint256 _valueDeducted ) {
        uint256 rawBalance = super.balanceOf(_owner);
        uint256 adjustedBalance = getAdjustedValue(_owner);
        uint256 newBalance = adjustedBalance.sub(_value);
        if (newBalance <= dustAmount) {
            // dont leave balance below dust, empty account
            _valueDeducted = _value.add(newBalance);
            newBalance =  0;
        } else {
            _valueDeducted = _value;
        }
        setBalance(_owner, newBalance);
        checkMintOrBurn(_owner, rawBalance, adjustedBalance);
    }

    /// @notice set balance of account `owner` to `_value`
    /// @param _owner The address of the account
    /// @param _value The new balance 
    function setBalance(address _owner, uint256 _value) internal {
        super.setBalance(_owner, _value);
        // update `owner`s compoundLevel
        if (_value == 0) {
            // stall account release storage
            delete compoundedInterestFactor[_owner];
        } else {
            // only update compoundedInterestFactor when value has changed 
            // important note: for InterestRateNone the compoundedInterestFactor is newer stored because the default value for getCompoundingLevel is SCALEFACTOR
            uint256 currentLevel = getInterestRate().getCurrentCompoundingLevel();
            if (currentLevel != getCompoundingLevel(_owner)) {
                compoundedInterestFactor[_owner] = currentLevel;
            }
        }
    }

    /// @dev get address of active bond
    function getInterestRate() internal view returns (InterestRateInterface) {
        if ((block.timestamp <= announcedMaturityDate))
            return currentTerms;
        else
            return announcedTerms;
    }

    /// @notice get adjusted balance of account `owner`
    /// @param _owner The address of the account
    function getAdjustedValue(address _owner) internal view returns (uint256) {
        uint256 _rawBalance = super.balanceOf(_owner);
        // if _rawBalance is 0 dont perform calculations
        if (_rawBalance == 0)
            return 0;
        // important note: for empty/new account the getCompoundingLevel value is not meaningfull
        uint256 startLevel = getCompoundingLevel(_owner);
        uint256 currentLevel = getInterestRate().getCurrentCompoundingLevel();
        return _rawBalance.mul(currentLevel).div(startLevel);
    }

    /// @notice get adjusted balance of account `owner` at data `date`
    /// @param _owner The address of the account
    /// @param _date The date of the balance NB: MUST be within valid current and announced Terms date range
    function getAdjustedValueDate(address _owner,uint256 _date) public view returns (uint256) {
        uint256 _rawBalance = super.balanceOf(_owner);
        // if _rawBalance is 0 dont perform calculations
        if (_rawBalance == 0)
            return 0;
        // important note: for empty/new account the getCompoundingLevel value is not meaningfull
        uint256 startLevel = getCompoundingLevel(_owner);

        InterestRateInterface dateTerms;
        if (_date <= announcedMaturityDate)
            dateTerms = currentTerms;
        else
            dateTerms = announcedTerms;

        uint256 dateLevel = dateTerms.getCompoundingLevelDate(_date);
        return _rawBalance.mul(dateLevel).div(startLevel);
    }

    // PRIVATE FUNCTIONS

    // EVENTS

    event AnnounceRollover(string newName, address indexed newTerms, uint256 indexed newMaturityDate, uint256 indexed newTermEndDate);
}